import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app/providers/command_providers.dart';
import 'package:ledger/app/providers/infrastructure_providers.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/features/accounts/application/open_account_handler.dart';
import 'package:ledger/features/accounts/presentation/accounts_list_page.dart';
import 'package:ledger/features/transactions/application/record_transaction_handler.dart';
import 'package:ledger/features/transactions/domain/leg.dart';

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
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AccountsListPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state with no accounts', (tester) async {
    await pump(tester);
    expect(find.text('No accounts yet'), findsOneWidget);
  });

  testWidgets('shows an opened account with a zero balance', (tester) async {
    await container
        .read(openAccountHandlerProvider)
        .handle(
          const OpenAccountCommand(
            accountId: 'acc-1',
            name: 'Groceries',
            currency: Currency.usd,
          ),
        );

    await pump(tester);

    expect(find.text('Groceries'), findsOneWidget);
    expect(
      find.text(const Money.zero(Currency.usd).toString()),
      findsOneWidget,
    );
  });

  testWidgets("reflects a recorded transaction's balance live", (tester) async {
    await container
        .read(openAccountHandlerProvider)
        .handle(
          const OpenAccountCommand(
            accountId: 'groceries',
            name: 'Groceries',
            currency: Currency.usd,
          ),
        );
    await container
        .read(openAccountHandlerProvider)
        .handle(
          const OpenAccountCommand(
            accountId: 'wallet',
            name: 'Wallet',
            currency: Currency.usd,
          ),
        );
    await container
        .read(recordTransactionHandlerProvider)
        .handle(
          RecordTransactionCommand(
            transactionId: 'tx-1',
            description: 'shop',
            occurredAt: DateTime.utc(2026, 9, 10),
            legs: [
              Leg(
                accountId: 'groceries',
                amount: Money.parse('50.00', Currency.usd),
              ),
              Leg(
                accountId: 'wallet',
                amount: Money.parse('-50.00', Currency.usd),
              ),
            ],
          ),
        );

    await pump(tester);

    expect(
      find.text(Money.parse('50.00', Currency.usd).toString()),
      findsOneWidget,
    );
    expect(
      find.text(Money.parse('-50.00', Currency.usd).toString()),
      findsOneWidget,
    );
  });

  testWidgets('long-pressing an open account closes it', (tester) async {
    await container
        .read(openAccountHandlerProvider)
        .handle(
          const OpenAccountCommand(
            accountId: 'acc-1',
            name: 'Groceries',
            currency: Currency.usd,
          ),
        );
    await pump(tester);

    await tester.longPress(find.text('Groceries'));
    await tester.pumpAndSettle();

    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Closed Groceries.'), findsOneWidget); // the SnackBar
  });
}
