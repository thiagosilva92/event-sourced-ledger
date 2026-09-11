import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ledger/app/providers/command_providers.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/features/accounts/application/open_account_handler.dart';
import 'package:uuid/uuid.dart';

/// A minimal form over `OpenAccountHandler`. The account id is generated
/// here (a UUID v7) — `OpenAccountCommand` takes the id as input rather
/// than the handler assigning one, so the caller decides identity, which
/// matters once this needs to work offline: an id has to exist before any
/// server round-trip could hand one back.
class OpenAccountPage extends ConsumerStatefulWidget {
  const OpenAccountPage({super.key});

  @override
  ConsumerState<OpenAccountPage> createState() => _OpenAccountPageState();
}

class _OpenAccountPageState extends ConsumerState<OpenAccountPage> {
  static const List<Currency> _currencies = [
    Currency.usd,
    Currency.eur,
    Currency.brl,
    Currency.jpy,
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  Currency _currency = Currency.usd;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    final handler = ref.read(openAccountHandlerProvider);
    final result = await handler.handle(
      OpenAccountCommand(
        accountId: const Uuid().v7(),
        name: _nameController.text.trim(),
        currency: _currency,
      ),
    );

    if (!mounted) return;
    result.fold((_) => context.pop(), (failure) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_describe(failure))));
    });
  }

  String _describe(OpenAccountFailure failure) => switch (failure) {
    AccountIdAlreadyUsed() => 'That id is already in use — please try again.',
    InvalidAccountName(:final message) => message,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Open account')),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Currency>(
                initialValue: _currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: [
                  for (final currency in _currencies)
                    DropdownMenuItem(
                      value: currency,
                      child: Text(currency.code),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _currency = value ?? _currency),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Open account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
