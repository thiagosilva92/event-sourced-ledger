import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

// --- A minimal, domain-neutral sample used to exercise the core. -------------

int _seq = 0;
Hlc _ts() => Hlc(wallMillis: 1000 + _seq, counter: 0, nodeId: 'test');
String _id() => 'evt-${(_seq++).toString().padLeft(4, '0')}';

base class TallyStarted extends DomainEvent {
  TallyStarted({required super.aggregateId, required this.label})
    : super(eventId: _id(), timestamp: _ts());

  final String label;

  @override
  String get eventType => 'tally.started';

  @override
  Map<String, Object?> toPayload() => {'label': label};
}

base class TallyIncremented extends DomainEvent {
  TallyIncremented({required super.aggregateId, required this.by, Hlc? at})
    : super(eventId: _id(), timestamp: at ?? _ts());

  final int by;

  @override
  String get eventType => 'tally.incremented';

  @override
  Map<String, Object?> toPayload() => {'by': by};
}

class Tally extends Aggregate<DomainEvent> {
  Tally(super.id);

  String label = '';
  int total = 0;
  bool _started = false;

  void start(String label) {
    if (_started) throw StateError('already started');
    raise(TallyStarted(aggregateId: id, label: label));
  }

  void add(int amount) {
    if (!_started) throw StateError('not started');
    if (amount <= 0) throw ArgumentError('amount must be positive');
    raise(TallyIncremented(aggregateId: id, by: amount));
  }

  @override
  void applyEvent(DomainEvent event) {
    switch (event) {
      case TallyStarted(:final label):
        this.label = label;
        _started = true;
      case TallyIncremented(:final by):
        total += by;
    }
  }
}

class GrandTotalProjection extends Projection<int> {
  int _total = 0;

  @override
  int get state => _total;

  @override
  void handle(DomainEvent event) {
    if (event is TallyIncremented) _total += event.by;
  }

  @override
  void clear() => _total = 0;
}

