import 'package:go_router/go_router.dart';
import 'package:ledger/features/accounts/presentation/accounts_list_page.dart';
import 'package:ledger/features/accounts/presentation/open_account_page.dart';
import 'package:ledger/features/transactions/presentation/record_transaction_page.dart';

/// Builds a fresh router. A function, not a top-level singleton `GoRouter` —
/// a `GoRouter` carries its own navigation stack as internal state, so a
/// module-level singleton would leak that stack across every screen that
/// (re)builds it, and, worse, across every widget test that pumps
/// `LedgerApp` in the same test process: whichever route the previous test
/// last navigated to is where the next one would start. `LedgerApp` calls
/// this once per app instance (see `app.dart`) and keeps the result for its
/// whole lifetime.
GoRouter buildAppRouter() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const AccountsListPage(),
      routes: [
        GoRoute(
          path: 'accounts/open',
          builder: (context, state) => const OpenAccountPage(),
        ),
        GoRoute(
          path: 'transactions/record',
          builder: (context, state) => const RecordTransactionPage(),
        ),
      ],
    ),
  ],
);
