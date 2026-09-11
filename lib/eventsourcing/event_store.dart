import 'dart:async';

import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/eventsourcing/domain_event.dart';
import 'package:meta/meta.dart';

/// An event together with the global append order the local store gave it.
@immutable
final class SequencedEvent {
  const SequencedEvent(this.sequence, this.event);

  /// Monotonically increasing per store; the local write log order.
  final int sequence;
  final DomainEvent event;
}

/// Raised when an append's [expectedVersion] does not match the aggregate's
/// current version — a concurrent local write happened in between.
class ConcurrencyError extends Error {
  ConcurrencyError({
    required this.aggregateId,
    required this.expectedVersion,
    required this.actualVersion,
  });

  final String aggregateId;
  final int expectedVersion;
  final int actualVersion;

  @override
  String toString() =>
      'ConcurrencyError: $aggregateId expected version $expectedVersion '
      'but store is at $actualVersion';
}

/// Append-only log of [DomainEvent]s plus the reads projections and sync need.
abstract interface class EventStore {
  /// Appends [events] for a single aggregate atomically.
  ///
  /// When [expectedVersion] is given it must equal the number of events
  /// already stored for that aggregate, or [ConcurrencyError] is thrown and
  /// nothing is written.
  Future<void> append(
    String aggregateId,
    List<DomainEvent> events, {
    int? expectedVersion,
  });

  /// Ingests events that originated on another device. Already-seen event ids
  /// are skipped. No version check — merge order is decided by the HLC.
  Future<int> merge(Iterable<DomainEvent> events);

  /// All events for one aggregate, in append order.
  Future<List<DomainEvent>> readAggregate(String aggregateId);

  /// The whole log in append order, optionally only what was appended after
  /// [afterSequence]. Used to (re)build projections.
  Future<List<SequencedEvent>> readAll({int afterSequence = 0});

  /// Events with an HLC timestamp strictly greater than [since], ordered by
  /// HLC then eventId, capped at [limit]. Used by the sync push/pull cursor.
  Future<List<DomainEvent>> readSince(Hlc? since, {int limit = 500});

  /// Highest sequence number handed out so far (0 when empty).
  Future<int> latestSequence();

  /// Broadcasts every event as it becomes durable (local append or merge).
  Stream<DomainEvent> get changes;
}

/// In-memory [EventStore] for tests and for composing higher layers before
/// the Drift-backed store exists.
class InMemoryEventStore implements EventStore {
  final List<SequencedEvent> _log = [];
  final Set<String> _seenEventIds = {};
  final StreamController<DomainEvent> _changes =
      StreamController<DomainEvent>.broadcast();

  int _sequence = 0;

  @override
  Stream<DomainEvent> get changes => _changes.stream;

  @override
  Future<void> append(
    String aggregateId,
    List<DomainEvent> events, {
    int? expectedVersion,
  }) async {
    if (events.isEmpty) return;
    if (events.any((e) => e.aggregateId != aggregateId)) {
      throw ArgumentError('all events must belong to $aggregateId');
    }
    if (expectedVersion != null) {
      final current = _log
          .where((s) => s.event.aggregateId == aggregateId)
          .length;
      if (current != expectedVersion) {
        throw ConcurrencyError(
          aggregateId: aggregateId,
          expectedVersion: expectedVersion,
          actualVersion: current,
        );
      }
    }
    events.forEach(_appendOne);
  }

  @override
  Future<int> merge(Iterable<DomainEvent> events) async {
    var merged = 0;
    for (final event in events) {
      if (_seenEventIds.contains(event.eventId)) continue;
      _appendOne(event);
      merged++;
    }
    return merged;
  }

  void _appendOne(DomainEvent event) {
    _log.add(SequencedEvent(++_sequence, event));
    _seenEventIds.add(event.eventId);
    _changes.add(event);
  }

  @override
  Future<List<DomainEvent>> readAggregate(String aggregateId) async => _log
      .where((s) => s.event.aggregateId == aggregateId)
      .map((s) => s.event)
      .toList();

  @override
  Future<List<SequencedEvent>> readAll({int afterSequence = 0}) async =>
      _log.where((s) => s.sequence > afterSequence).toList();

  @override
  Future<List<DomainEvent>> readSince(Hlc? since, {int limit = 500}) async {
    final events =
        _log.map((s) => s.event).where((e) {
          if (since == null) return true;
          return e.timestamp > since;
        }).toList()..sort((a, b) {
          final byClock = a.timestamp.compareTo(b.timestamp);
          return byClock != 0 ? byClock : a.eventId.compareTo(b.eventId);
        });
    return events.take(limit).toList();
  }

  @override
  Future<int> latestSequence() async => _sequence;

  /// Releases the broadcast controller. Call from test tearDown.
  Future<void> dispose() => _changes.close();
}
