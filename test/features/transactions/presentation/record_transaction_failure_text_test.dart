import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/features/transactions/application/record_transaction_handler.dart';
import 'package:ledger/features/transactions/presentation/record_transaction_page.dart';
import 'package:ledger/l10n/app_localizations.dart';

/// Direct unit tests for [describeRecordTransactionFailure] — the pure
/// mapping `RecordTransactionPage` uses to turn a failure into on-screen
/// text. Exists specifically to prove `InvalidLegs` shows a *localized*
/// message, not `LedgerTransaction.record`'s own English, developer-facing
/// `ArgumentError` text — the bug this file was added to catch (and to
/// keep caught).
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final pt = lookupAppLocalizations(const Locale('pt'));

  test('ReferencedAccountNotFound/Closed use their own dedicated messages', () {
    expect(
      describeRecordTransactionFailure(
        en,
        const ReferencedAccountNotFound('acc-1'),
      ),
      en.oneAccountNoLongerExistsMessage,
    );
    expect(
      describeRecordTransactionFailure(
        en,
        const ReferencedAccountClosed('acc-1'),
      ),
      en.oneAccountClosedMessage,
    );
  });

  group('InvalidLegs', () {
    // A real ArgumentError message LedgerTransaction.record actually
    // throws — see its own source for the full list.
    const domainMessage = 'legs must sum to zero, got 10.00 USD';

    test('shows a localized message, in English', () {
      final shown = describeRecordTransactionFailure(
        en,
        const InvalidLegs(domainMessage),
      );

      expect(shown, en.invalidTransactionMessage);
      // The exact bug this test exists to catch: the domain's raw message
      // must never reach the screen verbatim.
      expect(shown, isNot(contains('sum to zero')));
    });

    test('shows a localized message, in Portuguese — not the English one', () {
      final shown = describeRecordTransactionFailure(
        pt,
        const InvalidLegs(domainMessage),
      );

      expect(shown, pt.invalidTransactionMessage);
      expect(shown, isNot(equals(en.invalidTransactionMessage)));
    });
  });
}
