import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

import 'support/tally_fixture.dart';

/// Behavioral contract every [EventStore] implementation must satisfy.
///
/// Run once against `InMemoryEventStore` and once against `DriftEventStore`
/// (see the two `*_event_store_test.dart` files next to this one) so both
/// stay interchangeable from the rest of the app's point of view. A new
/// `EventStore` behavior belongs here, not bolted onto only one
/// implementation's test file — otherwise the two can silently drift apart.
void runEventStoreContractTests(
  EventStore Function() createStore, {
  Future<void> Function(EventStore store)? disposeStore,
}) {
  late EventStore store;

  setUp(() {
    resetTallyFixture();
    store = createStore();
  });

  tearDown(() async {
    if (disposeStore != null) await disposeStore(store);
  });

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
    // And nothing from the rejected append was written.
    expect(await store.readAggregate('t1'), hasLength(1));
  });

  test('append rejects events for a different aggregate', () async {
    final foreign = TallyIncremented.raised(aggregateId: 'other', by: 1);
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
      // The inclusive `>=` fix only covers the exact boundary event; it
      // cannot rescue this case, because neverSyncedTimestamp is genuinely
      // less than cursorTimestamp.
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

      final neverSyncedEvent = TallyIncremented.raised(
        aggregateId: 't1',
        by: 2,
        at: neverSyncedTimestamp,
      );
      await store.merge([
        TallyIncremented.raised(aggregateId: 't1', by: 1, at: cursorTimestamp),
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
    await store.merge([TallyIncremented.raised(aggregateId: 't1', by: 1)]);
    await Future<void>.delayed(Duration.zero);

    expect(seen, ['tally.started', 'tally.incremented']);
    await sub.cancel();
  });

  test('latestSequence tracks the highest sequence handed out', () async {
    expect(await store.latestSequence(), 0);

    final t = Tally('t1')
      ..start('x')
      ..add(1);
    await store.append('t1', t.pendingEvents);

    expect(await store.latestSequence(), 2);
  });
}
