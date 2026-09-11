import 'package:ledger/core/money/money.dart';
import 'package:meta/meta.dart';

/// One side of a double-entry posting: a signed [amount] against one
/// [accountId]. A transaction's legs must sum to zero — see
/// `LedgerTransaction.record`.
///
/// References the account by id only, never by object — aggregates never
/// hold references to other aggregates.
@immutable
final class Leg {
  const Leg({required this.accountId, required this.amount});

  factory Leg.fromJson(Map<String, Object?> json) => Leg(
    accountId: json['accountId']! as String,
    amount: Money.ofMinor(
      json['amountMinorUnits']! as int,
      Currency(
        json['currencyCode']! as String,
        decimalPlaces: json['currencyDecimalPlaces']! as int,
      ),
    ),
  );

  final String accountId;
  final Money amount;

  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'amountMinorUnits': amount.minorUnits,
    'currencyCode': amount.currency.code,
    'currencyDecimalPlaces': amount.currency.decimalPlaces,
  };

  @override
  bool operator ==(Object other) =>
      other is Leg && other.accountId == accountId && other.amount == amount;

  @override
  int get hashCode => Object.hash(accountId, amount);

  @override
  String toString() => 'Leg($accountId: $amount)';
}
