import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/features/transactions/domain/ledger_transaction.dart';
import 'package:ledger/features/transactions/domain/leg.dart';
import 'package:ledger/features/transactions/domain/transaction_events.dart';

import '../../../support/event_context_fixture.dart';

void main() {
  setUp(resetEventContextFixture);

  final occurredAt = DateTime.utc(2026, 9, 10);

  List<Leg> balancedLegs() => [
    Leg(accountId: 'groceries', amount: Money.parse('50.00', Currency.usd)),
    Leg(accountId: 'wallet', amount: Money.parse('-50.00', Currency.usd)),
  ];

  group('record', () {
    test('accepts balanced legs and raises one event', () {
      final tx = LedgerTransaction('tx-1')
        ..record(
          nextEventContext(),
          description: 'Groceries run',
          occurredAt: occurredAt,
          legs: balancedLegs(),
        );

      expect(tx.description, 'Groceries run');
      expect(tx.occurredAt, occurredAt);
      expect(tx.legs, balancedLegs());
      expect(tx.isRecorded, isTrue);
      expect(tx.isVoided, isFalse);
      expect(tx.pendingEvents.single, isA<TransactionRecorded>());
    });

    test('accepts more than two legs, still balanced', () {
      final legs = [
        Leg(accountId: 'rent', amount: Money.parse('600.00', Currency.usd)),
        Leg(accountId: 'alice', amount: Money.parse('-300.00', Currency.usd)),
        Leg(accountId: 'bob', amount: Money.parse('-300.00', Currency.usd)),
      ];
      final tx = LedgerTransaction('tx-1')
        ..record(
          nextEventContext(),
          description: 'Split rent',
          occurredAt: occurredAt,
          legs: legs,
        );
      expect(tx.legs, legs);
    });

    test('rejects legs that do not sum to zero', () {
      final legs = [
        Leg(accountId: 'a', amount: Money.parse('50.00', Currency.usd)),
        Leg(accountId: 'b', amount: Money.parse('-40.00', Currency.usd)),
      ];
      expect(
        () => LedgerTransaction('tx-1').record(
          nextEventContext(),
          description: 'x',
          occurredAt: occurredAt,
          legs: legs,
        ),
        throwsArgumentError,
      );
    });

    test('rejects fewer than two legs', () {
      final legs = [
        Leg(accountId: 'a', amount: Money.parse('50.00', Currency.usd)),
      ];
      expect(
        () => LedgerTransaction('tx-1').record(
          nextEventContext(),
          description: 'x',
          occurredAt: occurredAt,
          legs: legs,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a zero-amount leg', () {
      final legs = [
        Leg(accountId: 'a', amount: Money.parse('0.00', Currency.usd)),
        Leg(accountId: 'b', amount: Money.parse('0.00', Currency.usd)),
      ];
      expect(
        () => LedgerTransaction('tx-1').record(
          nextEventContext(),
          description: 'x',
          occurredAt: occurredAt,
          legs: legs,
        ),
        throwsArgumentError,
      );
    });

    test('rejects mixed currencies even if the raw numbers would balance', () {
      final legs = [
        Leg(accountId: 'a', amount: Money.parse('50.00', Currency.usd)),
        Leg(accountId: 'b', amount: Money.parse('-50.00', Currency.eur)),
      ];
      expect(
        () => LedgerTransaction('tx-1').record(
          nextEventContext(),
          description: 'x',
          occurredAt: occurredAt,
          legs: legs,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a blank description', () {
      expect(
        () => LedgerTransaction('tx-1').record(
          nextEventContext(),
          description: '  ',
          occurredAt: occurredAt,
          legs: balancedLegs(),
        ),
        throwsArgumentError,
      );
    });

    test('rejects recording the same aggregate twice', () {
      final tx = LedgerTransaction('tx-1')
        ..record(
          nextEventContext(),
          description: 'first',
          occurredAt: occurredAt,
          legs: balancedLegs(),
        );
      expect(
        () => tx.record(
          nextEventContext(),
          description: 'second',
          occurredAt: occurredAt,
          legs: balancedLegs(),
        ),
        throwsStateError,
      );
    });

    test('an invalid record() call raises nothing', () {
      final tx = LedgerTransaction('tx-1');
      expect(
        () => tx.record(
          nextEventContext(),
          description: 'x',
          occurredAt: occurredAt,
          legs: const [],
        ),
        throwsArgumentError,
      );
      expect(tx.hasPendingEvents, isFalse);
      expect(tx.isRecorded, isFalse);
    });
  });

  group('voidTransaction', () {
    test('marks the transaction voided and keeps its legs for history', () {
      final tx = LedgerTransaction('tx-1')
        ..record(
          nextEventContext(),
          description: 'Groceries run',
          occurredAt: occurredAt,
          legs: balancedLegs(),
        )
        ..voidTransaction(nextEventContext(), reason: 'duplicate entry');

      expect(tx.isVoided, isTrue);
      expect(tx.legs, balancedLegs()); // the record is preserved, not erased
      expect(tx.pendingEvents.map((e) => e.eventType), [
        'transaction.recorded',
        'transaction.voided',
      ]);
    });

    test('rejects voiding a transaction that was never recorded', () {
      expect(
        () =>
            LedgerTransaction('tx-1')
                .voidTransaction(nextEventContext(), reason: 'x'),
        throwsStateError,
      );
    });

    test('rejects voiding an already-voided transaction', () {
      final tx = LedgerTransaction('tx-1')
        ..record(
          nextEventContext(),
          description: 'x',
          occurredAt: occurredAt,
          legs: balancedLegs(),
        )
        ..voidTransaction(nextEventContext(), reason: 'first void');
      expect(
        () => tx.voidTransaction(nextEventContext(), reason: 'second void'),
        throwsStateError,
      );
    });

    test('rejects a blank reason', () {
      final tx = LedgerTransaction('tx-1')
        ..record(
          nextEventContext(),
          description: 'x',
          occurredAt: occurredAt,
          legs: balancedLegs(),
        );
      expect(
        () => tx.voidTransaction(nextEventContext(), reason: ' '),
        throwsArgumentError,
      );
    });
  });

  test('rehydrates from history to the same state as the original', () {
    final source = LedgerTransaction('tx-1')
      ..record(
        nextEventContext(),
        description: 'Groceries run',
        occurredAt: occurredAt,
        legs: balancedLegs(),
      )
      ..voidTransaction(nextEventContext(), reason: 'oops');
    final history = source.pendingEvents;

    final rebuilt = LedgerTransaction('tx-1')..loadFromHistory(history);

    expect(rebuilt.description, 'Groceries run');
    expect(rebuilt.occurredAt, occurredAt);
    expect(rebuilt.legs, balancedLegs());
    expect(rebuilt.isVoided, isTrue);
    expect(rebuilt.version, 2);
  });
}
