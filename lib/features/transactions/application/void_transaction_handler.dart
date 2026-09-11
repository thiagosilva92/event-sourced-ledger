import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/result/result.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/transactions/domain/ledger_transaction.dart';
import 'package:meta/meta.dart';

final class VoidTransactionCommand {
  const VoidTransactionCommand({
    required this.transactionId,
    required this.reason,
  });

  final String transactionId;
  final String reason;
}

@immutable
sealed class VoidTransactionFailure {
  const VoidTransactionFailure();
}

final class TransactionNotFound extends VoidTransactionFailure {
  const TransactionNotFound(this.transactionId);
  final String transactionId;

  @override
  bool operator ==(Object other) =>
      other is TransactionNotFound && other.transactionId == transactionId;

  @override
  int get hashCode => transactionId.hashCode;
}

final class TransactionAlreadyVoided extends VoidTransactionFailure {
  const TransactionAlreadyVoided(this.transactionId);
  final String transactionId;

  @override
  bool operator ==(Object other) =>
      other is TransactionAlreadyVoided && other.transactionId == transactionId;

  @override
  int get hashCode => transactionId.hashCode;
}

final class InvalidVoidReason extends VoidTransactionFailure {
  const InvalidVoidReason(this.message);
  final String message;

  @override
  bool operator ==(Object other) =>
      other is InvalidVoidReason && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Voids a transaction — a compensating `TransactionVoided` event, not a
/// deletion or an edit. No cross-aggregate check needed here (unlike
/// `RecordTransactionHandler`): voiding doesn't touch account state at all,
/// only whether *this* transaction was already recorded and not already
/// voided, both of which `LedgerTransaction` can see on its own.
class VoidTransactionHandler {
  VoidTransactionHandler({
    required EventStore eventStore,
    required HybridLogicalClock clock,
    required EventIdGenerator newEventId,
  }) : _eventStore = eventStore,
       _clock = clock,
       _newEventId = newEventId;

  final EventStore _eventStore;
  final HybridLogicalClock _clock;
  final EventIdGenerator _newEventId;

  Future<Result<void, VoidTransactionFailure>> handle(
    VoidTransactionCommand command,
  ) async {
    final history = await _eventStore.readAggregate(command.transactionId);
    if (history.isEmpty) {
      return Err(TransactionNotFound(command.transactionId));
    }

    final transaction = LedgerTransaction(command.transactionId)
      ..loadFromHistory(history);
    if (transaction.isVoided) {
      return Err(TransactionAlreadyVoided(command.transactionId));
    }

    try {
      transaction.voidTransaction(
        EventContext(eventId: _newEventId(), timestamp: _clock.now()),
        reason: command.reason,
      );
    } on ArgumentError catch (error) {
      return Err(InvalidVoidReason(error.message.toString()));
    }

    await _eventStore.append(command.transactionId, transaction.pendingEvents);
    transaction.markEventsCommitted();
    return const Ok(null);
  }
}
