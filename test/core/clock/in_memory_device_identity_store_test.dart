import 'package:ledger/core/clock/device_identity_store.dart';

import 'device_identity_store_contract.dart';

void main() {
  runDeviceIdentityStoreContractTests(InMemoryDeviceIdentityStore.new);
}
