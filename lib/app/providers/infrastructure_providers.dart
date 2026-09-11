import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/database/drift_event_store.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/ledger_event_registry.dart';
import 'package:uuid/uuid.dart';

/// The app's single [AppDatabase] connection.
///
/// A real [AppDatabase] needs `path_provider`, which isn't available in a
/// widget-test sandbox — tests override this provider with
/// `AppDatabase.forTesting(NativeDatabase.memory())` instead of touching
/// this default. That's the whole reason this is a provider and not a
/// global singleton: `ProviderScope(overrides: [...])` is what makes the
/// production database path swappable for tests without an `if (test)`
/// branch anywhere in app code.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final eventStoreProvider = Provider<EventStore>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final store = DriftEventStore(db, buildLedgerEventRegistry);
  ref.onDispose(store.dispose);
  return store;
});

/// This device's id for [Hlc] timestamps.
///
/// The default here (a fresh UUID) only ever runs if nothing overrides
/// this provider — which is true for most widget tests, where a new id
/// every rebuild is harmless because nothing in those tests compares HLC
/// timestamps across a restart. The real app never uses this default:
/// `main.dart` resolves the actual node id once, via
/// `DriftDeviceIdentityStore` (persisted in `device_identity_rows`, see
/// `core/clock/device_identity_store.dart` for why it has to survive a
/// restart), and overrides this provider with that value *before*
/// `runApp` — so every event this device ever appends, including the
/// very first one, is stamped with the same node id.
final deviceNodeIdProvider = Provider<String>((ref) => const Uuid().v4());

final hybridLogicalClockProvider = Provider<HybridLogicalClock>((ref) {
  return HybridLogicalClock(
    nodeId: ref.watch(deviceNodeIdProvider),
    physicalTimeMillis: () => DateTime.now().millisecondsSinceEpoch,
  );
});

final eventIdGeneratorProvider = Provider<EventIdGenerator>((ref) {
  const uuid = Uuid();
  return uuid.v7;
});
