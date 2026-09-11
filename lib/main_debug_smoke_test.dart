// Alternate entry point — run with:
//   flutter run -t lib/main_debug_smoke_test.dart -d <device>
//
// Exercises the *production* AppDatabase() path (real file via
// path_provider, real native SQLite, real background isolate) on whatever
// device it's run on. Not part of the normal `flutter run` / `main.dart`
// entry point, and not touched by `flutter test` — see
// lib/app/debug/db_smoke_test_screen.dart for why it exists and when to
// delete it.
import 'package:flutter/material.dart';
import 'package:ledger/app/debug/db_smoke_test_screen.dart';

void main() {
  runApp(const MaterialApp(title: 'DB smoke test', home: DbSmokeTestScreen()));
}
