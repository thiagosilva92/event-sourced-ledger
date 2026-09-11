import 'package:ledger/core/clock/device_identity_store.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

/// [DeviceIdentityStore] backed by the `device_identity_rows` table — the
/// node id survives an app restart, unlike `InMemoryDeviceIdentityStore`.
///
/// Lives under `core/database/`, alongside `DriftEventStore` and
/// `DriftSyncCursorStore`, for the same reason: it's the Drift-specific
/// implementation of a pure-Dart interface (`core/clock/`), not part of
/// the pure domain layer itself — `test/architecture/layering_test.dart`
/// pins all three here.
///
/// Not safe to call [nodeId] concurrently before the row exists: two
/// in-flight first calls would both read no row, both generate a
/// *different* id, and the second write would silently win — the caller
/// that got the first id would be wrong. Harmless in practice because
/// there's exactly one call site (`main.dart`, once, before anything else
/// touches the database), documented here so that stays true on purpose,
/// not by accident.
class DriftDeviceIdentityStore implements DeviceIdentityStore {
  DriftDeviceIdentityStore(this._db, {this.id = 'default'});

  final AppDatabase _db;

  /// Always `'default'` today — a real device only ever has one identity.
  final String id;

  @override
  Future<String> nodeId() async {
    final row = await (_db.select(
      _db.deviceIdentityRows,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row != null) return row.nodeId;

    final generated = const Uuid().v4();
    await _db
        .into(_db.deviceIdentityRows)
        .insertOnConflictUpdate(
          DeviceIdentityRowsCompanion.insert(id: id, nodeId: generated),
        );
    return generated;
  }
}
