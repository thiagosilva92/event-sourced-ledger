import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ledger/core/database/tables/event_log_entries.dart';
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
@DriftDatabase(tables: [EventLogEntries])
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    // There is only one shipped schema so far. When schemaVersion becomes
    // 2, add an `onUpgrade` step here (`if (from < 2) ...`) rather than
    // editing table definitions that already shipped — migrations must
    // stay reproducible for every version a real device might be on.
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
