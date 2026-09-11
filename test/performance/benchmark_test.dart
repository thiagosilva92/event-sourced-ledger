@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:flutter_test/flutter_test.dart';

import 'benchmarks/event_store_benchmark.dart';
import 'benchmarks/hlc_benchmark.dart';
import 'benchmarks/money_benchmark.dart';

/// Runs every formal benchmark once, reports the actual numbers, and warns
/// on regression against a committed baseline (`benchmark_baseline.json`) —
/// catching "this got dramatically slower" in a way
/// `test/performance/*_load_test.dart` can't, since those only assert one
/// generous ceiling per operation.
///
/// This is deliberately **not a hard CI gate**. Absolute timing depends on
/// the machine running it — a laptop under load, a shared CI runner, a
/// different CPU generation — so a tight threshold would fail on noise
/// rather than on real regressions. The comparison below only ever prints;
/// it never fails this test. See the "Testing strategy" section of the
/// README for what that trade-off does and doesn't guarantee.
///
/// To refresh the baseline after a deliberate, understood performance
/// change:
/// ```bash
/// UPDATE_BENCHMARK_BASELINE=1 flutter test test/performance/benchmark_test.dart
/// ```
void main() {
  test(
    'formal benchmarks: report current numbers, warn on regression',
    () async {
      final results = <String, double>{};

      for (final benchmark in <BenchmarkBase>[
        MoneyAllocateBenchmark(),
        MoneyAllocateByWeightsBenchmark(),
        HlcNowBenchmark(),
        HlcReceiveBenchmark(),
      ]) {
        results[benchmark.name] = benchmark.measure();
      }

      for (final benchmark in <AsyncBenchmarkBase>[
        AppendOneEventBenchmark(),
        MergeBatchBenchmark(),
        ReadAllBelowIsolateThresholdBenchmark(),
        ReadAllAboveIsolateThresholdBenchmark(),
      ]) {
        results[benchmark.name] = await benchmark.measure();
      }

      final baselineFile = File('test/performance/benchmark_baseline.json');

      if (Platform.environment['UPDATE_BENCHMARK_BASELINE'] == '1') {
        _writeBaseline(baselineFile, results);
        return;
      }

      _reportAgainstBaseline(baselineFile, results);

      // The only real assertion: every benchmark produced a positive number.
      // A zero or negative "microseconds per run" would mean measure() itself
      // is broken, not that the code under test got infinitely fast.
      for (final entry in results.entries) {
        expect(
          entry.value,
          greaterThan(0),
          reason: '${entry.key} reported a non-positive duration',
        );
      }
    },
  );
}

void _writeBaseline(File file, Map<String, double> results) {
  final sorted = Map.fromEntries(
    results.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
  );
  print('Wrote baseline for ${results.length} benchmarks to ${file.path}');
}

void _reportAgainstBaseline(File file, Map<String, double> results) {
  final baseline = file.existsSync()
      ? (jsonDecode(file.readAsStringSync()) as Map<String, Object?>).map(
          (key, value) => MapEntry(key, (value! as num).toDouble()),
        )
      : <String, double>{};

  // A regression this large is worth a human's attention even accounting
  // for machine noise; anything smaller is too easily explained by a busy
  // runner to call out specifically.
  const warnAboveRatio = 1.5;

  print('\n--- Benchmark report (µs/op, lower is better) ---');
  final names = results.keys.toList()..sort();
  for (final name in names) {
    final current = results[name]!;
    final previous = baseline[name];
    final line = StringBuffer(
      '${name.padRight(52)} ${current.toStringAsFixed(1).padLeft(10)}',
    );
    if (previous != null) {
      final ratio = current / previous;
      line.write(
        '  (baseline ${previous.toStringAsFixed(1)}, '
        '${(ratio * 100 - 100).toStringAsFixed(0)}%)',
      );
      if (ratio >= warnAboveRatio) {
        line.write(
          '  ⚠ WARN: >${((warnAboveRatio - 1) * 100).toStringAsFixed(0)}% slower than baseline',
        );
      }
    } else {
      line.write('  (no baseline yet)');
    }
    print(line);
  }
  print('---------------------------------------------------\n');
}
