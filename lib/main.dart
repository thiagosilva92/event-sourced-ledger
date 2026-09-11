import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger/app/app.dart';
import 'package:ledger/app/providers/infrastructure_providers.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/database/drift_device_identity_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolved once, here, before `runApp` — not lazily inside a provider.
  // Every event this device ever appends needs the *same* node id,
  // including the very first one, so it can't wait for some widget to
  // first watch `deviceNodeIdProvider`. Building the `AppDatabase` here
  // and handing this exact instance to `appDatabaseProvider` (rather than
  // letting that provider construct its own) keeps this the single
  // database connection the app ever opens — `DriftDeviceIdentityStore`
  // and every provider that watches `appDatabaseProvider` end up sharing
  // one connection, not two racing to create the file.
  final db = AppDatabase();
  final nodeId = await DriftDeviceIdentityStore(db).nodeId();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceNodeIdProvider.overrideWithValue(nodeId),
      ],
      child: const LedgerApp(),
    ),
  );
}
