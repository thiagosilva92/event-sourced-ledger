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

  Future<void> goToRecordTransactionPage(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Record transaction'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'with fewer than two open accounts, shows the empty state instead of a form',
    (tester) async {
      await openAccount('acc-1', 'Groceries', Currency.usd);
      await pump(tester);

      await goToRecordTransactionPage(tester);

      expect(find.text('Need two open accounts'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    },
  );

  testWidgets(
    'the "to" dropdown only offers accounts in the same currency as "from"',
    (tester) async {
      await openAccount('usd-acc', 'US Wallet', Currency.usd);
      await openAccount('eur-acc', 'EU Wallet', Currency.eur);
      await pump(tester);

      await goToRecordTransactionPage(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('US Wallet').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();

      // The only other account is in EUR, so it must not be offered as a
      // same-currency destination for a USD source.
      expect(find.text('EU Wallet'), findsNothing);
    },
  );

  testWidgets(
    'submitting with the amount and description left blank shows validation '
    'errors and does not navigate away',
    (tester) async {
      await openAccount('groceries', 'Groceries', Currency.usd);
      await openAccount('wallet', 'Wallet', Currency.usd);
      await pump(tester);

      await goToRecordTransactionPage(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wallet').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Record transaction'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsNWidgets(2)); // amount + description
      expect(find.widgetWithText(AppBar, 'Record transaction'), findsOneWidget);
    },
  );

  testWidgets(
    'the form scrolls instead of overflowing once the keyboard covers half '
    'the screen',
    (tester) async {
      // Reproduces a bug found on real hardware, not by any test: five
      // fields plus a button don't fit in what's left of a phone screen
      // once the on-screen keyboard is up, and a plain `Column` doesn't
      // scroll on its own. Every other test in this file pumps at the
      // default (large) test viewport, which is exactly why none of them
      // caught it — nothing here shrinks the viewport the way a real
      // keyboard does.
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;

      await openAccount('groceries', 'Groceries', Currency.usd);
      await openAccount('wallet', 'Wallet', Currency.usd);
      await pump(tester);

      await goToRecordTransactionPage(tester);

      // Simulate the keyboard covering roughly half the screen, the way it
      // does the moment a text field is focused on a real phone.
      tester.view.viewInsets = const FakeViewPadding(bottom: 400);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recording a transaction updates both balances and returns to the list',
    (tester) async {
      await openAccount('groceries', 'Groceries', Currency.usd);
      await openAccount('wallet', 'Wallet', Currency.usd);
      await pump(tester);

      await goToRecordTransactionPage(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wallet').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), '25.00');
      await tester.enterText(find.byType(TextFormField).at(1), 'Coffee run');

      await tester.tap(find.widgetWithText(FilledButton, 'Record transaction'));
      await tester.pumpAndSettle();

      // Back on the accounts list, both balances reflect the transfer.
      expect(find.widgetWithText(AppBar, 'Accounts'), findsOneWidget);
      expect(
        find.text(Money.parse('-25.00', Currency.usd).toString()),
        findsOneWidget,
      );
      expect(
        find.text(Money.parse('25.00', Currency.usd).toString()),
        findsOneWidget,
      );
    },
  );
}
