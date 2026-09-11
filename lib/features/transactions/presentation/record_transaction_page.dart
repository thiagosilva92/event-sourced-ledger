import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ledger/app/providers/command_providers.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/features/accounts/presentation/account_summary.dart';
import 'package:ledger/features/transactions/application/record_transaction_handler.dart';
import 'package:ledger/features/transactions/domain/leg.dart';
import 'package:uuid/uuid.dart';

/// A form over `RecordTransactionHandler`, shaped as the simplest case a
/// double-entry system supports: money moves from one open account to
/// another. That's exactly two legs — `-amount` on the source, `+amount` on
/// the destination — which is what most of this app's postings will
/// actually be; splitting one amount across more than two legs would need a
/// richer form than this MVP screen and isn't built yet (`Leg`/
/// `LedgerTransaction` already support it — nothing in the domain layer
/// blocks it, only this screen's UI does).
class RecordTransactionPage extends ConsumerStatefulWidget {
  const RecordTransactionPage({super.key});

  @override
  ConsumerState<RecordTransactionPage> createState() =>
      _RecordTransactionPageState();
}

class _RecordTransactionPageState extends ConsumerState<RecordTransactionPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _fromAccountId;
  String? _toAccountId;
  DateTime _occurredAt = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _occurredAt = picked);
    }
  }

  Future<void> _submit(AccountSummary from, AccountSummary to) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final amount = Money.parse(
      _amountController.text.trim(),
      from.balance.currency,
    );
    setState(() => _submitting = true);
    final handler = ref.read(recordTransactionHandlerProvider);
    final result = await handler.handle(
      RecordTransactionCommand(
        transactionId: const Uuid().v7(),
        description: _descriptionController.text.trim(),
        occurredAt: _occurredAt,
        legs: [
          Leg(accountId: from.id, amount: -amount),
          Leg(accountId: to.id, amount: amount),
        ],
      ),
    );

    if (!mounted) return;
    result.fold((_) => context.pop(), (failure) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_describe(failure))));
    });
  }

  String _describe(RecordTransactionFailure failure) => switch (failure) {
    TransactionIdAlreadyUsed() =>
      'That id is already in use — please try again.',
    ReferencedAccountNotFound() => 'One of the accounts no longer exists.',
    ReferencedAccountClosed() => 'One of the accounts is closed.',
    InvalidLegs(:final message) => message,
  };

  @override
  Widget build(BuildContext context) {
    final openAccounts = ref
        .watch(accountSummariesProvider)
        .where((summary) => summary.isOpen)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Record transaction')),
      body: openAccounts.length < 2
          ? const _NotEnoughAccounts()
          : _buildForm(context, openAccounts),
    );
  }

  Widget _buildForm(BuildContext context, List<AccountSummary> openAccounts) {
    final fromAccount = openAccounts
        .where((a) => a.id == _fromAccountId)
        .firstOrNull;
    // The destination must share the source's currency — `LedgerTransaction`
    // requires every leg to be in one currency, so an account that doesn't
    // match can't be a valid destination for this posting. Filtering it out
    // here means the form can't be submitted into a failure the aggregate
    // would just reject anyway.
    final toOptions = fromAccount == null
        ? const <AccountSummary>[]
        : openAccounts
              .where(
                (a) =>
                    a.id != fromAccount.id &&
                    a.balance.currency == fromAccount.balance.currency,
              )
              .toList();
    final toAccount = toOptions.where((a) => a.id == _toAccountId).firstOrNull;

    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _fromAccountId,
              decoration: const InputDecoration(labelText: 'From account'),
              items: [
                for (final account in openAccounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              validator: (value) => value == null ? 'Required' : null,
              onChanged: (value) => setState(() {
                _fromAccountId = value;
                // A destination chosen under the old source may no longer
                // be a valid (different-account, same-currency) option.
                _toAccountId = null;
              }),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _toAccountId,
              decoration: const InputDecoration(labelText: 'To account'),
              items: [
                for (final account in toOptions)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              validator: (value) => value == null ? 'Required' : null,
              onChanged: fromAccount == null
                  ? null
                  : (value) => setState(() => _toAccountId = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: fromAccount?.balance.currency.code,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (value) => _validateAmount(value, fromAccount),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(
                '${_occurredAt.year}-${_occurredAt.month.toString().padLeft(2, '0')}-'
                '${_occurredAt.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed:
                  (_submitting || fromAccount == null || toAccount == null)
                  ? null
                  : () => _submit(fromAccount, toAccount),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Record transaction'),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateAmount(String? value, AccountSummary? fromAccount) {
    if (value == null || value.trim().isEmpty) return 'Required';
    if (fromAccount == null) return 'Choose the from account first';
    try {
      final amount = Money.parse(value.trim(), fromAccount.balance.currency);
      if (amount.isZero) return 'Must not be zero';
    } on FormatException {
      return 'Not a valid amount';
    }
    return null;
  }
}

class _NotEnoughAccounts extends StatelessWidget {
  const _NotEnoughAccounts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_horiz,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Need two open accounts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'A transaction moves money between two open accounts in the '
              'same currency. Open a second one first.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
