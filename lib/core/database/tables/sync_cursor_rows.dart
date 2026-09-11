import 'package:drift/drift.dart';

/// Where this device's sync with one remote has gotten to, in each
/// direction. Mirrors `sync/sync_cursor.dart`'s `SyncCursors` value object —
/// this is its persisted form.
///
/// Exactly one row per remote. Today there's only ever one remote (the
/// server), keyed by the constant id `DriftSyncCursorStore` defaults to;
/// the schema doesn't assume that stays true.
@DataClassName('SyncCursorRow')
class SyncCursorRows extends Table {
  /// Identifies the remote these cursors are for.
  TextColumn get id => text()();

  /// Local events up to and including this sequence have been pushed.
  IntColumn get lastPushedLocalSequence => integer()();

  /// Remote events up to and including this (remote) sequence have been
  /// pulled and merged locally.
  IntColumn get lastPulledRemoteSequence => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
