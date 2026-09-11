import 'dart:async';

import 'package:drift/drift.dart';

/// Global test configuration, auto-loaded by the test runner for every test
/// under this directory.
///
/// The contract test suite opens a fresh `AppDatabase` per test by design
/// (each test gets an isolated in-memory database). Drift's
/// multiple-database heuristic is meant to catch an app accidentally
/// constructing more than one long-lived database over the same connection
/// in production — a real bug there — but it's a false positive for this
/// intentional test pattern, so it's silenced only here, not in app code.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
