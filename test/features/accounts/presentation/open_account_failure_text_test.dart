import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/features/accounts/application/open_account_handler.dart';
import 'package:ledger/features/accounts/presentation/open_account_page.dart';
import 'package:ledger/l10n/app_localizations.dart';

/// Direct unit tests for [describeOpenAccountFailure] — the pure mapping
/// `OpenAccountPage` uses to turn a failure into on-screen text. Exists
/// specifically to prove `InvalidAccountName` shows a *localized* message,
/// not `Account.open`'s own English, developer-facing `ArgumentError`
/// text — the bug this file was added to catch (and to keep caught).
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final pt = lookupAppLocalizations(const Locale('pt'));

  test('AccountIdAlreadyUsed uses the shared "id already in use" message', () {
    expect(
      describeOpenAccountFailure(en, const AccountIdAlreadyUsed('acc-1')),
      en.idAlreadyInUseMessage,
    );
  });

  group('InvalidAccountName', () {
    test('shows a localized message, in English', () {
      const failure = InvalidAccountName(
        'must not be blank',
      ); // Account.open's own ArgumentError text
      final shown = describeOpenAccountFailure(en, failure);

      expect(shown, en.invalidAccountNameMessage);
      // The exact bug this test exists to catch: the domain's raw message
      // must never reach the screen verbatim.
      expect(shown, isNot(contains('must not be blank')));
    });

    test('shows a localized message, in Portuguese — not the English one', () {
      const failure = InvalidAccountName('must not be blank');
      final shown = describeOpenAccountFailure(pt, failure);

      expect(shown, pt.invalidAccountNameMessage);
      expect(shown, isNot(equals(en.invalidAccountNameMessage)));
    });
  });
}
