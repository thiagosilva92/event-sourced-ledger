import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/transactions/domain/leg.dart';
import 'package:ledger/features/transactions/domain/transaction_events.dart';

/// Registers every `transaction.*` event's deserializer — the counterpart
/// to `RegisterAccountEvents`. See its doc comment for why this needs to
/// be called at all.
extension RegisterTransactionEvents on EventRegistry {
  void registerTransactionEvents() {
    register(
      'transaction.recorded',
      (meta, payload) => TransactionRecorded(
        eventId: meta.eventId,
        aggregateId: meta.aggregateId,
        timestamp: meta.timestamp,
        description: payload['description']! as String,
        occurredAt: DateTime.parse(payload['occurredAt']! as String),
        legs: (payload['legs']! as List)
            .map((leg) => Leg.fromJson((leg as Map).cast<String, Object?>()))
            .toList(),
      ),
    );
    register(
      'transaction.voided',
      (meta, payload) => TransactionVoided(
        eventId: meta.eventId,
        aggregateId: meta.aggregateId,
        timestamp: meta.timestamp,
        reason: payload['reason']! as String,
      ),
    );
  }
}
