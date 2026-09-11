import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger/app/providers/infrastructure_providers.dart';
import 'package:ledger/core/money/money.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';
import 'package:ledger/features/accounts/domain/account_directory_projection.dart';
import 'package:ledger/features/reports/domain/account_balance_projection.dart';

/// Base for a Riverpod [Notifier] that keeps one [Projection] live: an
/// initial full [ProjectionRunner.rebuild], then [ProjectionRunner.catchUp]
/// every time [EventStore.changes] emits — so the UI updates the moment a
/// command handler appends a new event, without any screen having to
/// remember to refresh after every action it triggers.
abstract class _LiveProjectionNotifier<S> extends Notifier<S> {
  late final Projection<S> _projection;
  late final ProjectionRunner _runner;
  StreamSubscription<DomainEvent>? _subscription;

  Projection<S> createProjection();

  @override
  S build() {
    _projection = createProjection();
    final store = ref.watch(eventStoreProvider);
    _runner = ProjectionRunner(store, [_projection]);

    _subscription = store.changes.listen((_) => unawaited(_catchUp()));
    ref.onDispose(() => _subscription?.cancel());

    unawaited(_rebuild());
    return _projection.state;
  }

  Future<void> _rebuild() async {
    await _runner.rebuild();
    state = _projection.state;
  }

  Future<void> _catchUp() async {
    await _runner.catchUp();
    state = _projection.state;
  }
}

class AccountBalancesNotifier
    extends _LiveProjectionNotifier<Map<String, Money>> {
  @override
  Projection<Map<String, Money>> createProjection() =>
      AccountBalanceProjection();
}

final accountBalancesProvider =
    NotifierProvider<AccountBalancesNotifier, Map<String, Money>>(
      AccountBalancesNotifier.new,
    );

class AccountDirectoryNotifier
    extends _LiveProjectionNotifier<Map<String, AccountDirectoryEntry>> {
  @override
  Projection<Map<String, AccountDirectoryEntry>> createProjection() =>
      AccountDirectoryProjection();
}

final accountDirectoryProvider =
    NotifierProvider<
      AccountDirectoryNotifier,
      Map<String, AccountDirectoryEntry>
    >(AccountDirectoryNotifier.new);
