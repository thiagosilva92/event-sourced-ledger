import 'package:ledger/core/money/money.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/domain/account_events.dart';

/// A named place money moves in and out of (e.g. "Groceries", "Shared
/// wallet"). Does **not** hold a balance — that's a fold over
/// `TransactionRecorded`/`TransactionVoided` events across every account,
/// not this aggregate's own event stream. See
/// `features/reports/domain/account_balance_projection.dart`.
///
/// Intra-aggregate invariants only (name not blank, can't reopen a used
/// account, can't act on a closed one). Whether an account referenced by a
/// transaction actually exists and is open is a *cross*-aggregate check —
/// `Account` can't see other aggregates, so that lives in
/// `RecordTransactionHandler` instead.
class Account extends Aggregate<DomainEvent> {
  Account(super.id);

  String _name = '';
  Currency? _currency;
  bool _isOpen = false;

  String get name => _name;

  Currency get currency =>
      _currency ?? (throw StateError('account $id was never opened'));

  bool get isOpen => _isOpen;

  void open(
    EventContext ctx, {
    required String name,
    required Currency currency,
  }) {
    if (version > 0) {
      throw StateError('account $id was already opened');
    }
    _requireNonBlank(name);
    raise(
      AccountOpened(
        eventId: ctx.eventId,
        aggregateId: id,
        timestamp: ctx.timestamp,
        name: name,
        currency: currency,
      ),
    );
  }

  void rename(EventContext ctx, String name) {
    _requireOpen();
    _requireNonBlank(name);
    raise(
      AccountRenamed(
        eventId: ctx.eventId,
        aggregateId: id,
        timestamp: ctx.timestamp,
        name: name,
      ),
    );
  }

  void close(EventContext ctx) {
    _requireOpen();
    raise(
      AccountClosed(
        eventId: ctx.eventId,
        aggregateId: id,
        timestamp: ctx.timestamp,
      ),
    );
  }

  void _requireOpen() {
    if (!_isOpen) {
      throw StateError('account $id is not open');
    }
  }

  void _requireNonBlank(String name) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be blank');
    }
  }

  @override
  void applyEvent(DomainEvent event) {
    switch (event) {
      case AccountOpened(:final name, :final currency):
        _name = name;
        _currency = currency;
        _isOpen = true;
      case AccountRenamed(:final name):
        _name = name;
      case AccountClosed():
        _isOpen = false;
    }
  }
}
