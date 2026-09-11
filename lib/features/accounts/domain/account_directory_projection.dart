import 'package:ledger/core/money/money.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/domain/account_events.dart';
import 'package:meta/meta.dart';

/// A read-only snapshot of one account's identity — everything the UI
/// needs to show an account *except* its balance, which is
/// `AccountBalanceProjection`'s job. Kept separate because the two are
/// genuinely different concerns (identity vs. a fold over transactions),
/// not because one is more expensive than the other.
@immutable
final class AccountDirectoryEntry {
  const AccountDirectoryEntry({
    required this.id,
    required this.name,
    required this.currency,
    required this.isOpen,
  });

  final String id;
  final String name;
  final Currency currency;
  final bool isOpen;

  @override
  bool operator ==(Object other) =>
      other is AccountDirectoryEntry &&
      other.id == id &&
      other.name == name &&
      other.currency == currency &&
      other.isOpen == isOpen;

  @override
  int get hashCode => Object.hash(id, name, currency, isOpen);
}

/// Every account's current name/currency/open-state, folded from
/// `account.*` events.
class AccountDirectoryProjection
    extends Projection<Map<String, AccountDirectoryEntry>> {
  final Map<String, AccountDirectoryEntry> _accounts = {};

  @override
  Map<String, AccountDirectoryEntry> get state => Map.unmodifiable(_accounts);

  @override
  void handle(DomainEvent event) {
    switch (event) {
      case AccountOpened(:final name, :final currency):
        _accounts[event.aggregateId] = AccountDirectoryEntry(
          id: event.aggregateId,
          name: name,
          currency: currency,
          isOpen: true,
        );
      case AccountRenamed(:final name):
        _update(event.aggregateId, (entry) => _copyWith(entry, name: name));
      case AccountClosed():
        _update(event.aggregateId, (entry) => _copyWith(entry, isOpen: false));
      default:
        break;
    }
  }

  void _update(
    String accountId,
    AccountDirectoryEntry Function(AccountDirectoryEntry) transform,
  ) {
    final existing = _accounts[accountId];
    if (existing != null) {
      _accounts[accountId] = transform(existing);
    }
  }

  AccountDirectoryEntry _copyWith(
    AccountDirectoryEntry entry, {
    String? name,
    bool? isOpen,
  }) => AccountDirectoryEntry(
    id: entry.id,
    name: name ?? entry.name,
    currency: entry.currency,
    isOpen: isOpen ?? entry.isOpen,
  );

  @override
  void clear() => _accounts.clear();
}
