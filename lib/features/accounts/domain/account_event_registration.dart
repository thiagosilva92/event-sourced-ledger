import 'package:ledger/core/money/money.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/domain/account_events.dart';

/// Registers every `account.*` event's deserializer. Every [EventStore]
/// that persists and reconstructs events (a `DriftEventStore`, a worker
/// isolate rebuilding its own registry) needs this called once before it
/// can decode an `Account` event.
extension RegisterAccountEvents on EventRegistry {
  void registerAccountEvents() {
    register(
      'account.opened',
      (meta, payload) => AccountOpened(
        eventId: meta.eventId,
        aggregateId: meta.aggregateId,
        timestamp: meta.timestamp,
        name: payload['name']! as String,
        currency: Currency(
          payload['currencyCode']! as String,
          decimalPlaces: payload['currencyDecimalPlaces']! as int,
        ),
      ),
    );
    register(
      'account.renamed',
      (meta, payload) => AccountRenamed(
        eventId: meta.eventId,
        aggregateId: meta.aggregateId,
        timestamp: meta.timestamp,
        name: payload['name']! as String,
      ),
    );
    register(
      'account.closed',
      (meta, payload) => AccountClosed(
        eventId: meta.eventId,
        aggregateId: meta.aggregateId,
        timestamp: meta.timestamp,
      ),
    );
  }
}
