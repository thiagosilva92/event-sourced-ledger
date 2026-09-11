import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/database/drift_device_identity_store.dart';
import 'package:ledger/core/database/drift_sync_cursor_store.dart';
import 'package:ledger/sync/sync.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Proves `AppDatabase`'s `onUpgrade` step, not just its `onCreate` one — a
/// path every other test in this repo skips, since they all open a brand
/// new in-memory database at the current schema version.
///
/// A schema-v1 database (`event_log_entries` only — before
/// `sync_cursor_rows` or `device_identity_rows` existed) is built by hand
/// with the raw `sqlite3` package, exactly as a device that installed the
/// app before either change would actually have on disk. Opening it with
/// today's `AppDatabase` has to run *both* additive steps (v1 -> 2 -> 3)
/// and keep the existing event log intact — any one of those failing would
/// mean a real user loses data, or a stale device silently skips a step,
/// on update.
void main() {
  test('upgrading a real v1 database adds sync_cursor_rows and '
      'device_identity_rows without losing event_log_entries data', () async {
    final dir = await Directory.systemTemp.createTemp('ledger_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'v1.sqlite'));

    _createV1Database(file);

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    // Triggers the migration (schemaVersion 1 -> 3) on first access.
    final survivingEvents = await db.select(db.eventLogEntries).get();
    expect(survivingEvents, hasLength(1));
    expect(survivingEvents.single.eventId, 'pre-migration-event');
    expect(survivingEvents.single.aggregateId, 'agg-1');

    // Both new tables work, not just exist.
    final cursorStore = DriftSyncCursorStore(db);
    expect(await cursorStore.read(), SyncCursors.zero);
    await cursorStore.write(
      const SyncCursors(
        lastPushedLocalSequence: 3,
        lastPulledRemoteSequence: 5,
      ),
    );
    expect(
      await cursorStore.read(),
      const SyncCursors(
        lastPushedLocalSequence: 3,
        lastPulledRemoteSequence: 5,
      ),
    );

    final identityStore = DriftDeviceIdentityStore(db);
    final nodeId = await identityStore.nodeId();
    expect(nodeId, isNotEmpty);
    // Surviving the upgrade with no prior row is the whole point here —
    // a device updating from v1 never had a node id before, so this is
    // exactly the "generate one for the first time" path, just reached
    // through onUpgrade instead of onCreate.
    expect(await identityStore.nodeId(), nodeId);
  });
}

/// Builds a schema-v1 database file directly with `sqlite3`, bypassing
/// `AppDatabase` entirely — using `AppDatabase` itself to create the "old"
/// schema would just be testing today's `onCreate` against itself, not a
/// real pre-migration file.
void _createV1Database(File file) {
  final raw = sqlite3.sqlite3.open(file.path);
  try {
    raw
      ..execute('''
        CREATE TABLE event_log_entries (
          sequence INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          event_id TEXT NOT NULL UNIQUE,
          aggregate_id TEXT NOT NULL,
          event_type TEXT NOT NULL,
          hlc_wall_millis INTEGER NOT NULL,
          hlc_counter INTEGER NOT NULL,
          hlc_node_id TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          recorded_at INTEGER NOT NULL
        );
      ''')
      ..execute(
        'CREATE INDEX event_log_aggregate_id ON event_log_entries (aggregate_id)',
      )
      ..execute(
        'CREATE INDEX event_log_hlc ON event_log_entries '
        '(hlc_wall_millis, hlc_counter, hlc_node_id)',
      )
      ..execute('''
        INSERT INTO event_log_entries
          (event_id, aggregate_id, event_type, hlc_wall_millis, hlc_counter,
           hlc_node_id, payload_json, recorded_at)
        VALUES
          ('pre-migration-event', 'agg-1', 'tally.started', 1000, 0, 'n',
           '{"label":"x"}', 0);
        ''')
      // Drift keeps the schema version in SQLite's own user_version pragma.
      ..execute('PRAGMA user_version = 1;');
  } finally {
    raw.close();
  }
}
