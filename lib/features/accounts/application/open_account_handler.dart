import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/core/result/result.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/domain/account.dart';
import 'package:meta/meta.dart';

final class OpenAccountCommand {
  const OpenAccountCommand({
    required this.accountId,
    required this.name,
    required this.currency,
  });

  final String accountId;
  final String name;
  final Currency currency;
}

@immutable
sealed class OpenAccountFailure {
  const OpenAccountFailure();
}

final class AccountIdAlreadyUsed extends OpenAccountFailure {
  const AccountIdAlreadyUsed(this.accountId);
  final String accountId;

  @override
  bool operator ==(Object other) =>
      other is AccountIdAlreadyUsed && other.accountId == accountId;

  @override
  int get hashCode => accountId.hashCode;
}

final class InvalidAccountName extends OpenAccountFailure {
  const InvalidAccountName(this.message);
  final String message;

  @override
  bool operator ==(Object other) =>
      other is InvalidAccountName && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Opens a new account.
///
/// The only thing this handler needs infrastructure for is checking the id
/// isn't already used — `Account.open` can't see that from inside its own
/// event stream (an empty stream and a never-created aggregate id look
/// identical to it). Everything else (blank name) is `Account.open`'s own
/// invariant; this handler calls it and translates what it throws into a
/// typed [OpenAccountFailure] — the deliberate boundary `Result`'s doc
/// comment describes: aggregates throw for invariant violations, the
/// application layer is what turns that into a `Result` for callers that
/// need to handle failure without a try/catch of their own.
class OpenAccountHandler {
  OpenAccountHandler({
    required EventStore eventStore,
    required HybridLogicalClock clock,
    required EventIdGenerator newEventId,
  }) : _eventStore = eventStore,
       _clock = clock,
       _newEventId = newEventId;

  final EventStore _eventStore;
  final HybridLogicalClock _clock;
  final EventIdGenerator _newEventId;

  Future<Result<String, OpenAccountFailure>> handle(
    OpenAccountCommand command,
  ) async {
    final existing = await _eventStore.readAggregate(command.accountId);
    if (existing.isNotEmpty) {
      return Err(AccountIdAlreadyUsed(command.accountId));
    }

    final account = Account(command.accountId);
    try {
      account.open(
        EventContext(eventId: _newEventId(), timestamp: _clock.now()),
        name: command.name,
        currency: command.currency,
      );
    } on ArgumentError catch (error) {
      return Err(InvalidAccountName(error.message.toString()));
    }

    await _eventStore.append(command.accountId, account.pendingEvents);
    account.markEventsCommitted();
    return Ok(account.id);
  }
}
