import 'package:flutter/material.dart';
import 'package:ledger/app/router.dart';

/// Root widget of the application.
///
/// Dependency wiring lives in `app/providers/` (injected via
/// `ProviderScope` in `main.dart`); routing lives in `app/router.dart`.
/// This widget just wires theme + router together.
class LedgerApp extends StatelessWidget {
  const LedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Household Ledger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
