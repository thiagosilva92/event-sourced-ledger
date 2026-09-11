import 'package:ledger/sync/sync.dart';

import 'sync_cursor_store_contract.dart';

void main() {
  runSyncCursorStoreContractTests(InMemorySyncCursorStore.new);
}
