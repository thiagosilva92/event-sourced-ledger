import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/eventsourcing/drift_event_store.dart';

import '../eventsourcing/support/tally_fixture.dart';

/// Load / stress tests for [DriftEventStore], answering: "does the local
/// event log survive thousands of events and a burst of concurrent
/// writers without corrupting data or grinding to a halt?"
///
/// This runs against an in-memory SQLite connection, same as every other
/// Drift test in this repo, so numbers here are about the store's own
/// logic (batching, transactions, indexing), not disk I/O — a real device
/// will be slower. `lib/main_debug_smoke_test.dart` is what proves the
/// real on-disk path works at all; this is what proves it holds up at
/// scale once it does.
///
/// Time budgets are intentionally generous for a shared CI runner. The
/// point of printing the actual duration alongside every assertion is to
/// make a regression visible in the test output long before it's ever
/// close to failing the budget.
void main() {
  setUp(resetTallyFixture);

  DriftEventStore newStore() => DriftEventStore(
    AppDatabase.forTesting(NativeDatabase.memory()),
    buildTallyRegistry,
  );

  test(
    'appends thousands of events across many aggregates within budget',
    () async {
      final store = newStore();
      addTearDown(store.dispose);

      const aggregateCount = 50;
      const eventsPerAggregate = 100; // + 1 "started" event each
      final stopwatch = Stopwatch()..start();

      for (var a = 0; a < aggregateCount; a++) {
        final id = 'agg-$a';
        final tally = Tally(id)..start('load test $a');
        for (var e = 0; e < eventsPerAggregate; e++) {
          tally.add(1);
        }
        await store.append(id, tally.pendingEvents);
      }

      stopwatch.stop();
      const total = aggregateCount * (eventsPerAggregate + 1);
      print('appended $total events in ${stopwatch.elapsedMilliseconds}ms');

      expect(await store.latestSequence(), total);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 15)));
    },
  );

  test('merge() absorbs a large offline backlog in one call', () async {
    final store = newStore();
    addTearDown(store.dispose);

    const backlogSize = 10000;
    final events = <TallyIncremented>[];
    for (var i = 0; i < backlogSize; i++) {
      events.add(TallyIncremented.raised(aggregateId: 'agg-${i % 20}', by: 1));
    }

    final stopwatch = Stopwatch()..start();
    final mergedCount = await store.merge(events);
    stopwatch.stop();
    print(
      'merged $mergedCount / $backlogSize backlog events in '
      '${stopwatch.elapsedMilliseconds}ms',
    );

    expect(mergedCount, backlogSize);
    expect(await store.latestSequence(), backlogSize);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
  });

  test('re-merging the same large backlog is a fast, exact no-op', () async {
    final store = newStore();
    addTearDown(store.dispose);

    final events = List.generate(
      5000,
      (i) => TallyIncremented.raised(aggregateId: 'agg-${i % 10}', by: 1),
    );
    await store.merge(events);

    final stopwatch = Stopwatch()..start();
    final mergedAgain = await store.merge(events);
    stopwatch.stop();
    print(
      're-merge of 5000 already-known events took '
      '${stopwatch.elapsedMilliseconds}ms',
    );

    expect(mergedAgain, 0);
    expect(await store.latestSequence(), 5000);
  });

  test('concurrent appends to distinct aggregates all land — no lost or '
      'corrupted writes under simultaneous load', () async {
    final store = newStore();
    addTearDown(store.dispose);

    const concurrentWriters = 50;
    const eventsEach = 20;

    final futures = List.generate(concurrentWriters, (i) async {
      final id = 'concurrent-$i';
      final tally = Tally(id)..start('writer $i');
      for (var e = 0; e < eventsEach; e++) {
        tally.add(1);
      }
      await store.append(id, tally.pendingEvents);
    });

    final stopwatch = Stopwatch()..start();
    await Future.wait(futures);
    stopwatch.stop();
    print(
      '$concurrentWriters concurrent writers x '
      '${eventsEach + 1} events each finished in '
      '${stopwatch.elapsedMilliseconds}ms',
    );

    const expectedTotal = concurrentWriters * (eventsEach + 1);
    expect(await store.latestSequence(), expectedTotal);

    // Every writer's own aggregate must be intact and in order — the
    // real risk under concurrency isn't "missing events" (Drift
    // serializes transactions) so much as one writer's batch getting
    // interleaved with another's inside what should be one atomic
    // append.
    for (var i = 0; i < concurrentWriters; i++) {
      final events = await store.readAggregate('concurrent-$i');
      expect(events, hasLength(eventsEach + 1));
      expect(events.first.eventType, 'tally.started');
      expect(
        events.skip(1).every((e) => e.eventType == 'tally.incremented'),
        isTrue,
      );
    }
  });
}
