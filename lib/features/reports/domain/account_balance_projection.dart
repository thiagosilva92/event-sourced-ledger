import 'package:ledger/core/money/money.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/transactions/domain/leg.dart';
import 'package:ledger/features/transactions/domain/transaction_events.dart';

/// Running balance per account, folded from every transaction ever
/// recorded — the read side of the CQRS split the README describes: the
/// write model (`Account`, `LedgerTransaction`) never computes a balance,
/// this is the only place one exists, and it's derived, not stored as
/// truth.
///
/// `TransactionVoided` doesn't carry the legs it's reversing — it shouldn't;
/// that would duplicate data `TransactionRecorded` already has. So this
/// projection keeps its own small index (legs by transaction id) purely to
/// know what to reverse when a void arrives later in the stream. That index
/// is derived state too, rebuilt on [reset] along with the balances
/// themselves — nothing here is a second source of truth.
class AccountBalanceProjection extends Projection<Map<String, Money>> {
  final Map<String, Money> _balances = {};
  final Map<String, List<Leg>> _legsByTransactionId = {};

  @override
  Map<String, Money> get state => Map.unmodifiable(_balances);

  @override
  void handle(DomainEvent event) {
    // DomainEvent isn't sealed (any feature can extend it), so this has to
    // explicitly ignore everything that isn't one of the two event types
    // this projection cares about — account events flow through the same
    // stream and are expected here, not a bug.
    switch (event) {
      case TransactionRecorded(:final legs):
        _legsByTransactionId[event.aggregateId] = legs;
        legs.forEach(_adjust);
      case TransactionVoided():
        final legs = _legsByTransactionId[event.aggregateId];
        // Events for one aggregate always arrive in the order they were
        // raised (EventStore.readAll orders by sequence), so a void can
        // only be missing its legs if it's being folded before its own
        // TransactionRecorded — which never happens in a correctly ordered
        // stream. Ignoring it here rather than throwing keeps a projection
        // rebuild resilient to that instead of crashing the app over it.
        if (legs != null) {
          for (final leg in legs) {
            _adjust(Leg(accountId: leg.accountId, amount: -leg.amount));
          }
        }
      default:
        break;
    }
  }

  void _adjust(Leg leg) {
    final current = _balances[leg.accountId];
    _balances[leg.accountId] = current == null
        ? leg.amount
        : current + leg.amount;
  }

  @override
  void clear() {
    _balances.clear();
    _legsByTransactionId.clear();
  }
}
