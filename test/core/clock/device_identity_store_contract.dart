import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/device_identity_store.dart';

/// Behavioral contract every [DeviceIdentityStore] implementation must
/// satisfy — the same pattern as `event_store_contract.dart` and
/// `sync_cursor_store_contract.dart`, so `InMemoryDeviceIdentityStore`
/// (tests) and `DriftDeviceIdentityStore` (the app) can't quietly drift
/// apart.
///
/// What this contract *doesn't* cover: surviving an actual restart. That
/// needs two store instances sharing the same backing storage, which is
/// meaningless for an in-memory store — it's tested once, for
/// `DriftDeviceIdentityStore` specifically, in
/// `drift_device_identity_store_test.dart` (two stores over the same
/// `AppDatabase`) and again end-to-end in
/// `app_database_migration_test.dart`.
void runDeviceIdentityStoreContractTests(
  DeviceIdentityStore Function() createStore,
) {
  late DeviceIdentityStore store;

  setUp(() => store = createStore());

  test('generates a non-empty node id the first time it is asked', () async {
    expect(await store.nodeId(), isNotEmpty);
  });

  test('returns the same node id on every subsequent call', () async {
    final first = await store.nodeId();
    expect(await store.nodeId(), first);
    expect(await store.nodeId(), first);
  });
}
