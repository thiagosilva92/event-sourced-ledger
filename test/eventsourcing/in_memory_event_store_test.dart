import 'package:ledger/eventsourcing/eventsourcing.dart';

import 'event_store_contract.dart';

void main() {
  runEventStoreContractTests(
    InMemoryEventStore.new,
    disposeStore: (store) => (store as InMemoryEventStore).dispose(),
  );
}
