import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/eventsourcing/domain_event.dart';
import 'package:ledger/eventsourcing/event_store.dart';

/// [EventStore] backed by a Drift/SQLite `event_log` table.
///
/// Behaves identically to `InMemoryEventStore` from the caller's point of
/// view — both are exercised by the same contract test suite
/// (`test/eventsourcing/event_store_contract.dart`) — but persists across
/// app restarts and scales past what fits comfortably in memory.
///
/// Unlike the in-memory store, this one does not keep the original
/// `DomainEvent` objects: every read reconstructs them from stored JSON via
/// [registry], so every event type used with this store must be registered
/// there first.
class DriftEventStore implements EventStore {
  DriftEventStore(this._db, this.registry);

  final AppDatabase _db;
  final EventRegistry registry;

  final StreamController<DomainEvent> _changes =
      StreamController<DomainEvent>.broadcast();

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

    await _db.transaction(() async {
      if (expectedVersion != null) {
        final current = await _versionOf(aggregateId);
        if (current != expectedVersion) {
          throw ConcurrencyError(
            aggregateId: aggregateId,
            expectedVersion: expectedVersion,
            actualVersion: current,
          );
        }
      }
      for (final event in events) {
        await _insert(event);
      }
    });

    events.forEach(_changes.add);
  }

  @override
  Future<int> merge(Iterable<DomainEvent> events) async {
    final candidates = events.toList();
    if (candidates.isEmpty) return 0;

    final inserted = await _db.transaction(() async {
      final ids = candidates.map((e) => e.eventId).toList();
      final existing = await (_db.select(
        _db.eventLogEntries,
      )..where((row) => row.eventId.isIn(ids))).map((row) => row.eventId).get();
      final alreadySeen = existing.toSet();

      final toInsert = candidates
          .where((e) => !alreadySeen.contains(e.eventId))
          .toList();
      for (final event in toInsert) {
        await _insert(event);
      }
      return toInsert;
    });

    inserted.forEach(_changes.add);
    return inserted.length;
  }

  @override
  Future<List<DomainEvent>> readAggregate(String aggregateId) async {
    final rows =
        await (_db.select(_db.eventLogEntries)
              ..where((row) => row.aggregateId.equals(aggregateId))
              ..orderBy([(row) => OrderingTerm(expression: row.sequence)]))
            .get();
    return rows.map(_toDomainEvent).toList();
  }

  @override
  Future<List<SequencedEvent>> readAll({int afterSequence = 0}) async {
    final rows =
        await (_db.select(_db.eventLogEntries)
              ..where((row) => row.sequence.isBiggerThanValue(afterSequence))
              ..orderBy([(row) => OrderingTerm(expression: row.sequence)]))
            .get();
    return rows
        .map((row) => SequencedEvent(row.sequence, _toDomainEvent(row)))
        .toList();
  }

  @override
  Future<List<DomainEvent>> readSince(Hlc? since, {int limit = 500}) async {
    final query = _db.select(_db.eventLogEntries)
      ..orderBy([
        (row) => OrderingTerm(expression: row.hlcWallMillis),
        (row) => OrderingTerm(expression: row.hlcCounter),
        (row) => OrderingTerm(expression: row.hlcNodeId),
        (row) => OrderingTerm(expression: row.eventId),
      ])
      ..limit(limit);

    if (since != null) {
      // Mirrors Hlc.compareTo: wallMillis, then counter, then nodeId.
      // Inclusive (`>=` on the final term) — see EventStore.readSince's doc
      // comment for why, and for the limit of what this alone guarantees.
      query.where(
        (row) =>
            row.hlcWallMillis.isBiggerThanValue(since.wallMillis) |
            (row.hlcWallMillis.equals(since.wallMillis) &
                row.hlcCounter.isBiggerThanValue(since.counter)) |
            (row.hlcWallMillis.equals(since.wallMillis) &
                row.hlcCounter.equals(since.counter) &
                row.hlcNodeId.isBiggerOrEqualValue(since.nodeId)),
      );
    }

    final rows = await query.get();
    return rows.map(_toDomainEvent).toList();
  }

  @override
  Future<int> latestSequence() async {
    final maxSequence = _db.eventLogEntries.sequence.max();
    final row = await (_db.selectOnly(
      _db.eventLogEntries,
    )..addColumns([maxSequence])).getSingleOrNull();
    final value = row?.read(maxSequence) ?? 0;
    return value;
  }

  Future<int> _versionOf(String aggregateId) async {
    final rowCount = _db.eventLogEntries.sequence.count();
    final query = _db.selectOnly(_db.eventLogEntries)
      ..addColumns([rowCount])
      ..where(_db.eventLogEntries.aggregateId.equals(aggregateId));
    final row = await query.getSingle();
    final value = row.read(rowCount) ?? 0;
    return value;
  }

  Future<void> _insert(DomainEvent event) {
    return _db
        .into(_db.eventLogEntries)
        .insert(
          EventLogEntriesCompanion.insert(
            eventId: event.eventId,
            aggregateId: event.aggregateId,
            eventType: event.eventType,
            hlcWallMillis: event.timestamp.wallMillis,
            hlcCounter: event.timestamp.counter,
            hlcNodeId: event.timestamp.nodeId,
            payloadJson: jsonEncode(event.toPayload()),
          ),
        );
  }

  DomainEvent _toDomainEvent(EventLogRow row) {
    final metadata = EventMetadata(
      eventId: row.eventId,
      aggregateId: row.aggregateId,
      timestamp: Hlc(
        wallMillis: row.hlcWallMillis,
        counter: row.hlcCounter,
        nodeId: row.hlcNodeId,
      ),
    );
    final payload = jsonDecode(row.payloadJson) as Map<String, Object?>;
    return registry.deserialize(row.eventType, metadata, payload);
  }

  /// Closes the underlying database. Does not delete data on disk.
  Future<void> dispose() async {
    await _changes.close();
    await _db.close();
  }
}
