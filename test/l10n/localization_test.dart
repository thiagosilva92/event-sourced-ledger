import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app/providers/infrastructure_providers.dart';
import 'package:ledger/core/database/app_database.dart';
import 'package:ledger/features/accounts/presentation/accounts_list_page.dart';
import 'package:ledger/features/accounts/presentation/open_account_page.dart';
import 'package:ledger/l10n/app_localizations.dart';

/// Proves locale switching actually renders different text, not just that
/// `AppLocalizations` compiles and the English default still reads
/// correctly (every other widget test already covers that). Forcing
/// `locale: Locale('pt')` and asserting the Portuguese string appears is
/// the only way to know the second `.arb` file is wired up at all — a
/// missing or mistyped key would otherwise fail silently by falling back
/// to English, which no English-only test could ever catch.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(
          AppDatabase.forTesting(NativeDatabase.memory()),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the accounts list empty state renders in Portuguese', (
    tester,
  ) async {
    await pump(tester, const AccountsListPage());

    expect(find.text('Contas'), findsOneWidget); // AppBar title
    expect(find.text('Nenhuma conta ainda'), findsOneWidget);
    expect(
      find.text('Toque em + para abrir sua primeira conta.'),
      findsOneWidget,
    );
    // The English strings must NOT be present — proves this isn't just
    // falling back to the default locale.
    expect(find.text('Accounts'), findsNothing);
    expect(find.text('No accounts yet'), findsNothing);
  });

  testWidgets('the open account form renders in Portuguese', (tester) async {
    await pump(tester, const OpenAccountPage());

    expect(find.widgetWithText(AppBar, 'Abrir conta'), findsOneWidget);
    expect(find.text('Nome'), findsOneWidget);
    expect(find.text('Moeda'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Abrir conta'), findsOneWidget);

    // Triggers the "Required" validator — proves a *dynamically shown*
    // string is also localized, not just static labels present at
    // first build.
    await tester.tap(find.widgetWithText(FilledButton, 'Abrir conta'));
    await tester.pumpAndSettle();
    expect(find.text('Obrigatório'), findsOneWidget);
  });
}
