import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:ledger/core/clock/hlc.dart';

/// A `maxCounter` far above the default: `run()` is called back-to-back for
/// up to ~2 seconds (`benchmark_harness`'s exercise window), fast enough on
/// modern hardware to plausibly issue more than the default 0xFFFF-per-
/// millisecond ceiling. That ceiling is a real safety guard for production
/// use (see `HybridLogicalClock`'s doc comment) — it isn't what this
/// benchmark is measuring, so it's relaxed here rather than tripped.
const int _benchmarkMaxCounter = 1 << 30;

class HlcNowBenchmark extends BenchmarkBase {
  HlcNowBenchmark() : super('HybridLogicalClock.now()');

  late HybridLogicalClock _clock;

  @override
  void setup() {
    _clock = HybridLogicalClock(
      nodeId: 'benchmark',
      physicalTimeMillis: () => DateTime.now().millisecondsSinceEpoch,
      maxCounter: _benchmarkMaxCounter,
    );
  }

  @override
  void run() {
    _clock.now();
  }
}

class HlcReceiveBenchmark extends BenchmarkBase {
  HlcReceiveBenchmark() : super('HybridLogicalClock.receive()');

  late HybridLogicalClock _clock;
  int _peerCounter = 0;

  @override
  void setup() {
    _clock = HybridLogicalClock(
      nodeId: 'benchmark',
      physicalTimeMillis: () => DateTime.now().millisecondsSinceEpoch,
      maxCounter: _benchmarkMaxCounter,
    );
  }

  @override
  void run() {
    _clock.receive(
      Hlc(
        wallMillis: DateTime.now().millisecondsSinceEpoch,
        counter: _peerCounter++,
        nodeId: 'peer-device',
      ),
    );
  }
}
