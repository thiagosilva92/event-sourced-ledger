import 'package:meta/meta.dart';

/// An ISO-4217-style currency descriptor.
///
/// Only what the ledger needs: the alphabetic code and how many minor units
/// make up one major unit (2 for USD/EUR/BRL, 0 for JPY, 3 for BHD).
@immutable
final class Currency {
  const Currency(this.code, {required this.decimalPlaces})
    : assert(code.length == 3, 'currency code must be 3 letters'),
      assert(
        decimalPlaces >= 0 && decimalPlaces <= 4,
        'decimalPlaces out of range',
      );

  /// Uppercase alphabetic code, e.g. `USD`.
  final String code;

  /// Number of minor units in one major unit. `100` cents => `2`.
  final int decimalPlaces;

  /// Minor units per major unit (`10 ^ decimalPlaces`).
  int get minorUnitsPerMajor {
    var factor = 1;
    for (var i = 0; i < decimalPlaces; i++) {
      factor *= 10;
    }
    return factor;
  }

  static const Currency usd = Currency('USD', decimalPlaces: 2);
  static const Currency eur = Currency('EUR', decimalPlaces: 2);
  static const Currency brl = Currency('BRL', decimalPlaces: 2);
  static const Currency jpy = Currency('JPY', decimalPlaces: 0);

  @override
  bool operator ==(Object other) =>
      other is Currency &&
      other.code == code &&
      other.decimalPlaces == decimalPlaces;

  @override
  int get hashCode => Object.hash(code, decimalPlaces);

  @override
  String toString() => code;
}
