import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ledger/app/providers/command_providers.dart';
import 'package:ledger/features/accounts/application/close_account_handler.dart';
import 'package:ledger/features/accounts/presentation/account_summary.dart';
import 'package:ledger/l10n/app_localizations.dart';

/// The app's home screen: every account with its live balance, reading
/// straight from `accountSummariesProvider` — this widget has no idea an
/// `EventStore` or a `Projection` exists, only a `List<AccountSummary>`.
class AccountsListPage extends ConsumerWidget {
  const AccountsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(accountSummariesProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accountsPageTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: l10n.recordTransactionTooltip,
            onPressed: () => context.push('/transactions/record'),
          ),
        ],
      ),
      body: summaries.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              itemCount: summaries.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final summary = summaries[index];
                // Long-press alone isn't discoverable to a screen reader
                // user — nothing hints that a row has a hidden gesture. A
                // custom semantic action surfaces "Close account" as an
                // explicit, announced action (TalkBack/VoiceOver's actions
                // rotor) that fires the exact same handler, without
                // changing sighted behavior at all.
                return Semantics(
                  customSemanticsActions: summary.isOpen
                      ? {
                          CustomSemanticsAction(
                            label: l10n.closeAccountSemanticAction,
                          ): () =>
                              _closeAccount(context, ref, l10n, summary),
                        }
                      : const {},
                  child: ListTile(
                    title: Text(summary.name),
                    subtitle: summary.isOpen
                        ? null
                        : Text(l10n.accountClosedLabel),
                    trailing: Text(
                      summary.balance.toString(),
                      semanticsLabel: summary.balance.isNegative
                          ? l10n.negativeBalanceSemanticLabel(
                              (-summary.balance).toString(),
                            )
                          : l10n.balanceSemanticLabel(
                              summary.balance.toString(),
                            ),
                      style: TextStyle(
                        color: summary.balance.isNegative
                            ? Theme.of(context).colorScheme.error
                            : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    enabled: summary.isOpen,
                    onLongPress: summary.isOpen
                        ? () => _closeAccount(context, ref, l10n, summary)
                        : null,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/accounts/open'),
        tooltip: l10n.openAccountTooltip,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _closeAccount(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AccountSummary summary,
  ) async {
    final handler = ref.read(closeAccountHandlerProvider);
    final result = await handler.handle(
      CloseAccountCommand(accountId: summary.id),
    );
    if (!context.mounted) return;

    final message = result.fold(
      (_) => l10n.accountClosedMessage(summary.name),
      (failure) => switch (failure) {
        AccountNotFound() => l10n.accountNotFoundMessage(summary.name),
        AccountAlreadyClosed() => l10n.accountAlreadyClosedMessage(
          summary.name,
        ),
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
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Purely decorative — the text right below says the same
            // thing. Without this, some screen readers still announce an
            // unlabeled icon as "image", noise a sighted user never sees.
            ExcludeSemantics(
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.noAccountsYetTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.noAccountsYetBody,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
