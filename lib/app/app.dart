import 'package:flutter/material.dart';

/// Root widget of the application.
///
/// Routing, theming and dependency wiring are attached here as the
/// corresponding layers land. For now it renders a placeholder so the
/// scaffold compiles and can be smoke-tested.
class LedgerApp extends StatelessWidget {
  const LedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Household Ledger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Household Ledger')));
  }
}
