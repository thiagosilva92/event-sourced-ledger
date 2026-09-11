import 'package:drift/drift.dart';

/// This device's own persisted node id — the same `nodeId` value
/// `HybridLogicalClock` stamps on every event it timestamps. Exactly one
/// row, ever: a device's identity doesn't change across restarts, or `Hlc`
/// ordering has nothing stable to key on. See
/// `core/clock/device_identity_store.dart` for why this needs to persist
/// at all.
@DataClassName('DeviceIdentityRow')
class DeviceIdentityRows extends Table {
  /// Always the constant `DriftDeviceIdentityStore.id` defaults to — a
  /// deliberate singleton row, not a real identifier space. Kept as a
  /// column (not implicit) for the same reason `SyncCursorRows.id` is:
  /// nothing rules out a future multi-identity scenario needing more than
  /// one row.
  TextColumn get id => text()();

  TextColumn get nodeId => text()();

  @override
  Set<Column> get primaryKey => {id};
}
