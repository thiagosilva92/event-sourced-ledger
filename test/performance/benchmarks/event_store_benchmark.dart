import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:drift/native.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/database/drift_event_store.dart';

import '../../eventsourcing/support/tally_fixture.dart';

DriftEventStore _newStore() => DriftEventStore(
  AppDatabase.forTesting(NativeDatabase.memory()),
  buildTallyRegistry,
);

class AppendOneEventBenchmark extends AsyncBenchmarkBase {
  AppendOneEventBenchmark() : super('DriftEventStore.append (1 event)');

  late DriftEventStore _store;
  int _n = 0;

  @override
  Future<void> setup() async {
    resetTallyFixture();
    _store = _newStore();
  }

  @override
  Future<void> run() async {
    final id = 'agg-${_n++}';
    await _store.append(id, [TallyStarted.raised(aggregateId: id, label: 'x')]);
  }

  @override
  Future<void> teardown() => _store.dispose();
}

class MergeBatchBenchmark extends AsyncBenchmarkBase {
  MergeBatchBenchmark() : super('DriftEventStore.merge (batch of 50, all new)');

  late DriftEventStore _store;
  int _n = 0;

  @override
  Future<void> setup() async {
    resetTallyFixture();
    _store = _newStore();
  }

  @override
  Future<void> run() async {
    final batch = List.generate(
      50,
      (_) => TallyIncremented.raised(aggregateId: 'agg-${_n++ % 20}', by: 1),
    );
    await _store.merge(batch);
  }

  @override
  Future<void> teardown() => _store.dispose();
}

/// Same fixed dataset read over and over — a read benchmark should measure
/// read cost, not be entangled with how the data got there.
class ReadAllBelowIsolateThresholdBenchmark extends AsyncBenchmarkBase {
  ReadAllBelowIsolateThresholdBenchmark()
    : super('DriftEventStore.readAll (300 events, inline decode)');

  late DriftEventStore _store;

  @override
  Future<void> setup() async {
    resetTallyFixture();
    _store = _newStore();
    await _store.merge(
      List.generate(
        300,
        (i) => TallyIncremented.raised(aggregateId: 'agg-${i % 10}', by: 1),
      ),
    );
  }

  @override
  Future<void> run() => _store.readAll();

  @override
  Future<void> teardown() => _store.dispose();
}

class ReadAllAboveIsolateThresholdBenchmark extends AsyncBenchmarkBase {
  ReadAllAboveIsolateThresholdBenchmark()
    : super('DriftEventStore.readAll (5,000 events, worker-isolate decode)');

  late DriftEventStore _store;

  @override
  Future<void> setup() async {
    resetTallyFixture();
    _store = _newStore();
    await _store.merge(
      List.generate(
        5000,
        (i) => TallyIncremented.raised(aggregateId: 'agg-${i % 25}', by: 1),
      ),
    );
  }

  @override
  Future<void> run() => _store.readAll();

  @override
  Future<void> teardown() => _store.dispose();
}
