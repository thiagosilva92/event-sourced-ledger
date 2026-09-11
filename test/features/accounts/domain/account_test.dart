import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/features/accounts/domain/account.dart';
import 'package:ledger/features/accounts/domain/account_events.dart';

import '../../../support/event_context_fixture.dart';

void main() {
  setUp(resetEventContextFixture);

  test('open sets name, currency and isOpen, and raises one event', () {
    final account = Account('acc-1')
      ..open(nextEventContext(), name: 'Groceries', currency: Currency.usd);

    expect(account.name, 'Groceries');
    expect(account.currency, Currency.usd);
    expect(account.isOpen, isTrue);
    expect(account.version, 1);
    expect(account.pendingEvents, hasLength(1));
    expect(account.pendingEvents.single, isA<AccountOpened>());
  });

  test('open rejects a blank name', () {
    final account = Account('acc-1');
    expect(
      () =>
          account.open(nextEventContext(), name: '   ', currency: Currency.usd),
      throwsArgumentError,
    );
    expect(account.hasPendingEvents, isFalse);
  });

  test('open rejects opening the same aggregate twice', () {
    final account = Account('acc-1')
      ..open(nextEventContext(), name: 'Groceries', currency: Currency.usd);
    expect(
      () => account.open(
        nextEventContext(),
        name: 'Again',
        currency: Currency.usd,
      ),
      throwsStateError,
    );
  });

  test('open rejects reopening a closed account', () {
    final account = Account('acc-1')
      ..open(nextEventContext(), name: 'Groceries', currency: Currency.usd)
      ..close(nextEventContext());
    expect(
      () => account.open(
        nextEventContext(),
        name: 'Again',
        currency: Currency.usd,
      ),
      throwsStateError,
    );
  });

  test('rename updates name without touching currency or open state', () {
    final account = Account('acc-1')
      ..open(nextEventContext(), name: 'Groceries', currency: Currency.usd)
      ..rename(nextEventContext(), 'Food & Household');

    expect(account.name, 'Food & Household');
    expect(account.currency, Currency.usd);
    expect(account.isOpen, isTrue);
    expect(account.version, 2);
  });

  test('rename rejects a blank name', () {
    final account = Account('acc-1')
      ..open(nextEventContext(), name: 'Groceries', currency: Currency.usd);
    expect(() => account.rename(nextEventContext(), ''), throwsArgumentError);
  });

  test('rename on an unopened account throws', () {
    final account = Account('acc-1');
    expect(() => account.rename(nextEventContext(), 'x'), throwsStateError);
  });

  test('close sets isOpen to false', () {
    final account = Account('acc-1')
      ..open(nextEventContext(), name: 'Groceries', currency: Currency.usd)
      ..close(nextEventContext());

    expect(account.isOpen, isFalse);
    expect(account.pendingEvents.map((e) => e.eventType), [
      'account.opened',
      'account.closed',
    ]);
  });

  test('close on an unopened account throws', () {
    final account = Account('acc-1');
    expect(() => account.close(nextEventContext()), throwsStateError);
  });

  test('close on an already-closed account throws', () {
    final account = Account('acc-1')
      ..open(nextEventContext(), name: 'Groceries', currency: Currency.usd)
      ..close(nextEventContext());
    expect(() => account.close(nextEventContext()), throwsStateError);
  });

  test('currency getter throws on an unopened account', () {
    expect(() => Account('acc-1').currency, throwsStateError);
  });

  test('rehydrates from history to the same state raise() produced', () {
    final source = Account('acc-1')
      ..open(nextEventContext(), name: 'Groceries', currency: Currency.usd)
      ..rename(nextEventContext(), 'Food');
    final history = source.pendingEvents;

    final rebuilt = Account('acc-1')..loadFromHistory(history);

    expect(rebuilt.name, 'Food');
    expect(rebuilt.currency, Currency.usd);
    expect(rebuilt.isOpen, isTrue);
    expect(rebuilt.version, 2);
    expect(rebuilt.hasPendingEvents, isFalse);
  });
}
