import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/result/result.dart';

void main() {
  group('construction and predicates', () {
    test('ok', () {
      const r = Result<int, String>.ok(42);
      expect(r.isOk, isTrue);
      expect(r.isErr, isFalse);
      expect(r.valueOrNull, 42);
      expect(r.failureOrNull, isNull);
    });

    test('err', () {
      const r = Result<int, String>.err('boom');
      expect(r.isErr, isTrue);
      expect(r.valueOrNull, isNull);
      expect(r.failureOrNull, 'boom');
    });
  });

  group('map / flatMap / mapErr', () {
    test('map transforms only success', () {
      expect(
        const Result<int, String>.ok(2).map((v) => v * 10),
        const Ok<int, String>(20),
      );
      expect(
        const Result<int, String>.err('e').map((v) => v * 10),
        const Err<int, String>('e'),
      );
    });

    test('flatMap chains fallible steps', () {
      Result<int, String> half(int n) =>
          n.isEven ? Ok(n ~/ 2) : const Err('odd');

      expect(
        const Result<int, String>.ok(8).flatMap(half).flatMap(half),
        const Ok<int, String>(2),
      );
      expect(
        const Result<int, String>.ok(6).flatMap(half).flatMap(half),
        const Err<int, String>('odd'),
      );
    });

    test('mapErr transforms only failure', () {
      expect(
        const Result<int, String>.err('e').mapErr((f) => f.toUpperCase()),
        const Err<int, String>('E'),
      );
      expect(
        const Result<int, String>.ok(1).mapErr((f) => '$f!'),
        const Ok<int, String>(1),
      );
    });
  });

  group('fold / getOrElse', () {
    test('fold collapses both branches', () {
      String describe(Result<int, String> r) =>
          r.fold((v) => 'value $v', (f) => 'error $f');
      expect(describe(const Ok(1)), 'value 1');
      expect(describe(const Err('x')), 'error x');
    });

    test('getOrElse returns fallback on failure', () {
      expect(const Result<int, String>.ok(5).getOrElse((_) => 0), 5);
      expect(const Result<int, String>.err('x').getOrElse((_) => 0), 0);
    });
  });

  group('value equality', () {
    test('Ok and Err compare by contents', () {
      expect(const Ok<int, String>(1), const Ok<int, String>(1));
      expect(const Err<int, String>('a'), const Err<int, String>('a'));
      expect(const Ok<int, String>(1) == const Ok<int, String>(2), isFalse);
    });

    test('exhaustive switch works', () {
      const Result<int, String> r = Ok(7);
      final out = switch (r) {
        Ok(:final value) => value,
        Err(:final failure) => failure.length,
      };
      expect(out, 7);
    });
  });
}
