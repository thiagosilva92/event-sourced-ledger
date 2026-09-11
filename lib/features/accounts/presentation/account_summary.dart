import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger/app/providers/projection_providers.dart';
import 'package:ledger/core/money/money.dart';
import 'package:meta/meta.dart';

/// What the accounts list screen actually needs to render one row —
/// identity (`AccountDirectoryProjection`) merged with balance
/// (`AccountBalanceProjection`). Shaping two read models into one view
/// model is presentation's job; neither projection needs to know the other
/// exists.
@immutable
final class AccountSummary {
  const AccountSummary({
    required this.id,
    required this.name,
    required this.isOpen,
    required this.balance,
  });

  final String id;
  final String name;
  final bool isOpen;
  final Money balance;
}

/// Every account, balance attached, sorted by name. Recomputes whenever
/// either underlying projection changes — both are already live (see
/// `_LiveProjectionNotifier`), so this needs no refresh logic of its own.
final accountSummariesProvider = Provider<List<AccountSummary>>((ref) {
  final directory = ref.watch(accountDirectoryProvider);
  final balances = ref.watch(accountBalancesProvider);

  final summaries = directory.values.map((entry) {
    return AccountSummary(
      id: entry.id,
      name: entry.name,
      isOpen: entry.isOpen,
      balance: balances[entry.id] ?? Money.zero(entry.currency),
    );
  }).toList();

  summaries.sort((a, b) => a.name.compareTo(b.name));
  return summaries;
});
