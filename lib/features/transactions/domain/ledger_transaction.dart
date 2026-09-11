import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/transactions/domain/leg.dart';
import 'package:ledger/features/transactions/domain/transaction_events.dart';

/// A double-entry posting: named `LedgerTransaction`, not `Transaction`, to
/// avoid colliding with Drift's own `transaction()` — the two are easy to
/// mix up in an import list otherwise.
///
/// Enforces exactly the invariants it *can* see from its own event stream:
/// at least two legs, none zero, all the same currency, summing to exactly
/// zero. It does **not** check that the referenced accounts exist or are
/// open — that's a cross-aggregate concern this aggregate has no way to see
/// on its own, so it lives in `RecordTransactionHandler` instead.
class LedgerTransaction extends Aggregate<DomainEvent> {
  LedgerTransaction(super.id);

  String _description = '';
  DateTime? _occurredAt;
  List<Leg> _legs = const [];
  bool _isVoided = false;

  String get description => _description;

  DateTime get occurredAt =>
      _occurredAt ?? (throw StateError('transaction $id was never recorded'));

  List<Leg> get legs => List.unmodifiable(_legs);

  bool get isRecorded => _occurredAt != null;

  bool get isVoided => _isVoided;

  void record(
    EventContext ctx, {
    required String description,
    required DateTime occurredAt,
    required List<Leg> legs,
  }) {
    if (version > 0) {
      throw StateError('transaction $id was already recorded');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError.value(
        description,
        'description',
        'must not be blank',
      );
    }
    if (legs.length < 2) {
      throw ArgumentError.value(legs, 'legs', 'needs at least 2 legs');
    }
    if (legs.any((leg) => leg.amount.isZero)) {
      throw ArgumentError.value(legs, 'legs', 'no leg amount may be zero');
    }

    final currency = legs.first.amount.currency;
    if (legs.any((leg) => leg.amount.currency != currency)) {
      throw ArgumentError.value(
        legs,
        'legs',
        'all legs must be in the same currency ($currency)',
      );
    }

    final total = legs.map((leg) => leg.amount).reduce((a, b) => a + b);
    if (!total.isZero) {
      throw ArgumentError.value(
        legs,
        'legs',
        'legs must sum to zero, got ${total.toDecimalString()} $currency',
      );
    }

    raise(
      TransactionRecorded(
        eventId: ctx.eventId,
        aggregateId: id,
        timestamp: ctx.timestamp,
        description: description,
        occurredAt: occurredAt,
        legs: legs,
      ),
    );
  }

  void voidTransaction(EventContext ctx, {required String reason}) {
    if (!isRecorded) {
      throw StateError('transaction $id was never recorded');
    }
    if (_isVoided) {
      throw StateError('transaction $id is already voided');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'must not be blank');
    }
    raise(
      TransactionVoided(
        eventId: ctx.eventId,
        aggregateId: id,
        timestamp: ctx.timestamp,
        reason: reason,
      ),
    );
  }

  @override
  void applyEvent(DomainEvent event) {
    switch (event) {
      case TransactionRecorded(
        :final description,
        :final occurredAt,
        :final legs,
      ):
        _description = description;
        _occurredAt = occurredAt;
        _legs = legs;
      case TransactionVoided():
        _isVoided = true;
    }
  }
}
