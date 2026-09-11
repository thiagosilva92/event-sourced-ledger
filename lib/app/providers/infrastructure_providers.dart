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
/// Simplification: generated fresh per app launch rather than persisted.
/// Harmless today — `sync/` isn't wired into the UI yet, so nothing
/// compares this device's HLC against another device's across a restart.
/// Before sync is wired in, this needs to persist (e.g. a settings table)
/// so causal ordering is meaningful device-to-device across sessions, not
/// just within one.
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
