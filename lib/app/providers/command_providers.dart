import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger/app/providers/infrastructure_providers.dart';
import 'package:ledger/features/accounts/application/close_account_handler.dart';
import 'package:ledger/features/accounts/application/open_account_handler.dart';
import 'package:ledger/features/transactions/application/record_transaction_handler.dart';
import 'package:ledger/features/transactions/application/void_transaction_handler.dart';

/// One provider per command handler — each wired to the same event store,
/// clock and id generator, so every command in one app session shares one
/// causally-ordered timeline.
final openAccountHandlerProvider = Provider<OpenAccountHandler>((ref) {
  return OpenAccountHandler(
    eventStore: ref.watch(eventStoreProvider),
    clock: ref.watch(hybridLogicalClockProvider),
    newEventId: ref.watch(eventIdGeneratorProvider),
  );
});

final closeAccountHandlerProvider = Provider<CloseAccountHandler>((ref) {
  return CloseAccountHandler(
    eventStore: ref.watch(eventStoreProvider),
    clock: ref.watch(hybridLogicalClockProvider),
    newEventId: ref.watch(eventIdGeneratorProvider),
  );
});

final recordTransactionHandlerProvider = Provider<RecordTransactionHandler>((
  ref,
) {
  return RecordTransactionHandler(
    eventStore: ref.watch(eventStoreProvider),
    clock: ref.watch(hybridLogicalClockProvider),
    newEventId: ref.watch(eventIdGeneratorProvider),
  );
});

final voidTransactionHandlerProvider = Provider<VoidTransactionHandler>((ref) {
  return VoidTransactionHandler(
    eventStore: ref.watch(eventStoreProvider),
    clock: ref.watch(hybridLogicalClockProvider),
    newEventId: ref.watch(eventIdGeneratorProvider),
  );
});
