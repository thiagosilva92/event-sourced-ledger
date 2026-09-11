import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/sync/sync_cursor.dart';

/// [SyncCursorStore] backed by the `sync_cursor_rows` table — cursors
/// survive an app restart, unlike `InMemorySyncCursorStore`.
///
/// Lives under `core/database/`, alongside `DriftEventStore`, for the same
/// reason: it's the Drift-specific implementation of a `sync/` interface,
/// not part of the pure-Dart domain layer. `test/architecture/layering_test.dart`
/// checks that `sync/` stays free of Drift the same way it checks
/// `eventsourcing/`.
class DriftSyncCursorStore implements SyncCursorStore {
  DriftSyncCursorStore(this._db, {this.remoteId = 'default'});

  final AppDatabase _db;

  /// Identifies which remote these cursors track. There's only ever one
  /// remote today, so the default is enough; a future multi-remote setup
  /// would construct one store per remote with a distinct id.
  final String remoteId;

  @override
  Future<SyncCursors> read() async {
    final row = await (_db.select(
      _db.syncCursorRows,
    )..where((row) => row.id.equals(remoteId))).getSingleOrNull();
    if (row == null) return SyncCursors.zero;
    return SyncCursors(
      lastPushedLocalSequence: row.lastPushedLocalSequence,
      lastPulledRemoteSequence: row.lastPulledRemoteSequence,
    );
  }

  @override
  Future<void> write(SyncCursors cursors) {
    return _db
        .into(_db.syncCursorRows)
        .insertOnConflictUpdate(
          SyncCursorRowsCompanion.insert(
            id: remoteId,
            lastPushedLocalSequence: cursors.lastPushedLocalSequence,
            lastPulledRemoteSequence: cursors.lastPulledRemoteSequence,
          ),
        );
  }
}