void main() {
  setUp(() => _seq = 0);

  group('Aggregate', () {
    test('raise applies state and queues pending events', () {
      final tally = Tally('t1')
        ..start('groceries')
        ..add(3)
        ..add(2);

      expect(tally.label, 'groceries');
      expect(tally.total, 5);
      expect(tally.version, 3);
      expect(tally.pendingEvents, hasLength(3));
    });

    test('markEventsCommitted clears pending but keeps state and version', () {
      final tally = Tally('t1')
        ..start('x')
        ..add(1)
        ..markEventsCommitted();

      expect(tally.hasPendingEvents, isFalse);
      expect(tally.version, 2);
      expect(tally.total, 1);
    });

    test('loadFromHistory rebuilds state without pending events', () {
      final source = Tally('t1')
        ..start('rent')
        ..add(10);
      final history = source.pendingEvents;

      final rebuilt = Tally('t1')..loadFromHistory(history);

      expect(rebuilt.total, 10);
      expect(rebuilt.label, 'rent');
      expect(rebuilt.version, 2);
      expect(rebuilt.hasPendingEvents, isFalse);
    });

    test('loadFromSnapshot resumes from a version plus a tail', () {
      final tally = Tally('t1')..start('x');
      tally.markEventsCommitted();
      tally
        ..add(4)
        ..add(6);
      final tail = tally.pendingEvents;

      final rebuilt = Tally('t1')..loadFromSnapshot(1, tail);
      expect(rebuilt.version, 3);
      expect(rebuilt.total, 10);
    });

    test('rejects events belonging to another aggregate', () {
      final foreign = TallyIncremented(aggregateId: 'other', by: 1);
      expect(() => Tally('t1').loadFromHistory([foreign]), throwsArgumentError);
    });

    test('rejects loadFromHistory on a used aggregate', () {
      final tally = Tally('t1')..start('x');
      expect(() => tally.loadFromHistory([]), throwsStateError);
    });
  });

  group('InMemoryEventStore', () {
    late InMemoryEventStore store;

    setUp(() => store = InMemoryEventStore());
    tearDown(() => store.dispose());

    test('append then readAggregate returns events in order', () async {
      final tally = Tally('t1')
        ..start('x')
        ..add(1);
      await store.append('t1', tally.pendingEvents);

      final read = await store.readAggregate('t1');
      expect(read.map((e) => e.eventType), [
        'tally.started',
        'tally.incremented',
      ]);
    });

    test('optimistic concurrency: stale expectedVersion is rejected', () async {
      final a = Tally('t1')..start('x');
      await store.append('t1', a.pendingEvents, expectedVersion: 0);

      final b = Tally('t1')..start('y');
      expect(
        () => store.append('t1', b.pendingEvents, expectedVersion: 0),
        throwsA(isA<ConcurrencyError>()),
      );
    });

    test('append rejects events for a different aggregate', () async {
      final foreign = TallyIncremented(aggregateId: 'other', by: 1);
      expect(() => store.append('t1', [foreign]), throwsArgumentError);
    });

    test('merge skips already-seen event ids and is idempotent', () async {
      final tally = Tally('t1')
        ..start('x')
        ..add(1);
      final events = tally.pendingEvents;

      final first = await store.merge(events);
      final second = await store.merge(events);

      expect(first, 2);
      expect(second, 0);
      expect(await store.readAggregate('t1'), hasLength(2));
    });

    test('readAll paginates by sequence', () async {
      final t = Tally('t1')
        ..start('x')
        ..add(1)
        ..add(1);
      await store.append('t1', t.pendingEvents);

      final tail = await store.readAll(afterSequence: 1);
      expect(tail.map((s) => s.sequence), [2, 3]);
    });

    test('readSince is inclusive of the cursor and orders by HLC', () async {
      final t = Tally('t1')
        ..start('x')
        ..add(1)
        ..add(1);
      final events = t.pendingEvents;
      await store.append('t1', events);

      final since = events.first.timestamp;
      final result = await store.readSince(since);

      // Inclusive: the event at the cursor comes back too. Harmless — the
      // receiving side's merge() de-duplicates by eventId.
      expect(result, hasLength(3));
      expect(result.first.timestamp, since);
      expect(result[1].timestamp > since, isTrue);
    });

    test(
      'characterization: a scalar cursor can still miss an event that ties '
      'it on wallMillis/counter but sorts before it by nodeId — this is why '
      'sync/ must track per-node cursors, not just call readSince inclusive',
      () async {
        // Two devices, never in contact, independently reach the same
        // (wallMillis, counter) pair. Hlc's total order then falls back to
        // nodeId, which is arbitrary with respect to "was this seen before".
        // The inclusive `>=` fix (see the test above) only covers the exact
        // boundary event; it cannot rescue this case, because
        // neverSyncedTimestamp is genuinely less than cursorTimestamp.
        const cursorTimestamp = Hlc(
          wallMillis: 5000,
          counter: 2,
          nodeId: 'zzz-already-synced-device',
        );
        const neverSyncedTimestamp = Hlc(
          wallMillis: 5000,
          counter: 2,
          nodeId: 'aaa-new-device', // sorts before 'zzz...' at the same tick
        );
        expect(neverSyncedTimestamp < cursorTimestamp, isTrue); // the trap

        final neverSyncedEvent = TallyIncremented(
          aggregateId: 't1',
          by: 2,
          at: neverSyncedTimestamp,
        );
        await store.merge([
          TallyIncremented(aggregateId: 't1', by: 1, at: cursorTimestamp),
          neverSyncedEvent,
        ]);

        final result = await store.readSince(cursorTimestamp);

        // Documents the known gap — see EventStore.readSince's doc comment.
        expect(
          result.map((e) => e.eventId),
          isNot(contains(neverSyncedEvent.eventId)),
        );
      },
    );

    test('changes stream emits on append and merge', () async {
      final seen = <String>[];
      final sub = store.changes.listen((e) => seen.add(e.eventType));

      final t = Tally('t1')..start('x');
      await store.append('t1', t.pendingEvents);
      await store.merge([TallyIncremented(aggregateId: 't1', by: 1)]);
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['tally.started', 'tally.incremented']);
      await sub.cancel();
    });
  });

  group('EventRegistry', () {
    test('round-trips an event through register/deserialize', () {
      final registry = EventRegistry()
        ..register(
          'tally.incremented',
          (meta, payload) => TallyIncremented(
            aggregateId: meta.aggregateId,
            by: payload['by']! as int,
          ),
        );

      final rebuilt = registry.deserialize(
        'tally.incremented',
        const EventMetadata(
          eventId: 'e1',
          aggregateId: 't1',
          timestamp: Hlc(wallMillis: 1, counter: 0, nodeId: 'n'),
        ),
        {'by': 7},
      );

      expect(rebuilt, isA<TallyIncremented>());
      expect((rebuilt as TallyIncremented).by, 7);
    });

    test('unknown type throws a helpful error', () {
      expect(
        () => EventRegistry().deserialize(
          'nope',
          const EventMetadata(
            eventId: 'e',
            aggregateId: 'a',
            timestamp: Hlc.zero('n'),
          ),
          const {},
        ),
        throwsA(isA<UnknownEventTypeError>()),
      );
    });

    test('double registration throws', () {
      final registry = EventRegistry()
        ..register('x', (m, p) => throw UnimplementedError());
      expect(
        () => registry.register('x', (m, p) => throw UnimplementedError()),
        throwsStateError,
      );
    });
  });

  group('ProjectionRunner', () {
    late InMemoryEventStore store;
    late GrandTotalProjection projection;
    late ProjectionRunner runner;

    setUp(() {
      store = InMemoryEventStore();
      projection = GrandTotalProjection();
      runner = ProjectionRunner(store, [projection]);
    });
    tearDown(() => store.dispose());

    test('rebuild folds the whole log', () async {
      final t = Tally('t1')
        ..start('x')
        ..add(4)
        ..add(6);
      await store.append('t1', t.pendingEvents);

      await runner.rebuild();

      expect(projection.state, 10);
      expect(projection.lastSequence, 3);
    });

    test('catchUp applies only new events, no double counting', () async {
      final t = Tally('t1')
        ..start('x')
        ..add(5);
      await store.append('t1', t.pendingEvents);
      await runner.rebuild();

      await store.merge([TallyIncremented(aggregateId: 't1', by: 3)]);
      await runner.catchUp();

      expect(projection.state, 8);

      await runner.catchUp(); // no-op
      expect(projection.state, 8);
    });

    test('rebuild is deterministic and idempotent', () async {
      final t = Tally('t1')
        ..start('x')
        ..add(2)
        ..add(2);
      await store.append('t1', t.pendingEvents);

      await runner.rebuild();
      final first = projection.state;
      await runner.rebuild();

      expect(projection.state, first);
    });
  });
}
