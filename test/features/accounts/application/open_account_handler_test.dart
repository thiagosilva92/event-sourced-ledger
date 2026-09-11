import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/core/result/result.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/application/open_account_handler.dart';

void main() {
  late InMemoryEventStore eventStore;
  late OpenAccountHandler handler;
  var idCounter = 0;

  setUp(() {
    eventStore = InMemoryEventStore();
    idCounter = 0;
    handler = OpenAccountHandler(
      eventStore: eventStore,
      clock: HybridLogicalClock(nodeId: 'test', physicalTimeMillis: () => 1000),
      newEventId: () => 'evt-${idCounter++}',
    );
  });
  tearDown(() => eventStore.dispose());

  test('opens a new account and persists AccountOpened', () async {
    final result = await handler.handle(
      const OpenAccountCommand(
        accountId: 'acc-1',
        name: 'Groceries',
        currency: Currency.usd,
      ),
    );

    expect(result, isA<Ok<String, OpenAccountFailure>>());
    expect(result.valueOrNull, 'acc-1');

    final stored = await eventStore.readAggregate('acc-1');
    expect(stored, hasLength(1));
    expect(stored.single.eventType, 'account.opened');
  });

  test('rejects an id that is already in use', () async {
    await handler.handle(
      const OpenAccountCommand(
        accountId: 'acc-1',
        name: 'Groceries',
        currency: Currency.usd,
      ),
    );

    final result = await handler.handle(
      const OpenAccountCommand(
        accountId: 'acc-1',
        name: 'Something else',
        currency: Currency.usd,
      ),
    );

    expect(
      result,
      const Err<String, OpenAccountFailure>(AccountIdAlreadyUsed('acc-1')),
    );
    // Nothing from the rejected command was written.
    expect(await eventStore.readAggregate('acc-1'), hasLength(1));
  });

  test('rejects a blank name without touching the event store', () async {
    final result = await handler.handle(
      const OpenAccountCommand(
        accountId: 'acc-1',
        name: '  ',
        currency: Currency.usd,
      ),
    );

    expect(result.isErr, isTrue);
    expect(result.failureOrNull, isA<InvalidAccountName>());
    expect(await eventStore.readAggregate('acc-1'), isEmpty);
  });
}
