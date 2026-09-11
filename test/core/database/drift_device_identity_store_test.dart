import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/database/drift_device_identity_store.dart';

import '../clock/device_identity_store_contract.dart';

void main() {
  runDeviceIdentityStoreContractTests(
    () => DriftDeviceIdentityStore(
      AppDatabase.forTesting(NativeDatabase.memory()),
    ),
  );

  test('a fresh store instance over the same database sees the same node id — '
      'this is the whole point: it has to survive a real app restart, not '
      'just outlive one Dart object', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final first = await DriftDeviceIdentityStore(db).nodeId();
    final second = await DriftDeviceIdentityStore(db).nodeId();

    expect(second, first);
  });

  test('two ids tracked by the same database stay independent', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final deviceA = DriftDeviceIdentityStore(db, id: 'device-a');
    final deviceB = DriftDeviceIdentityStore(db, id: 'device-b');

    final nodeIdA = await deviceA.nodeId();
    final nodeIdB = await deviceB.nodeId();

    expect(nodeIdA, isNot(nodeIdB));
    expect(await deviceA.nodeId(), nodeIdA);
    expect(await deviceB.nodeId(), nodeIdB);
  });
}
