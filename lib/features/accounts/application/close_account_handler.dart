import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/result/result.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/domain/account.dart';
import 'package:meta/meta.dart';

final class CloseAccountCommand {
  const CloseAccountCommand({required this.accountId});
  final String accountId;
}

@immutable
sealed class CloseAccountFailure {
  const CloseAccountFailure();
}

final class AccountNotFound extends CloseAccountFailure {
  const AccountNotFound(this.accountId);
  final String accountId;

  @override
  bool operator ==(Object other) =>
      other is AccountNotFound && other.accountId == accountId;

  @override
  int get hashCode => accountId.hashCode;
}

final class AccountAlreadyClosed extends CloseAccountFailure {
  const AccountAlreadyClosed(this.accountId);
  final String accountId;

  @override
  bool operator ==(Object other) =>
      other is AccountAlreadyClosed && other.accountId == accountId;

  @override
  int get hashCode => accountId.hashCode;
}

/// Closes an account. A closed account keeps every past transaction leg
/// (history is never edited) but `RecordTransactionHandler` refuses to
/// record any *new* transaction against it.
class CloseAccountHandler {
  CloseAccountHandler({
    required EventStore eventStore,
    required HybridLogicalClock clock,
    required EventIdGenerator newEventId,
  }) : _eventStore = eventStore,
       _clock = clock,
       _newEventId = newEventId;

  final EventStore _eventStore;
  final HybridLogicalClock _clock;
  final EventIdGenerator _newEventId;

  Future<Result<void, CloseAccountFailure>> handle(
    CloseAccountCommand command,
  ) async {
    final history = await _eventStore.readAggregate(command.accountId);
    if (history.isEmpty) {
      return Err(AccountNotFound(command.accountId));
    }

    final account = Account(command.accountId)..loadFromHistory(history);
    if (!account.isOpen) {
      return Err(AccountAlreadyClosed(command.accountId));
    }

    account.close(
      EventContext(eventId: _newEventId(), timestamp: _clock.now()),
    );
    await _eventStore.append(command.accountId, account.pendingEvents);
    account.markEventsCommitted();
    return const Ok(null);
  }
}
