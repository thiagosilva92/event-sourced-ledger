import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/features/transactions/domain/leg.dart';

void main() {
  test('toJson / fromJson round-trips exactly', () {
    final leg = Leg(
      accountId: 'acc-1',
      amount: Money.parse('12.34', Currency.usd),
    );

    final rebuilt = Leg.fromJson(leg.toJson());

    expect(rebuilt, leg);
    expect(rebuilt.amount, leg.amount);
  });

  test('value equality by accountId and amount', () {
    final a = Leg(
      accountId: 'acc-1',
      amount: Money.parse('10.00', Currency.usd),
    );
    final b = Leg(
      accountId: 'acc-1',
      amount: Money.parse('10.00', Currency.usd),
    );
    final differentAccount = Leg(
      accountId: 'acc-2',
      amount: Money.parse('10.00', Currency.usd),
    );
    final differentAmount = Leg(
      accountId: 'acc-1',
      amount: Money.parse('20.00', Currency.usd),
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == differentAccount, isFalse);
    expect(a == differentAmount, isFalse);
  });

  test('handles a negative (credit) amount', () {
    final leg = Leg(
      accountId: 'acc-1',
      amount: Money.parse('-5.00', Currency.usd),
    );
    expect(Leg.fromJson(leg.toJson()), leg);
  });
}
