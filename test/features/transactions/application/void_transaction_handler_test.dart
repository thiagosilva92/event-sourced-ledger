import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/core/result/result.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/application/open_account_handler.dart';
import 'package:ledger/features/transactions/application/record_transaction_handler.dart';
import 'package:ledger/features/transactions/application/void_transaction_handler.dart';
import 'package:ledger/features/transactions/domain/leg.dart';

void main() {
  late InMemoryEventStore eventStore;
  late OpenAccountHandler openAccount;
  late RecordTransactionHandler recordTransaction;
  late VoidTransactionHandler voidTransaction;
  var idCounter = 0;

  setUp(() async {
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

    await openAccount.handle(
      const OpenAccountCommand(
        accountId: 'groceries',
        name: 'Groceries',
        currency: Currency.usd,
      ),
    );
    await openAccount.handle(
      const OpenAccountCommand(
        accountId: 'wallet',
        name: 'Wallet',
        currency: Currency.usd,
      ),
    );
    await recordTransaction.handle(
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
  });
  tearDown(() => eventStore.dispose());

  test('voids a recorded transaction', () async {
    final result = await voidTransaction.handle(
      const VoidTransactionCommand(
        transactionId: 'tx-1',
        reason: 'duplicate entry',
      ),
    );

    expect(result.isOk, isTrue);
    final stored = await eventStore.readAggregate('tx-1');
    expect(stored.map((e) => e.eventType), [
      'transaction.recorded',
      'transaction.voided',
    ]);
  });

  test('rejects voiding a transaction that does not exist', () async {
    final result = await voidTransaction.handle(
      const VoidTransactionCommand(transactionId: 'nope', reason: 'x'),
    );
    expect(
      result,
      const Err<void, VoidTransactionFailure>(TransactionNotFound('nope')),
    );
  });

  test('rejects voiding an already-voided transaction', () async {
    await voidTransaction.handle(
      const VoidTransactionCommand(transactionId: 'tx-1', reason: 'first'),
    );

    final result = await voidTransaction.handle(
      const VoidTransactionCommand(transactionId: 'tx-1', reason: 'second'),
    );

    expect(
      result,
      const Err<void, VoidTransactionFailure>(TransactionAlreadyVoided('tx-1')),
    );
  });

  test('rejects a blank reason', () async {
    final result = await voidTransaction.handle(
      const VoidTransactionCommand(transactionId: 'tx-1', reason: '  '),
    );
    expect(result.failureOrNull, isA<InvalidVoidReason>());
  });
}
