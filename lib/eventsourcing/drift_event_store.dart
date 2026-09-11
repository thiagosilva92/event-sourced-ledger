import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

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
  /// [registryFactory] builds a fresh [EventRegistry] with every event type
  /// this store needs to decode registered on it. It must be a **top-level
  /// or static function** (not a method tear-off or a closure capturing
  /// anything) — [readAll] sends it, unevaluated, to a worker isolate for
  /// large result sets, so it has to be safe to run there with no shared
  /// state. It's called once immediately for normal (small-batch) decoding
  /// on this isolate, and again inside a worker isolate only when a batch
  /// is large enough to be worth offloading — see [_isolateDecodeThreshold].
  DriftEventStore(this._db, EventRegistry Function() registryFactory)
    : registry = registryFactory(),
      _registryFactory = registryFactory;

  final AppDatabase _db;
  final EventRegistry registry;
  final EventRegistry Function() _registryFactory;

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

  /// Below this many rows, decoding inline is faster than the fixed cost of
  /// spawning a worker isolate (a few ms) — chosen from the measurements in
  /// `test/performance/projection_rebuild_load_test.dart`, not a guess.
  static const _isolateDecodeThreshold = 500;

  @override
  Future<List<SequencedEvent>> readAll({int afterSequence = 0}) async {
    final rows =
        await (_db.select(_db.eventLogEntries)
              ..where((row) => row.sequence.isBiggerThanValue(afterSequence))
              ..orderBy([(row) => OrderingTerm(expression: row.sequence)]))
            .get();

    final events = rows.length >= _isolateDecodeThreshold
        ? await _decodeInWorkerIsolate(rows)
        : rows.map(_toDomainEvent).toList();

    return [
      for (var i = 0; i < rows.length; i++)
        SequencedEvent(rows[i].sequence, events[i]),
    ];
  }

  /// Decodes a large batch of rows off this isolate, so folding thousands
  /// of events into a projection (`ProjectionRunner.rebuild`, the reason
  /// this exists) doesn't block the isolate driving the UI. Measured cost
  /// of *not* doing this: see `docs/concurrency.md` and the "before" numbers
  /// in `test/performance/projection_rebuild_load_test.dart`.
  ///
  /// Rebuilds a fresh [EventRegistry] via [_registryFactory] inside the
  /// worker isolate rather than sending [registry] itself — registered
  /// deserializers are arbitrary closures from feature code, and requiring
  /// every one of them to be provably isolate-safe is a much easier bar to
  /// clear for "one designated top-level function" than for "every closure
  /// anyone ever registers".
  Future<List<DomainEvent>> _decodeInWorkerIsolate(
    List<EventLogRow> rows,
  ) async {
    final registryFactory = _registryFactory;
    final decoded = await Isolate.run(() {
      final isolateRegistry = registryFactory();
      return rows
          .map((row) => _toDomainEventWith(row, isolateRegistry))
          .toList();
    });
    return decoded;
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

  DomainEvent _toDomainEvent(EventLogRow row) =>
      _toDomainEventWith(row, registry);

  /// Closes the underlying database. Does not delete data on disk.
  Future<void> dispose() async {
    await _changes.close();
    await _db.close();
  }
}

/// Top-level so it can run inside a worker isolate (see
/// [DriftEventStore._decodeInWorkerIsolate]) without capturing a
/// [DriftEventStore] instance — only [row] and [registry] cross the
/// boundary, both of which are plain data.
DomainEvent _toDomainEventWith(EventLogRow row, EventRegistry registry) {
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
