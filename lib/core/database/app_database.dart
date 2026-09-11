import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ledger/core/database/tables/device_identity_rows.dart';
import 'package:ledger/core/database/tables/event_log_entries.dart';
import 'package:ledger/core/database/tables/sync_cursor_rows.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// The app's local SQLite database: the event log plus, eventually, the
/// materialized projection tables.
///
/// This is infrastructure only — it stores rows and runs the queries
/// `DriftEventStore` asks for. It has no domain knowledge (no
/// `DomainEvent`, no `Hlc` type here); that boundary is what keeps the
/// event-sourcing core testable without a database at all.
@DriftDatabase(tables: [EventLogEntries, SyncCursorRows, DeviceIdentityRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests and tooling: inject any executor directly, typically
  /// `NativeDatabase.memory()`.
  // The generated super constructor names its parameter `e`; `executor` is
  // a clearer name for this public constructor, so this can't use the
  // super-parameter shorthand.
  // ignore: use_super_parameters
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    // Additive only, in order, one `if` per version bump — never edit a
    // table definition that already shipped. A device can be sitting on
    // any past version, and every step from there to today has to still
    // run. test/core/database/app_database_migration_test.dart builds a
    // real v1 database by hand and checks upgrading it this way preserves
    // its data.
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(syncCursorRows);
      }
      if (from < 3) {
        await migrator.createTable(deviceIdentityRows);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

LazyDatabase _openConnection() {
  // Lazy: nothing touches the filesystem or spawns the background isolate
  // until the first query actually runs.
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'ledger.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
