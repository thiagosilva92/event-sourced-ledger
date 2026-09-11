import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/application/close_account_handler.dart';
import 'package:ledger/features/accounts/application/open_account_handler.dart';
import 'package:ledger/features/reports/domain/account_balance_projection.dart';
import 'package:ledger/features/transactions/application/record_transaction_handler.dart';
import 'package:ledger/features/transactions/application/void_transaction_handler.dart';
import 'package:ledger/features/transactions/domain/leg.dart';

void main() {
  late InMemoryEventStore eventStore;
  late OpenAccountHandler openAccount;
  late CloseAccountHandler closeAccount;
  late RecordTransactionHandler recordTransaction;
  late VoidTransactionHandler voidTransaction;
  late AccountBalanceProjection projection;
  late ProjectionRunner runner;
  var idCounter = 0;

  setUp(() {
    eventStore = InMemoryEventStore();
    idCounter = 0;
    final clock = HybridLogicalClock(
      nodeId: 'test',
      physicalTimeMillis: () => 1000,
    );
    String newId() => 'evt-${idCounter++}';
    openAccount = OpenAccountHandler(
      eventStore: eventStore,
      clock: clock,
      newEventId: newId,
    );
    closeAccount = CloseAccountHandler(
      eventStore: eventStore,
      clock: clock,
      newEventId: newId,
    );
    recordTransaction = RecordTransactionHandler(
      eventStore: eventStore,
      clock: clock,
      newEventId: newId,
    );
    voidTransaction = VoidTransactionHandler(
      eventStore: eventStore,
      clock: clock,
      newEventId: newId,
    );
    projection = AccountBalanceProjection();
    runner = ProjectionRunner(eventStore, [projection]);
  });
  tearDown(() => eventStore.dispose());

  Future<void> open(String accountId) => openAccount
      .handle(
        OpenAccountCommand(
          accountId: accountId,
          name: accountId,
          currency: Currency.usd,
        ),
      )
      .then((_) {});

  test('folds a single transaction into balances on both sides', () async {
    await open('groceries');
    await open('wallet');
    await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-1',
        description: 'shop',
        occurredAt: DateTime.utc(2026, 9, 10),
        legs: [
          Leg(
            accountId: 'groceries',
            amount: Money.parse('50.00', Currency.usd),
          ),
          Leg(accountId: 'wallet', amount: Money.parse('-50.00', Currency.usd)),
        ],
      ),
    );

    await runner.rebuild();

    expect(projection.state['groceries'], Money.parse('50.00', Currency.usd));
    expect(projection.state['wallet'], Money.parse('-50.00', Currency.usd));
  });

  test(
    'accumulates balance across several transactions on the same account',
    () async {
      await open('groceries');
      await open('wallet');
      for (final amount in ['20.00', '15.50', '9.99']) {
        await recordTransaction.handle(
          RecordTransactionCommand(
            transactionId: 'tx-$amount',
            description: 'shop',
            occurredAt: DateTime.utc(2026, 9, 10),
            legs: [
              Leg(
                accountId: 'groceries',
                amount: Money.parse(amount, Currency.usd),
              ),
              Leg(
                accountId: 'wallet',
                amount: Money.parse('-$amount', Currency.usd),
              ),
            ],
          ),
        );
      }

      await runner.rebuild();

      expect(projection.state['groceries'], Money.parse('45.49', Currency.usd));
      expect(projection.state['wallet'], Money.parse('-45.49', Currency.usd));
    },
  );

  test('a voided transaction is fully reversed out of the balance', () async {
    await open('groceries');
    await open('wallet');
    await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-1',
        description: 'shop',
        occurredAt: DateTime.utc(2026, 9, 10),
        legs: [
          Leg(
            accountId: 'groceries',
            amount: Money.parse('50.00', Currency.usd),
          ),
          Leg(accountId: 'wallet', amount: Money.parse('-50.00', Currency.usd)),
        ],
      ),
    );
    await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-2',
        description: 'shop again',
        occurredAt: DateTime.utc(2026, 9, 11),
        legs: [
          Leg(
            accountId: 'groceries',
            amount: Money.parse('10.00', Currency.usd),
          ),
          Leg(accountId: 'wallet', amount: Money.parse('-10.00', Currency.usd)),
        ],
      ),
    );
    await voidTransaction.handle(
      const VoidTransactionCommand(transactionId: 'tx-1', reason: 'duplicate'),
    );

    await runner.rebuild();

    // Only tx-2 should count — tx-1 was voided out entirely.
    expect(projection.state['groceries'], Money.parse('10.00', Currency.usd));
    expect(projection.state['wallet'], Money.parse('-10.00', Currency.usd));
  });

  test('ignores account lifecycle events sharing the same log', () async {
    await open('groceries');
    await open('wallet');
    await closeAccount.handle(const CloseAccountCommand(accountId: 'wallet'));

    await runner.rebuild();

    // AccountOpened/AccountClosed produced no balance entries at all.
    expect(projection.state, isEmpty);
  });

  test('catchUp after rebuild only applies the new transaction, no double counting', () async {
    await open('groceries');
    await open('wallet');
    await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-1',
        description: 'shop',
        occurredAt: DateTime.utc(2026, 9, 10),
        legs: [
          Leg(
            accountId: 'groceries',
            amount: Money.parse('50.00', Currency.usd),
          ),
          Leg(accountId: 'wallet', amount: Money.parse('-50.00', Currency.usd)),
        ],
      ),
    );
    await runner.rebuild();

    await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-2',
        description: 'shop again',
        occurredAt: DateTime.utc(2026, 9, 11),
        legs: [
          Leg(
            accountId: 'groceries',
            amount: Money.parse('10.00', Currency.usd),
          ),
          Leg(accountId: 'wallet', amount: Money.parse('-10.00', Currency.usd)),
        ],
      ),
    );
    await runner.catchUp();

    expect(projection.state['groceries'], Money.parse('60.00', Currency.usd));

    await runner.catchUp(); // no-op
    expect(projection.state['groceries'], Money.parse('60.00', Currency.usd));
  });

  test('rebuild from scratch is deterministic', () async {
    await open('groceries');
    await open('wallet');
    await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-1',
        description: 'shop',
        occurredAt: DateTime.utc(2026, 9, 10),
        legs: [
          Leg(
            accountId: 'groceries',
            amount: Money.parse('33.33', Currency.usd),
          ),
          Leg(accountId: 'wallet', amount: Money.parse('-33.33', Currency.usd)),
        ],
      ),
    );

    await runner.rebuild();
    final first = projection.state['groceries'];
    await runner.rebuild();

    expect(projection.state['groceries'], first);
  });
}
