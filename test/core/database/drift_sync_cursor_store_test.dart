import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/database/drift_sync_cursor_store.dart';
import 'package:ledger/sync/sync.dart';

import '../../sync/sync_cursor_store_contract.dart';

void main() {
  runSyncCursorStoreContractTests(
    () => DriftSyncCursorStore(AppDatabase.forTesting(NativeDatabase.memory())),
  );

  test('two remotes tracked by the same database stay independent', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final serverCursors = DriftSyncCursorStore(db, remoteId: 'server');
    final peerCursors = DriftSyncCursorStore(db, remoteId: 'peer-device-a');

    await serverCursors.write(
      const SyncCursors(
        lastPushedLocalSequence: 10,
        lastPulledRemoteSequence: 20,
      ),
    );
    await peerCursors.write(
      const SyncCursors(
        lastPushedLocalSequence: 1,
        lastPulledRemoteSequence: 2,
      ),
    );

    expect(
      await serverCursors.read(),
      const SyncCursors(
        lastPushedLocalSequence: 10,
        lastPulledRemoteSequence: 20,
      ),
    );
    expect(
      await peerCursors.read(),
      const SyncCursors(
        lastPushedLocalSequence: 1,
        lastPulledRemoteSequence: 2,
      ),
    );
  });
}
