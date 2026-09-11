import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/result/result.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/domain/account.dart';
import 'package:ledger/features/transactions/domain/ledger_transaction.dart';
import 'package:ledger/features/transactions/domain/leg.dart';
import 'package:meta/meta.dart';

final class RecordTransactionCommand {
  const RecordTransactionCommand({
    required this.transactionId,
    required this.description,
    required this.occurredAt,
    required this.legs,
  });

  final String transactionId;
  final String description;
  final DateTime occurredAt;
  final List<Leg> legs;
}

@immutable
sealed class RecordTransactionFailure {
  const RecordTransactionFailure();
}

final class TransactionIdAlreadyUsed extends RecordTransactionFailure {
  const TransactionIdAlreadyUsed(this.transactionId);
  final String transactionId;

  @override
  bool operator ==(Object other) =>
      other is TransactionIdAlreadyUsed && other.transactionId == transactionId;

  @override
  int get hashCode => transactionId.hashCode;
}

/// A leg names an account that doesn't exist. Named "referenced" (not just
/// `AccountNotFound`) to stay unmistakably distinct from
/// `CloseAccountHandler`'s failure of the same shape — a different command,
/// a different meaning, deliberately not the same type.
final class ReferencedAccountNotFound extends RecordTransactionFailure {
  const ReferencedAccountNotFound(this.accountId);
  final String accountId;

  @override
  bool operator ==(Object other) =>
      other is ReferencedAccountNotFound && other.accountId == accountId;

  @override
  int get hashCode => accountId.hashCode;
}

final class ReferencedAccountClosed extends RecordTransactionFailure {
  const ReferencedAccountClosed(this.accountId);
  final String accountId;

  @override
  bool operator ==(Object other) =>
      other is ReferencedAccountClosed && other.accountId == accountId;

  @override
  int get hashCode => accountId.hashCode;
}

final class InvalidLegs extends RecordTransactionFailure {
  const InvalidLegs(this.message);
  final String message;

  @override
  bool operator ==(Object other) =>
      other is InvalidLegs && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Records a double-entry transaction.
///
/// This is where the cross-aggregate check `LedgerTransaction` itself can't
/// make lives: every account a leg references has to be loaded and checked
/// — it exists, and it's open — *before* the transaction aggregate ever
/// gets a chance to raise `TransactionRecorded`. `LedgerTransaction.record`
/// still separately enforces everything it *can* see on its own (legs
/// balance, one currency, no zero legs) — this handler doesn't duplicate
/// that, it catches what `record` throws for those and translates it into
/// [InvalidLegs].
class RecordTransactionHandler {
  RecordTransactionHandler({
    required EventStore eventStore,
    required HybridLogicalClock clock,
    required EventIdGenerator newEventId,
  }) : _eventStore = eventStore,
       _clock = clock,
       _newEventId = newEventId;

  final EventStore _eventStore;
  final HybridLogicalClock _clock;
  final EventIdGenerator _newEventId;

  Future<Result<String, RecordTransactionFailure>> handle(
    RecordTransactionCommand command,
  ) async {
    final existing = await _eventStore.readAggregate(command.transactionId);
    if (existing.isNotEmpty) {
      return Err(TransactionIdAlreadyUsed(command.transactionId));
    }

    final referencedAccountIds = command.legs
        .map((leg) => leg.accountId)
        .toSet();
    for (final accountId in referencedAccountIds) {
      final history = await _eventStore.readAggregate(accountId);
      if (history.isEmpty) {
        return Err(ReferencedAccountNotFound(accountId));
      }
      final account = Account(accountId)..loadFromHistory(history);
      if (!account.isOpen) {
        return Err(ReferencedAccountClosed(accountId));
      }
    }

    final transaction = LedgerTransaction(command.transactionId);
    try {
      transaction.record(
        EventContext(eventId: _newEventId(), timestamp: _clock.now()),
        description: command.description,
        occurredAt: command.occurredAt,
        legs: command.legs,
      );
    } on ArgumentError catch (error) {
      return Err(InvalidLegs(error.message.toString()));
    }

    await _eventStore.append(command.transactionId, transaction.pendingEvents);
    transaction.markEventsCommitted();
    return Ok(transaction.id);
  }
}
