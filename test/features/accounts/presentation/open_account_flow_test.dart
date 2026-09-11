import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app/app.dart';

import '../../../support/test_provider_overrides.dart';

void main() {
  testWidgets(
    'opening an account through the UI navigates back and shows it in the list',
    (tester) async {
      await tester.pumpWidget(wrapWithTestProviderScope(const LedgerApp()));
      await tester.pumpAndSettle();
      expect(find.text('No accounts yet'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Open account'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Groceries');
      await tester.tap(find.widgetWithText(FilledButton, 'Open account'));
      await tester.pumpAndSettle();

      // Back on the list, showing the new account.
      expect(find.widgetWithText(AppBar, 'Accounts'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('No accounts yet'), findsNothing);
    },
  );

  testWidgets(
    'submitting a blank name shows a validation error, no navigation',
    (tester) async {
      await tester.pumpWidget(wrapWithTestProviderScope(const LedgerApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Open account'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Open account'), findsOneWidget);
    },
  );
}
