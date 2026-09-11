import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger/app/providers/infrastructure_providers.dart';
import 'package:ledger/core/database/app_database.dart';

/// Wraps [child] in a [ProviderScope] for every widget test that pumps
/// `LedgerApp` or a screen that (transitively) reads [appDatabaseProvider].
///
/// The real [appDatabaseProvider] constructs `AppDatabase()`, which needs
/// `path_provider` — a Flutter plugin backed by a platform channel that
/// doesn't exist in the widget-test sandbox. Swapping in an in-memory
/// database here, once, is what `ProviderScope(overrides: [...])` exists
/// for: no `if (test)` branch anywhere in `app/providers/`, the same
/// pattern `DriftEventStore.forTesting`-style constructors use one layer
/// down.
///
/// (Riverpod's `Override` type isn't part of its public export surface, so
/// this returns the wrapped `Widget` rather than a `List<Override>` a test
/// could inline itself — there's no way to name that type from outside the
/// package.)
Widget wrapWithTestProviderScope(Widget child) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(
        AppDatabase.forTesting(NativeDatabase.memory()),
      ),
    ],
    child: child,
  );
}
