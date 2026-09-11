import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ledger/app/router.dart';

/// Root widget of the application.
///
/// Dependency wiring lives in `app/providers/` (injected via
/// `ProviderScope` in `main.dart`); routing lives in `app/router.dart`.
/// This widget wires theme + router together and owns the router's
/// lifetime.
///
/// Deliberately a `StatefulWidget`, not stateless: `_router` is built once
/// in `initState` and kept for as long as this widget lives, rather than
/// being a module-level singleton (see `buildAppRouter`'s doc comment for
/// why that would leak navigation state across app instances / tests) or
/// being rebuilt on every `build()` (which would silently reset navigation
/// history on any ancestor-triggered rebuild).
class LedgerApp extends StatefulWidget {
  const LedgerApp({super.key});

  @override
  State<LedgerApp> createState() => _LedgerAppState();
}

class _LedgerAppState extends State<LedgerApp> {
  late final GoRouter _router = buildAppRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Household Ledger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
