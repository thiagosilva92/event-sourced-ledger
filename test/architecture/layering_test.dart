import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces the layering the README promises, so a future change can't
/// quietly violate it — the same way `event_store_contract.dart` keeps two
/// `EventStore` implementations honest, this keeps the dependency graph
/// honest.
///
/// This is a plain regex scan over `import '...'` lines, not an AST
/// analysis. This codebase's import style (one import per line, no
/// `deferred as`, no conditional imports) is consistent enough for that to
/// be reliable, and it needs no dependency beyond what test tooling already
/// pulls in — no `package:analyzer`, no `custom_lint` plugin, nothing that
/// could itself drift out of sync with the Dart/Flutter version this repo
/// is on.
///
/// A rule failing here doesn't mean the code is broken — everything still
/// compiles and every other test still passes — it means an architectural
/// promise this repo makes (in the README, in doc comments) stopped being
/// true, silently. That's exactly the failure mode a human code review is
/// worst at catching and a test like this is best at.
void main() {
  final importsByFile = _collectImports(Directory('lib'));

  group('pure domain layers stay pure Dart', () {
    // No Flutter, no Drift/SQLite, no platform plugins. These directories
    // must be testable with a bare `dart test` — not because we run it that
    // way today (everything goes through `flutter test`), but because
    // "doesn't need a device, a database engine, or a widget tree to make
    // sense" is exactly the property that keeps domain logic cheap to test
    // and easy to reason about. The day one of these imports `flutter/`,
    // that property is gone, possibly without anyone deciding it should be.
    const pureZones = [
      'core/money/',
      'core/clock/',
      'core/result/',
      'eventsourcing/',
    ];
    const forbiddenPrefixes = [
      'package:flutter/',
      'package:drift/',
      'package:path_provider/',
      'package:connectivity_plus/',
      'package:go_router/',
      'dart:ui',
    ];

    for (final zone in pureZones) {
      test(zone, () {
        final offenders = _violationsIn(
          importsByFile,
          pathPrefix: zone,
          isForbidden: (import) => forbiddenPrefixes.any(import.startsWith),
        );
        expect(
          offenders,
          isEmpty,
          reason:
              '"$zone" must stay pure Dart — no Flutter, Drift, or platform '
              'plugins:\n${offenders.join('\n')}',
        );
      });
    }
  });

  group('the foundation never depends on what is built on top of it', () {
    // core/ and eventsourcing/ are the base of the dependency graph per the
    // README's architecture diagram. sync/, app/ and (eventually) features/
    // depend on them — never the other way around. A foundation file
    // importing from `app/` or `features/` would mean the "foundation"
    // label is a lie, and everything built on it is secretly circular.
    const foundationZones = ['core/', 'eventsourcing/'];
    const upperZones = ['app/', 'features/', 'sync/'];

    for (final zone in foundationZones) {
      test(zone, () {
        final offenders = _violationsIn(
          importsByFile,
          pathPrefix: zone,
          isForbidden: (import) => upperZones.any(
            (upper) => import.startsWith('package:ledger/$upper'),
          ),
        );
        expect(
          offenders,
          isEmpty,
          reason:
              '"$zone" is foundation — it must not depend on '
              '${upperZones.join(', ')}:\n${offenders.join('\n')}',
        );
      });
    }

    test('sync/', () {
      // sync/ sits between the foundation and the app: it's allowed to
      // depend on core/ and eventsourcing/, but app/ and features/ depend
      // on *it*, not the reverse.
      final offenders = _violationsIn(
        importsByFile,
        pathPrefix: 'sync/',
        isForbidden: (import) =>
            import.startsWith('package:ledger/app/') ||
            import.startsWith('package:ledger/features/'),
      );
      expect(
        offenders,
        isEmpty,
        reason:
            '"sync/" must not depend on app/ or features/:\n'
            '${offenders.join('\n')}',
      );
    });
  });

  test('the Drift-backed EventStore lives in core/database/, not '
      'eventsourcing/ — it is the implementation, not the interface', () {
    // A rule specific enough to catch the exact mistake that prompted
    // this file: drift_event_store.dart briefly lived under eventsourcing/
    // and quietly broke the "pure domain layer" rule above until it was
    // moved. Pinning the file's location directly makes that regression
    // impossible to reintroduce by accident.
    final misplaced = importsByFile.keys.where(
      (path) =>
          path.startsWith('eventsourcing/') &&
          path.contains('drift_event_store'),
    );
    expect(misplaced, isEmpty, reason: misplaced.join('\n'));
  });
}

/// Maps each `.dart` file under [root] (path relative to `lib/`) to the
/// list of packages/libraries it imports.
Map<String, List<String>> _collectImports(Directory root) {
  final importPattern = RegExp(r"""^\s*import\s+['"]([^'"]+)['"]""");
  final result = <String, List<String>>{};

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relativePath = entity.path.replaceAll(r'\', '/').split('lib/').last;
    result[relativePath] = [
      for (final line in entity.readAsLinesSync())
        if (importPattern.firstMatch(line) case final match?) match.group(1)!,
    ];
  }
  return result;
}

/// Every `pathPrefix imports import` pair where [isForbidden] holds, one
/// human-readable line per violation.
List<String> _violationsIn(
  Map<String, List<String>> importsByFile, {
  required String pathPrefix,
  required bool Function(String import) isForbidden,
}) {
  final offenders = <String>[];
  importsByFile.forEach((path, imports) {
    if (!path.startsWith(pathPrefix)) return;
    for (final import in imports) {
      if (isForbidden(import)) {
        offenders.add('  lib/$path imports $import');
      }
    }
  });
  return offenders;
}
