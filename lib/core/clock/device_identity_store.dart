import 'package:ledger/core/clock/hlc.dart';
import 'package:uuid/uuid.dart';

/// Persists this device's [Hlc] node id across app restarts.
///
/// A node id has to stay the same for the *life of the device install*,
/// not just one app session: `Hlc` ordering (see `hlc.dart`) uses it to
/// break ties between two events with the same wall-clock millisecond and
/// counter, and `SyncService` uses it to tell "this device's events" apart
/// from a remote's when merging. A node id that regenerated on every
/// launch would still work within a single session — every event in it
/// shares the same id — but would silently stop being *this device's*
/// identity the moment sync ever compared two sessions against each other.
abstract interface class DeviceIdentityStore {
  /// Returns this device's node id, generating and persisting a new one
  /// the first time this is ever called. Every call after that — including
  /// from a fresh app launch — returns the same value.
  Future<String> nodeId();
}

/// In-memory [DeviceIdentityStore] for tests: generates once per instance
/// and holds it in memory, the same sense in which `InMemorySyncCursorStore`
/// "persists" — only for the lifetime of one test, not across a real
/// restart. Persistence *across* an app restart is what
/// `DriftDeviceIdentityStore` is for.
class InMemoryDeviceIdentityStore implements DeviceIdentityStore {
  InMemoryDeviceIdentityStore({String Function()? generateId})
    : _generateId = generateId ?? _defaultGenerateId;

  final String Function() _generateId;
  String? _nodeId;

  @override
  Future<String> nodeId() async => _nodeId ??= _generateId();
}

String _defaultGenerateId() => const Uuid().v4();
