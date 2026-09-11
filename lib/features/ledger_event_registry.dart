import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/domain/account_event_registration.dart';
import 'package:ledger/features/transactions/domain/transaction_event_registration.dart';

/// Every event type the app can decode, in one place.
///
/// Top-level, as `DriftEventStore` requires of the registry factory it's
/// given (see its constructor doc comment): it rebuilds this fresh inside a
/// worker isolate when decoding a large batch, so it has to be callable
/// with no shared state. A new feature that adds events registers them here
/// too, or `DriftEventStore` will throw `UnknownEventTypeError` the first
/// time it tries to read one back.
EventRegistry buildLedgerEventRegistry() => EventRegistry()
  ..registerAccountEvents()
  ..registerTransactionEvents();
