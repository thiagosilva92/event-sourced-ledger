import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/clock/hlc.dart';

/// A controllable physical clock for deterministic tests.
class _FakeClock {
  int millis = 1000;
  int read() => millis;
}

void main() {
  group('Hlc value', () {
    test('ordering by wall, then counter, then nodeId', () {
      const a = Hlc(wallMillis: 10, counter: 0, nodeId: 'a');
      const b = Hlc(wallMillis: 10, counter: 1, nodeId: 'a');
      const c = Hlc(wallMillis: 11, counter: 0, nodeId: 'a');
      const aOtherNode = Hlc(wallMillis: 10, counter: 0, nodeId: 'b');

      expect(a < b, isTrue);
      expect(b < c, isTrue);
      expect(a < aOtherNode, isTrue);
      expect([c, b, a]..sort(), [a, b, c]);
    });

    test('toString / parse round-trip', () {
      const ts = Hlc(wallMillis: 1694300000000, counter: 3, nodeId: 'device-a');
      expect(ts.toString(), '1694300000000-0003-device-a');
      expect(Hlc.parse(ts.toString()), ts);
    });

    test('parse tolerates dashes in nodeId', () {
      final ts = Hlc.parse('42-0007-node-with-dashes');
      expect(ts.wallMillis, 42);
      expect(ts.counter, 7);
      expect(ts.nodeId, 'node-with-dashes');
    });

    test('parse rejects malformed input', () {
      expect(() => Hlc.parse('nope'), throwsFormatException);
      expect(() => Hlc.parse('10-5-'), throwsFormatException);
    });

    test('value equality', () {
      expect(
        const Hlc(wallMillis: 1, counter: 2, nodeId: 'x'),
        const Hlc(wallMillis: 1, counter: 2, nodeId: 'x'),
      );
      expect(
        const Hlc(wallMillis: 1, counter: 2, nodeId: 'x').hashCode,
        const Hlc(wallMillis: 1, counter: 2, nodeId: 'x').hashCode,
      );
    });
  });

  group('HybridLogicalClock.now', () {
    test('advances counter within the same millisecond', () {
      final clock = _FakeClock();
      final hlc = HybridLogicalClock(
        nodeId: 'a',
        physicalTimeMillis: clock.read,
      );

      final t1 = hlc.now();
      final t2 = hlc.now();
      final t3 = hlc.now();

      expect(t1.wallMillis, 1000);
      expect([t1.counter, t2.counter, t3.counter], [0, 1, 2]);
      expect(t1 < t2, isTrue);
      expect(t2 < t3, isTrue);
    });

    test('resets counter when wall clock moves forward', () {
      final clock = _FakeClock();
      final hlc = HybridLogicalClock(
        nodeId: 'a',
        physicalTimeMillis: clock.read,
      );

      hlc.now();
      hlc.now();
      clock.millis = 1001;
      final t = hlc.now();

      expect(t.wallMillis, 1001);
      expect(t.counter, 0);
    });

    test('never goes backwards when the wall clock does', () {
      final clock = _FakeClock();
      final hlc = HybridLogicalClock(
        nodeId: 'a',
        physicalTimeMillis: clock.read,
      );

      final t1 = hlc.now();
      clock.millis = 500; // clock jumped back
      final t2 = hlc.now();

      expect(t2 > t1, isTrue);
      expect(t2.wallMillis, 1000);
      expect(t2.counter, 1);
    });

    test('throws on counter overflow', () {
      final clock = _FakeClock();
      final hlc = HybridLogicalClock(
        nodeId: 'a',
        physicalTimeMillis: clock.read,
        maxCounter: 3,
      );

      hlc.now();
      hlc.now();
      hlc.now();
      hlc.now();
      expect(hlc.now, throwsStateError);
    });
  });

  group('HybridLogicalClock.receive', () {
    test('adopts a higher remote wall time and increments from it', () {
      final clock = _FakeClock();
      final hlc = HybridLogicalClock(
        nodeId: 'a',
        physicalTimeMillis: clock.read,
      );

      final result = hlc.receive(
        const Hlc(wallMillis: 5000, counter: 7, nodeId: 'b'),
      );

      expect(result.wallMillis, 5000);
      expect(result.counter, 8);
      expect(result.nodeId, 'a');
    });

    test('same wall on both sides takes max counter + 1', () {
      final clock = _FakeClock()..millis = 5000;
      final hlc = HybridLogicalClock(
        nodeId: 'a',
        physicalTimeMillis: clock.read,
      );
      hlc.now(); // local (5000, 0)

      final result = hlc.receive(
        const Hlc(wallMillis: 5000, counter: 4, nodeId: 'b'),
      );

      expect(result.wallMillis, 5000);
      expect(result.counter, 5);
    });

    test('local physical time ahead of both resets counter', () {
      final clock = _FakeClock()..millis = 9000;
      final hlc = HybridLogicalClock(
        nodeId: 'a',
        physicalTimeMillis: clock.read,
      );

      final result = hlc.receive(
        const Hlc(wallMillis: 5000, counter: 4, nodeId: 'b'),
      );

      expect(result.wallMillis, 9000);
      expect(result.counter, 0);
    });

    test('rejects a remote timestamp too far in the future', () {
      final clock = _FakeClock()..millis = 1000;
      final hlc = HybridLogicalClock(
        nodeId: 'a',
        physicalTimeMillis: clock.read,
        maxDriftMillis: 1000,
      );

      expect(
        () =>
            hlc.receive(const Hlc(wallMillis: 999999, counter: 0, nodeId: 'b')),
        throwsA(isA<ClockDriftError>()),
      );
    });

    test('causal chain across two nodes stays ordered', () {
      final clockA = _FakeClock()..millis = 1000;
      final clockB = _FakeClock()..millis = 1000;
      final a = HybridLogicalClock(
        nodeId: 'a',
        physicalTimeMillis: clockA.read,
      );
      final b = HybridLogicalClock(
        nodeId: 'b',
        physicalTimeMillis: clockB.read,
      );

      final e1 = a.now(); // a creates
      final e2 = b.receive(e1); // b sees e1, then...
      clockB.millis = 1000; // ...creates in the same ms
      final e3 = b.now();
      final e4 = a.receive(e3); // a sees e3

      expect(e1 < e2, isTrue);
      expect(e2 < e3, isTrue);
      expect(e3 < e4, isTrue);
    });
  });

  test('rejects an initial timestamp from another node', () {
    expect(
      () => HybridLogicalClock(
        nodeId: 'a',
        physicalTimeMillis: () => 0,
        initial: const Hlc(wallMillis: 1, counter: 0, nodeId: 'b'),
      ),
      throwsArgumentError,
    );
  });
}
