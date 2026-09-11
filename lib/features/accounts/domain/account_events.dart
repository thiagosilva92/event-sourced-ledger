import 'package:ledger/core/money/money.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

/// An account is opened once, with a fixed currency — legs recorded against
/// it later must be in that currency (checked when a transaction is
/// recorded, not here; this event just states the fact).
base class AccountOpened extends DomainEvent {
  const AccountOpened({
    required super.eventId,
    required super.aggregateId,
    required super.timestamp,
    required this.name,
    required this.currency,
  });

  final String name;
  final Currency currency;

  @override
  String get eventType => 'account.opened';

  @override
  Map<String, Object?> toPayload() => {
    'name': name,
    'currencyCode': currency.code,
    'currencyDecimalPlaces': currency.decimalPlaces,
  };
}

base class AccountRenamed extends DomainEvent {
  const AccountRenamed({
    required super.eventId,
    required super.aggregateId,
    required super.timestamp,
    required this.name,
  });

  final String name;

  @override
  String get eventType => 'account.renamed';

  @override
  Map<String, Object?> toPayload() => {'name': name};
}

/// A closed account can't have new transactions recorded against it (see
/// `RecordTransactionHandler`). It stays in history — its past legs still
/// count towards balances and reports — this only blocks *new* activity.
base class AccountClosed extends DomainEvent {
  const AccountClosed({
    required super.eventId,
    required super.aggregateId,
    required super.timestamp,
  });

  @override
  String get eventType => 'account.closed';

  @override
  Map<String, Object?> toPayload() => const {};
}
