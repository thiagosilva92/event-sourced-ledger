import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/app/app.dart';

void main() {
  testWidgets('app boots and renders its title', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LedgerApp()));
    expect(find.text('Household Ledger'), findsOneWidget);
  });
}
