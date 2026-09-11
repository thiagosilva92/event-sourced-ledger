import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app/app.dart';

import 'support/test_provider_overrides.dart';

void main() {
  testWidgets('app boots and shows the accounts list, empty on first run', (
    tester,
  ) async {
    await tester.pumpWidget(wrapWithTestProviderScope(const LedgerApp()));
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsOneWidget); // the AppBar title
    expect(find.text('No accounts yet'), findsOneWidget);
  });
}
