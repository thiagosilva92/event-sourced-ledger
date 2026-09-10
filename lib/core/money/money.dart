import 'package:ledger/core/money/currency.dart';
import 'package:meta/meta.dart';

export 'package:ledger/core/money/currency.dart';

/// Thrown when an operation mixes two different currencies.
class CurrencyMismatchError extends Error {
  CurrencyMismatchError(this.left, this.right);

  final Currency left;
  final Currency right;

  @override
  String toString() =>
      'CurrencyMismatchError: cannot combine $left with $right';
}

/// An exact monetary amount held as a signed integer count of **minor units**
/// (cents), tagged with its [Currency].
///
/// Floating point is never used for arithmetic — `0.1 + 0.2 != 0.3` has no
/// place in a ledger. Amounts are only converted to/from decimal strings at
/// the edges (parsing user input, formatting for display).
@immutable
final class Money implements Comparable<Money> {
  const Money._(this.minorUnits, this.currency);

  /// Creates an amount directly from a minor-unit count (e.g. cents).
  const Money.ofMinor(int minorUnits, Currency currency)
    : this._(minorUnits, currency);

  /// Zero in [currency].
  const Money.zero(Currency currency) : this._(0, currency);

  /// Parses a decimal string such as `"12.34"`, `"-0.5"` or `"1000"`.
  ///
  /// Rejects values with more fractional digits than the currency allows
  /// rather than rounding silently — the caller decides how to round input.
  factory Money.parse(String value, Currency currency) {
    final trimmed = value.trim();
    final match = _decimalPattern.firstMatch(trimmed);
    if (match == null) {
      throw FormatException('not a decimal amount: "$value"');
    }
    final sign = match.group(1) == '-' ? -1 : 1;
    final whole = match.group(2)!;
    final fraction = match.group(3) ?? '';
    if (fraction.length > currency.decimalPlaces) {
      throw FormatException(
        '"$value" has more than ${currency.decimalPlaces} decimal places '
        'for $currency',
      );
    }
    final paddedFraction = fraction.padRight(currency.decimalPlaces, '0');
    final minor = int.parse('$whole$paddedFraction');
    return Money._(sign * minor, currency);
  }

  static final RegExp _decimalPattern = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$');

  /// Signed amount in minor units.
  final int minorUnits;
  final Currency currency;

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;
  bool get isPositive => minorUnits > 0;

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money._(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money._(minorUnits - other.minorUnits, currency);
  }

  Money operator -() => Money._(-minorUnits, currency);

  /// Scales the amount by an integer factor. Non-integer scaling would raise
  /// rounding questions the ledger should answer explicitly via [allocate].
  Money operator *(int factor) => Money._(minorUnits * factor, currency);

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  /// Splits this amount into [parts] pieces that sum back to exactly this
  /// amount. The remainder cent(s) are distributed one-by-one to the first
  /// pieces, so no fraction of a cent is ever created or lost.
  ///
  /// Example: `Money.parse('10.00', usd).allocate(3)` =>
  /// `[3.34, 3.33, 3.33]`.
  List<Money> allocate(int parts) {
    if (parts <= 0) {
      throw ArgumentError.value(parts, 'parts', 'must be positive');
    }
    final base = minorUnits ~/ parts;
    var remainder = minorUnits.remainder(parts).abs();
    final step = minorUnits.isNegative ? -1 : 1;
    return List<Money>.generate(parts, (i) {
      var share = base;
      if (remainder > 0) {
        share += step;
        remainder--;
      }
      return Money._(share, currency);
    });
  }

  /// Splits this amount across integer [weights] (e.g. `[1, 1, 2]`).
  /// Remainder cents go to the earliest weights.
  List<Money> allocateByWeights(List<int> weights) {
    if (weights.isEmpty ||
        weights.any((w) => w < 0) ||
        weights.every((w) => w == 0)) {
      throw ArgumentError.value(weights, 'weights', 'invalid weight list');
    }
    final total = weights.reduce((a, b) => a + b);
    var allocated = 0;
    final result = <Money>[];
    for (var i = 0; i < weights.length; i++) {
      if (i == weights.length - 1) {
        result.add(Money._(minorUnits - allocated, currency));
      } else {
        final share = minorUnits * weights[i] ~/ total;
        allocated += share;
        result.add(Money._(share, currency));
      }
    }
    return result;
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw CurrencyMismatchError(currency, other.currency);
    }
  }

  /// Decimal representation without a currency symbol, e.g. `"-12.34"`.
  String toDecimalString() {
    final places = currency.decimalPlaces;
    final sign = isNegative ? '-' : '';
    final digits = minorUnits.abs().toString().padLeft(places + 1, '0');
    if (places == 0) return '$sign$digits';
    final whole = digits.substring(0, digits.length - places);
    final fraction = digits.substring(digits.length - places);
    return '$sign$whole.$fraction';
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '${toDecimalString()} ${currency.code}';
}
