import 'package:go_router/go_router.dart';
import 'package:ledger/features/accounts/presentation/accounts_list_page.dart';
import 'package:ledger/features/accounts/presentation/open_account_page.dart';

final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const AccountsListPage(),
      routes: [
        GoRoute(
          path: 'accounts/open',
          builder: (context, state) => const OpenAccountPage(),
        ),
      ],
    ),
  ],
);
