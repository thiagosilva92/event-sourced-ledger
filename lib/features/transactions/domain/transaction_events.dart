import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/transactions/domain/leg.dart';

/// A completed double-entry posting. `legs` already sum to zero — that's
/// enforced by `LedgerTransaction.record` before this is ever raised, not
/// re-checked on replay (replay has to accept history as fact).
base class TransactionRecorded extends DomainEvent {
  const TransactionRecorded({
    required super.eventId,
    required super.aggregateId,
    required super.timestamp,
    required this.description,
    required this.occurredAt,
    required this.legs,
  });

  final String description;

  /// When the transaction happened in the real world — distinct from
  /// [DomainEvent.timestamp] (the HLC, which orders *when the event was
  /// recorded* across devices). A transaction entered late for a purchase
  /// made yesterday has an `occurredAt` of yesterday either way.
  final DateTime occurredAt;
  final List<Leg> legs;

  @override
  String get eventType => 'transaction.recorded';

  @override
  Map<String, Object?> toPayload() => {
    'description': description,
    'occurredAt': occurredAt.toIso8601String(),
    'legs': legs.map((leg) => leg.toJson()).toList(),
  };
}

/// A compensating event: the transaction's effect is reversed without
/// editing or deleting the original record, per this app's "no destructive
/// updates" rule (see the README). [reason] exists for both the human
/// audit trail and the eventual multi-device conflict story (an account
/// closed on one device, transacted against on another) once there's a
/// domain that can produce that conflict automatically rather than only
/// manually.
base class TransactionVoided extends DomainEvent {
  const TransactionVoided({
    required super.eventId,
    required super.aggregateId,
    required super.timestamp,
    required this.reason,
  });

  final String reason;

  @override
  String get eventType => 'transaction.voided';

  @override
  Map<String, Object?> toPayload() => {'reason': reason};
}
