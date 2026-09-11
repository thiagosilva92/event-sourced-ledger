import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ledger/app/providers/command_providers.dart';
import 'package:ledger/features/accounts/application/close_account_handler.dart';
import 'package:ledger/features/accounts/presentation/account_summary.dart';

/// The app's home screen: every account with its live balance, reading
/// straight from `accountSummariesProvider` — this widget has no idea an
/// `EventStore` or a `Projection` exists, only a `List<AccountSummary>`.
class AccountsListPage extends ConsumerWidget {
  const AccountsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(accountSummariesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: summaries.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              itemCount: summaries.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final summary = summaries[index];
                return ListTile(
                  title: Text(summary.name),
                  subtitle: summary.isOpen ? null : const Text('Closed'),
                  trailing: Text(
                    summary.balance.toString(),
                    style: TextStyle(
                      color: summary.balance.isNegative
                          ? Theme.of(context).colorScheme.error
                          : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  enabled: summary.isOpen,
                  onLongPress: summary.isOpen
                      ? () => _closeAccount(context, ref, summary)
                      : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/accounts/open'),
        tooltip: 'Open account',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _closeAccount(
    BuildContext context,
    WidgetRef ref,
    AccountSummary summary,
  ) async {
    final handler = ref.read(closeAccountHandlerProvider);
    final result = await handler.handle(
      CloseAccountCommand(accountId: summary.id),
    );
    if (!context.mounted) return;

    final message = result.fold(
      (_) => 'Closed ${summary.name}.',
      (failure) => switch (failure) {
        AccountNotFound() => '${summary.name} no longer exists.',
        AccountAlreadyClosed() => '${summary.name} is already closed.',
      },
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No accounts yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Tap + to open your first account.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
