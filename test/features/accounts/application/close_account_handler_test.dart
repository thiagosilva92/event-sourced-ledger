import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/core/result/result.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/application/close_account_handler.dart';
import 'package:ledger/features/accounts/application/open_account_handler.dart';

void main() {
  late InMemoryEventStore eventStore;
  late OpenAccountHandler openHandler;
  late CloseAccountHandler closeHandler;
  var idCounter = 0;

  setUp(() {
    eventStore = InMemoryEventStore();
    idCounter = 0;
    final clock = HybridLogicalClock(
      nodeId: 'test',
      physicalTimeMillis: () => 1000,
    );
    String newId() => 'evt-${idCounter++}';
    openHandler = OpenAccountHandler(
      eventStore: eventStore,
      clock: clock,
      newEventId: newId,
    );
    closeHandler = CloseAccountHandler(
      eventStore: eventStore,
      clock: clock,
      newEventId: newId,
    );
  });
  tearDown(() => eventStore.dispose());

  test('closes an open account', () async {
    await openHandler.handle(
      const OpenAccountCommand(
        accountId: 'acc-1',
        name: 'Groceries',
        currency: Currency.usd,
      ),
    );

    final result = await closeHandler.handle(
      const CloseAccountCommand(accountId: 'acc-1'),
    );

    expect(result.isOk, isTrue);
    final stored = await eventStore.readAggregate('acc-1');
    expect(stored.map((e) => e.eventType), [
      'account.opened',
      'account.closed',
    ]);
  });

  test('rejects closing an account that does not exist', () async {
    final result = await closeHandler.handle(
      const CloseAccountCommand(accountId: 'nope'),
    );
    expect(
      result,
      const Err<void, CloseAccountFailure>(AccountNotFound('nope')),
    );
  });

  test('rejects closing an already-closed account', () async {
    await openHandler.handle(
      const OpenAccountCommand(
        accountId: 'acc-1',
        name: 'Groceries',
        currency: Currency.usd,
      ),
    );
    await closeHandler.handle(const CloseAccountCommand(accountId: 'acc-1'));

    final result = await closeHandler.handle(
      const CloseAccountCommand(accountId: 'acc-1'),
    );

    expect(
      result,
      const Err<void, CloseAccountFailure>(AccountAlreadyClosed('acc-1')),
    );
  });
}
