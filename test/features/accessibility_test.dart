import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app/app.dart';
import 'package:ledger/app/providers/command_providers.dart';
import 'package:ledger/app/providers/infrastructure_providers.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/features/accounts/application/open_account_handler.dart';

/// Runs Flutter's own accessibility guideline checks against every screen
/// a user actually reaches, not just the widgets a screen reader happens to
/// announce something for. `meetsGuideline` is a real, built-in assertion
/// (no extra package) — it fails the test if a tappable element is smaller
/// than Android's/iOS's minimum touch target, is unlabeled, or fails
/// minimum text contrast; it doesn't just assert a `Semantics` node exists.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(
          AppDatabase.forTesting(NativeDatabase.memory()),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LedgerApp()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAccount(String id, String name, Currency currency) async {
    await container
        .read(openAccountHandlerProvider)
        .handle(
          OpenAccountCommand(accountId: id, name: name, currency: currency),
        );
  }

  /// Every guideline this suite checks, run together — a screen that fails
  /// any one of these fails the test, same as a user who can't read the
  /// text, can't reliably tap the target, or gets no label at all.
  Future<void> checkGuidelines(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  }

  group('accounts list', () {
    testWidgets('empty state meets accessibility guidelines', (tester) async {
      await pump(tester);
      await checkGuidelines(tester);
    });

    testWidgets(
      'with an open and a closed account, meets accessibility guidelines',
      (tester) async {
        await openAccount('acc-1', 'Groceries', Currency.usd);
        await openAccount('acc-2', 'Old wallet', Currency.usd);
        await pump(tester);

        await tester.longPress(find.text('Old wallet'));
        await tester.pumpAndSettle();

        // Both an open row (with the custom "Close account" semantic
        // action) and a closed row (without it) are on screen at once —
        // exactly the case that would catch a `null` action leaking into
        // a real Semantics action key by accident.
        await checkGuidelines(tester);
      },
    );
  });

  group('open account', () {
    testWidgets('meets accessibility guidelines', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await checkGuidelines(tester);
    });
  });

  group('record transaction', () {
    testWidgets(
      'the not-enough-accounts empty state meets accessibility guidelines',
      (tester) async {
        await pump(tester);
        await tester.tap(find.byTooltip('Record transaction'));
        await tester.pumpAndSettle();

        await checkGuidelines(tester);
      },
    );

    testWidgets('the real form meets accessibility guidelines', (tester) async {
      await openAccount('acc-1', 'Groceries', Currency.usd);
      await openAccount('acc-2', 'Wallet', Currency.usd);
      await pump(tester);
      await tester.tap(find.byTooltip('Record transaction'));
      await tester.pumpAndSettle();

      await checkGuidelines(tester);
    });
  });
}
