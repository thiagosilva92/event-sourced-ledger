import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/core/result/result.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/application/close_account_handler.dart';
import 'package:ledger/features/accounts/application/open_account_handler.dart';
import 'package:ledger/features/transactions/application/record_transaction_handler.dart';
import 'package:ledger/features/transactions/domain/leg.dart';

void main() {
  late InMemoryEventStore eventStore;
  late OpenAccountHandler openAccount;
  late CloseAccountHandler closeAccount;
  late RecordTransactionHandler recordTransaction;
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
  });
  tearDown(() => eventStore.dispose());

  Future<void> open(String accountId, String name) => openAccount
      .handle(
        OpenAccountCommand(
          accountId: accountId,
          name: name,
          currency: Currency.usd,
        ),
      )
      .then((_) {});

  test('records a balanced transaction between two open accounts', () async {
    await open('groceries', 'Groceries');
    await open('wallet', 'Shared wallet');

    final result = await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-1',
        description: 'Weekly shop',
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

    expect(result, const Ok<String, RecordTransactionFailure>('tx-1'));
    final stored = await eventStore.readAggregate('tx-1');
    expect(stored.single.eventType, 'transaction.recorded');
  });

  test('records a three-way split across three open accounts', () async {
    await open('rent', 'Rent');
    await open('alice', 'Alice');
    await open('bob', 'Bob');

    final result = await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-1',
        description: 'Split rent',
        occurredAt: DateTime.utc(2026, 9, 10),
        legs: [
          Leg(accountId: 'rent', amount: Money.parse('600.00', Currency.usd)),
          Leg(accountId: 'alice', amount: Money.parse('-300.00', Currency.usd)),
          Leg(accountId: 'bob', amount: Money.parse('-300.00', Currency.usd)),
        ],
      ),
    );

    expect(result.isOk, isTrue);
  });

  test('rejects a leg referencing an account that does not exist', () async {
    await open('groceries', 'Groceries');
    // 'wallet' was never opened.

    final result = await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-1',
        description: 'Weekly shop',
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

    expect(
      result,
      const Err<String, RecordTransactionFailure>(
        ReferencedAccountNotFound('wallet'),
      ),
    );
    // Nothing was written — a partially-valid transaction is not recorded.
    expect(await eventStore.readAggregate('tx-1'), isEmpty);
  });

  test(
    'rejects a leg referencing a closed account — the compensating-event '
    'scenario the README describes, without needing sync to trigger it',
    () async {
      await open('groceries', 'Groceries');
      await open('old-wallet', 'Old wallet');
      await closeAccount.handle(
        const CloseAccountCommand(accountId: 'old-wallet'),
      );

      final result = await recordTransaction.handle(
        RecordTransactionCommand(
          transactionId: 'tx-1',
          description: 'Weekly shop',
          occurredAt: DateTime.utc(2026, 9, 10),
          legs: [
            Leg(
              accountId: 'groceries',
              amount: Money.parse('50.00', Currency.usd),
            ),
            Leg(
              accountId: 'old-wallet',
              amount: Money.parse('-50.00', Currency.usd),
            ),
          ],
        ),
      );

      expect(
        result,
        const Err<String, RecordTransactionFailure>(
          ReferencedAccountClosed('old-wallet'),
        ),
      );
    },
  );

  test("rejects unbalanced legs, translating LedgerTransaction's own "
      'invariant into InvalidLegs', () async {
    await open('groceries', 'Groceries');
    await open('wallet', 'Shared wallet');

    final result = await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-1',
        description: 'Weekly shop',
        occurredAt: DateTime.utc(2026, 9, 10),
        legs: [
          Leg(
            accountId: 'groceries',
            amount: Money.parse('50.00', Currency.usd),
          ),
          Leg(accountId: 'wallet', amount: Money.parse('-40.00', Currency.usd)),
        ],
      ),
    );

    expect(result.isErr, isTrue);
    expect(result.failureOrNull, isA<InvalidLegs>());
    expect(await eventStore.readAggregate('tx-1'), isEmpty);
  });

  test('rejects reusing a transaction id', () async {
    await open('groceries', 'Groceries');
    await open('wallet', 'Shared wallet');
    final legs = [
      Leg(accountId: 'groceries', amount: Money.parse('50.00', Currency.usd)),
      Leg(accountId: 'wallet', amount: Money.parse('-50.00', Currency.usd)),
    ];
    await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-1',
        description: 'first',
        occurredAt: DateTime.utc(2026, 9, 10),
        legs: legs,
      ),
    );

    final result = await recordTransaction.handle(
      RecordTransactionCommand(
        transactionId: 'tx-1',
        description: 'second',
        occurredAt: DateTime.utc(2026, 9, 11),
        legs: legs,
      ),
    );

    expect(
      result,
      const Err<String, RecordTransactionFailure>(
        TransactionIdAlreadyUsed('tx-1'),
      ),
    );
  });
}
