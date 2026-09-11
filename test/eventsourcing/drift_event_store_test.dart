import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/eventsourcing/drift_event_store.dart';
import 'package:path/path.dart' as p;

import 'event_store_contract.dart';
import 'support/tally_fixture.dart';

DriftEventStore _newStore() {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  return DriftEventStore(db, buildTallyRegistry);
}

void main() {
  runEventStoreContractTests(
    _newStore,
    disposeStore: (store) => (store as DriftEventStore).dispose(),
  );

  group('DriftEventStore-specific', () {
    test(
      'events are reconstructed via the registry, not kept by reference',
      () async {
        final store = _newStore();
        addTearDown(store.dispose);

        final tally = Tally('t1')..start('groceries');
        final original = tally.pendingEvents.single as TallyStarted;
        await store.append('t1', [original]);

        final results = await store.readAggregate('t1');
        final rebuilt = results.single as TallyStarted;

        expect(identical(rebuilt, original), isFalse);
        expect(rebuilt, original); // DomainEvent.== compares by eventId
        expect(rebuilt.label, original.label);
        expect(rebuilt.timestamp, original.timestamp);
      },
    );

    test('data survives closing and reopening the database file', () async {
      final dir = await Directory.systemTemp.createTemp('ledger_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'test.sqlite'));

      final storeA = DriftEventStore(
        AppDatabase.forTesting(NativeDatabase(file)),
        buildTallyRegistry,
      );
      final tally = Tally('t1')
        ..start('x')
        ..add(5);
      await storeA.append('t1', tally.pendingEvents);
      await storeA.dispose(); // flush + close, as an app shutdown would

      final storeB = DriftEventStore(
        AppDatabase.forTesting(NativeDatabase(file)),
        buildTallyRegistry,
      );
      addTearDown(storeB.dispose);

      final events = await storeB.readAggregate('t1');
      expect(events.map((e) => e.eventType), [
        'tally.started',
        'tally.incremented',
      ]);
    });
  });
}
