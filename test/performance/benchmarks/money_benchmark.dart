import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:ledger/core/money/money.dart';

/// Largest-remainder allocation — the one piece of `Money` with an actual
/// loop in it; `+`/`-`/`compareTo` are single-instruction-cheap and not
/// worth a formal benchmark.
class MoneyAllocateBenchmark extends BenchmarkBase {
  MoneyAllocateBenchmark() : super('Money.allocate(7 parts)');

  static final Money _amount = Money.parse('123456.78', Currency.usd);

  @override
  void run() {
    _amount.allocate(7);
  }
}

class MoneyAllocateByWeightsBenchmark extends BenchmarkBase {
  MoneyAllocateByWeightsBenchmark()
    : super('Money.allocateByWeights([3, 1, 1, 5])');

  static final Money _amount = Money.parse('9999.99', Currency.usd);
  static const _weights = [3, 1, 1, 5];

  @override
  void run() {
    _amount.allocateByWeights(_weights);
  }
}
