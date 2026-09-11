import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

import '../eventsourcing/support/tally_fixture.dart';

/// Measures decoding a large incoming sync batch — `EventCodec
/// .decodeManyFromJson`, the same isolate-threshold pattern
/// `DriftEventStore.readAll` uses for its own large-batch decode, applied
/// here to what `SyncTransport.pull()` receives over the wire.
///
/// Mirrors `test/performance/projection_rebuild_load_test.dart`'s structure
/// on purpose: it's the same shape of problem (JSON decode + registry
/// dispatch dominating a large batch's cost) solved the same way, so the
/// proof that it actually worked should look the same too — a concurrent
/// heartbeat timer, not just a smaller wall-clock number.
void main() {
  setUp(resetTallyFixture);

  test(
    'decodeManyFromJson over 10,000 payloads: end-to-end wall time',
    () async {
      const eventCount = 10000;
      final onWire = List.generate(
        eventCount,
        (i) => TallyIncremented.raised(aggregateId: 'agg-${i % 25}', by: 1),
      ).map((e) => EventCodec(buildTallyRegistry()).encodeToJson(e)).toList();

      final stopwatch = Stopwatch()..start();
      final decoded = await EventCodec.decodeManyFromJson(
        onWire,
        buildTallyRegistry,
      );
      stopwatch.stop();

      print(
        'decodeManyFromJson decoded $eventCount payloads in '
        '${stopwatch.elapsedMilliseconds}ms '
        '(${(stopwatch.elapsedMicroseconds / eventCount).toStringAsFixed(1)}'
        'µs/event)',
      );

      expect(decoded, hasLength(eventCount));
      // Generous ceiling — this is a measurement test, not a tight gate.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    },
  );

  test('decodeManyFromJson above the isolate threshold does not block the '
      "calling isolate's event loop — a concurrent timer keeps ticking "
      'throughout', () async {
    const eventCount = 8000; // well above the isolate-decode threshold
    final onWire = List.generate(
      eventCount,
      (i) => TallyIncremented.raised(aggregateId: 'agg-${i % 25}', by: 1),
    ).map((e) => EventCodec(buildTallyRegistry()).encodeToJson(e)).toList();

    // Same reasoning as the equivalent DriftEventStore.readAll test: if
    // decodeManyFromJson ran its decode synchronously on this isolate,
    // this timer could not fire even once until the call returned —
    // Dart's single event loop can't preempt a synchronous stretch of
    // code. Counting how many times it *does* fire while the call is in
    // flight is a direct runtime measurement that the decode work is
    // happening elsewhere, not a description of what the code is merely
    // supposed to do.
    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 2),
      (_) => ticks++,
    );

    final stopwatch = Stopwatch()..start();
    final decoded = await EventCodec.decodeManyFromJson(
      onWire,
      buildTallyRegistry,
    );
    stopwatch.stop();
    heartbeat.cancel();

    print(
      'decodeManyFromJson of $eventCount payloads: '
      '${stopwatch.elapsedMilliseconds}ms wall time, $ticks heartbeat '
      'ticks fired on the calling isolate while it was in flight (0 would '
      'mean this isolate was blocked solid for the whole call)',
    );

    expect(decoded, hasLength(eventCount));
    // The real bar: 0 would mean this isolate never got a turn for the
    // whole call, i.e. decoding ran synchronously here after all. Timer
    // coarseness on a busy runner means the *rate* isn't a reliable
    // signal, so this only asserts the qualitative claim it can actually
    // back up.
    expect(ticks, greaterThan(0));
  });
}
