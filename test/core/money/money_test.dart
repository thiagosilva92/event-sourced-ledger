import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/money/money.dart';

void main() {
  const usd = Currency.usd;
  const eur = Currency.eur;
  const jpy = Currency.jpy;

  group('construction', () {
    test('ofMinor / zero', () {
      expect(const Money.ofMinor(1234, usd).minorUnits, 1234);
      expect(const Money.zero(usd).isZero, isTrue);
    });

    test('parse handles whole, fractional and signed input', () {
      expect(Money.parse('12.34', usd).minorUnits, 1234);
      expect(Money.parse('1000', usd).minorUnits, 100000);
      expect(Money.parse('-0.5', usd).minorUnits, -50);
      expect(Money.parse('  7.00  ', usd).minorUnits, 700);
      expect(Money.parse('500', jpy).minorUnits, 500);
    });

    test('parse rejects over-precise input instead of rounding', () {
      expect(() => Money.parse('1.234', usd), throwsFormatException);
      expect(() => Money.parse('1.5', jpy), throwsFormatException);
    });

    test('parse rejects garbage', () {
      expect(() => Money.parse('abc', usd), throwsFormatException);
      expect(() => Money.parse('1,50', usd), throwsFormatException);
      expect(() => Money.parse('', usd), throwsFormatException);
    });
  });

  group('arithmetic', () {
    test('add and subtract', () {
      expect(
        Money.parse('1.50', usd) + Money.parse('2.75', usd),
        Money.parse('4.25', usd),
      );
      expect(
        Money.parse('1.00', usd) - Money.parse('2.50', usd),
        Money.parse('-1.50', usd),
      );
    });

    test('negate and scale', () {
      expect(-Money.parse('3.00', usd), Money.parse('-3.00', usd));
      expect(Money.parse('1.11', usd) * 3, Money.parse('3.33', usd));
    });

    test('mixing currencies throws', () {
      expect(
        () => Money.parse('1.00', usd) + Money.parse('1.00', eur),
        throwsA(isA<CurrencyMismatchError>()),
      );
      expect(
        () => Money.parse('1.00', usd).compareTo(Money.parse('1.00', eur)),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });
  });

  group('comparison', () {
    test('operators and sort', () {
      expect(Money.parse('1.00', usd) < Money.parse('1.01', usd), isTrue);
      expect(Money.parse('1.00', usd) >= Money.parse('1.00', usd), isTrue);
      final list = [
        Money.parse('3.00', usd),
        Money.parse('-1.00', usd),
        Money.parse('0.50', usd),
      ]..sort();
      expect(list.map((m) => m.toDecimalString()), ['-1.00', '0.50', '3.00']);
    });
  });

  group('allocate', () {
    test('distributes remainder cents without loss', () {
      final parts = Money.parse('10.00', usd).allocate(3);
      expect(parts.map((m) => m.toDecimalString()), ['3.34', '3.33', '3.33']);
      expect(parts.reduce((a, b) => a + b), Money.parse('10.00', usd));
    });

    test('exact division', () {
      final parts = Money.parse('9.00', usd).allocate(3);
      expect(parts.every((m) => m == Money.parse('3.00', usd)), isTrue);
    });

    test('negative amounts keep sign and still sum back', () {
      final parts = Money.parse('-10.00', usd).allocate(3);
      expect(parts.map((m) => m.toDecimalString()), [
        '-3.34',
        '-3.33',
        '-3.33',
      ]);
      expect(parts.reduce((a, b) => a + b), Money.parse('-10.00', usd));
    });

    test('rejects non-positive parts', () {
      expect(() => Money.parse('1.00', usd).allocate(0), throwsArgumentError);
    });

    test('property: any split sums back to the original', () {
      final amount = Money.parse('123.45', usd);
      for (var parts = 1; parts <= 40; parts++) {
        expect(
          amount.allocate(parts).reduce((a, b) => a + b),
          amount,
          reason: 'failed for parts=$parts',
        );
      }
    });
  });

  group('allocateByWeights', () {
    test('splits by ratio, remainder to earliest weights', () {
      final parts = Money.parse('10.00', usd).allocateByWeights([1, 1, 2]);
      expect(parts.map((m) => m.toDecimalString()), ['2.50', '2.50', '5.00']);
      expect(parts.reduce((a, b) => a + b), Money.parse('10.00', usd));
    });

    test('uneven ratio still sums back', () {
      final parts = Money.parse('0.10', usd).allocateByWeights([1, 1, 1]);
      expect(parts.reduce((a, b) => a + b), Money.parse('0.10', usd));
    });

    test('rejects invalid weights', () {
      expect(
        () => Money.parse('1.00', usd).allocateByWeights([]),
        throwsArgumentError,
      );
      expect(
        () => Money.parse('1.00', usd).allocateByWeights([0, 0]),
        throwsArgumentError,
      );
      expect(
        () => Money.parse('1.00', usd).allocateByWeights([-1, 2]),
        throwsArgumentError,
      );
    });
  });

  group('formatting', () {
    test('toDecimalString pads and signs correctly', () {
      expect(const Money.ofMinor(5, usd).toDecimalString(), '0.05');
      expect(const Money.ofMinor(-5, usd).toDecimalString(), '-0.05');
      expect(const Money.ofMinor(100000, usd).toDecimalString(), '1000.00');
      expect(const Money.ofMinor(500, jpy).toDecimalString(), '500');
    });

    test('toString includes currency code', () {
      expect(Money.parse('12.34', usd).toString(), '12.34 USD');
    });

    test('round-trips through parse', () {
      for (final raw in ['0.00', '-1.05', '999.99', '1000000.01']) {
        expect(Money.parse(raw, usd).toDecimalString(), raw);
      }
    });
  });

  group('value equality', () {
    test('equal by amount and currency', () {
      expect(const Money.ofMinor(100, usd), const Money.ofMinor(100, usd));
      expect(
        const Money.ofMinor(100, usd) == const Money.ofMinor(100, eur),
        isFalse,
      );
      expect(
        const Money.ofMinor(1, usd).hashCode,
        const Money.ofMinor(1, usd).hashCode,
      );
    });
  });
}
