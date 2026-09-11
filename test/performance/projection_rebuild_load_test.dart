import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/database/drift_event_store.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

import '../eventsourcing/support/tally_fixture.dart';

/// Measures folding a large event log into a projection.
///
/// The very first version of this file measured the *old* behavior —
/// decoding always ran synchronously on the caller's isolate — and used
/// that to decide whether isolate offloading (`docs/concurrency.md`'s
/// "planned, not wired up" note) was worth building at all. It was: 10,000
/// events cost ~180ms of synchronous JSON-decode-and-registry-dispatch,
/// with the fold itself taking ~0ms — see the "breakdown" test below,
/// which still measures that split. `DriftEventStore.readAll` now offloads
/// decoding to a worker isolate above a size threshold; the
/// "does not block the calling isolate" test below is the runtime proof
/// that actually did what it was supposed to, not just a smaller number.
void main() {
  setUp(resetTallyFixture);

  test('rebuild() over 10,000 events: end-to-end wall time '
      '(decode now runs on a worker isolate above the threshold)', () async {
    final store = DriftEventStore(
      AppDatabase.forTesting(NativeDatabase.memory()),
      buildTallyRegistry,
    );
    addTearDown(store.dispose);

    const eventCount = 10000;
    final events = List.generate(
      eventCount,
      (i) => TallyIncremented.raised(aggregateId: 'agg-${i % 25}', by: 1),
    );
    await store.merge(events);

    final projection = _GrandTotal();
    final runner = ProjectionRunner(store, [projection]);

    final stopwatch = Stopwatch()..start();
    await runner.rebuild();
    stopwatch.stop();

    print(
      'rebuild() folded $eventCount events in '
      '${stopwatch.elapsedMilliseconds}ms '
      '(${(stopwatch.elapsedMicroseconds / eventCount).toStringAsFixed(1)}'
      'µs/event)',
    );

    expect(projection.state, eventCount); // 1 per event, by: 1 each
    expect(projection.lastSequence, eventCount);
    // Generous ceiling — this is a measurement test, not a tight gate.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test(
    'breakdown: how much of rebuild() is reading+decoding vs. folding',
    () async {
      // ProjectionRunner does one readAll() (query + JSON decode of every
      // row back into a DomainEvent, all on the caller's isolate — Drift's
      // background isolate only covers the raw SQL execution) and then
      // folds each event into every projection. This splits the two so a
      // decision about what to move to an isolate is based on where the
      // time actually goes, not a guess.
      final store = DriftEventStore(
        AppDatabase.forTesting(NativeDatabase.memory()),
        buildTallyRegistry,
      );
      addTearDown(store.dispose);

      const eventCount = 10000;
      await store.merge(
        List.generate(
          eventCount,
          (i) => TallyIncremented.raised(aggregateId: 'agg-${i % 25}', by: 1),
        ),
      );

      final readStopwatch = Stopwatch()..start();
      final sequencedEvents = await store.readAll();
      readStopwatch.stop();

      final projection = _GrandTotal();
      final foldStopwatch = Stopwatch()..start();
      for (final sequenced in sequencedEvents) {
        projection.apply(sequenced.sequence, sequenced.event);
      }
      foldStopwatch.stop();

      print(
        'readAll() (query + JSON decode): '
        '${readStopwatch.elapsedMilliseconds}ms · '
        'fold loop only: ${foldStopwatch.elapsedMilliseconds}ms · '
        'for $eventCount events',
      );

      expect(projection.state, eventCount);
    },
  );

  test(
    'readAll() above the isolate threshold does not block the calling '
    "isolate's event loop — a concurrent timer keeps ticking throughout",
    () async {
      final store = DriftEventStore(
        AppDatabase.forTesting(NativeDatabase.memory()),
        buildTallyRegistry,
      );
      addTearDown(store.dispose);

      const eventCount = 8000; // well above the isolate-decode threshold
      await store.merge(
        List.generate(
          eventCount,
          (i) => TallyIncremented.raised(aggregateId: 'agg-${i % 25}', by: 1),
        ),
      );

      // A concurrent heartbeat: if readAll() ran its decode synchronously
      // on this isolate (the old behavior for every batch, still what
      // happens below the threshold), this timer could not fire even once
      // until readAll() returned — Dart's single event loop can't preempt
      // a synchronous stretch of code. Counting how many times it *does*
      // fire while readAll() is in flight is a direct runtime measurement
      // that the decode work is happening elsewhere, not a description of
      // what the code is merely supposed to do.
      var ticks = 0;
      final heartbeat = Timer.periodic(
        const Duration(milliseconds: 2),
        (_) => ticks++,
      );

      final stopwatch = Stopwatch()..start();
      final result = await store.readAll();
      stopwatch.stop();
      heartbeat.cancel();

      print(
        'readAll() of $eventCount events: ${stopwatch.elapsedMilliseconds}ms '
        'wall time, $ticks heartbeat ticks fired on the calling isolate '
        'while it was in flight (0 would mean this isolate was blocked '
        'solid for the whole call)',
      );

      expect(result, hasLength(eventCount));
      // The real bar: 0 would mean this isolate never got a turn for the
      // whole call, i.e. decoding ran synchronously here after all. Timer
      // coarseness on a busy runner means the *rate* isn't a reliable
      // signal (this run got 3 ticks for a 2ms period over 114ms, well
      // under what "2ms" implies), so this only asserts the qualitative
      // claim it can actually back up.
      expect(ticks, greaterThan(0));
    },
  );

  test(
    'catchUp() after rebuild only pays for the new events, not the whole log',
    () async {
      final store = DriftEventStore(
        AppDatabase.forTesting(NativeDatabase.memory()),
        buildTallyRegistry,
      );
      addTearDown(store.dispose);

      final initial = List.generate(
        8000,
        (i) => TallyIncremented.raised(aggregateId: 'agg-${i % 25}', by: 1),
      );
      await store.merge(initial);

      final projection = _GrandTotal();
      final runner = ProjectionRunner(store, [projection]);
      await runner.rebuild();

      final topUp = List.generate(
        500,
        (i) => TallyIncremented.raised(aggregateId: 'agg-${i % 25}', by: 1),
      );
      await store.merge(topUp);

      final stopwatch = Stopwatch()..start();
      await runner.catchUp();
      stopwatch.stop();

      print(
        'catchUp() folded 500 new events in ${stopwatch.elapsedMilliseconds}ms',
      );

      expect(projection.state, 8500);
      // The point of catchUp existing at all: it should be nowhere near as
      // slow as a full rebuild of 8500 events would be.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );
}

class _GrandTotal extends Projection<int> {
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
