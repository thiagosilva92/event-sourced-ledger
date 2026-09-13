import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger/app/app.dart';
import 'package:ledger/app/providers/infrastructure_providers.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/database/drift_device_identity_store.dart';
import 'package:ledger/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Two separate error sources, both routed to Crashlytics, because they
  // genuinely are separate: `FlutterError.onError` catches errors thrown
  // during the framework's own build/layout/paint pipeline (a bad
  // `build()`, for instance); `PlatformDispatcher.instance.onError`
  // catches everything else — an uncaught exception in an `async` gap, a
  // stream listener, a timer callback — that never passes through
  // Flutter's own error zone at all. Missing either one is a real,
  // documented Crashlytics gap (see
  // https://firebase.google.com/docs/crashlytics/get-started?platform=flutter),
  // not a hypothetical one — this project doesn't repeat other teams'
  // "why didn't it catch that crash" postmortem.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    // Deliberately not awaited: `PlatformDispatcher.onError` itself is
    // synchronous (it returns `bool`, not `Future<bool>`), the same
    // shape Firebase's own documented recipe uses.
    unawaited(
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
    );
    return true;
  };

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
