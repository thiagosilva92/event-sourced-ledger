import 'package:ledger/eventsourcing/domain_event.dart';
import 'package:ledger/eventsourcing/event_codec.dart';
import 'package:ledger/eventsourcing/event_store.dart';
import 'package:ledger/sync/sync_transport.dart';

/// An in-process stand-in for the real sync server, for local development
/// and tests without a backend.
///
/// [remoteStore] plays the role of the server's own event log — construct
/// several [FakeSyncTransport]s over the *same* [remoteStore] to simulate
/// several devices syncing through one server. Every event still travels
/// through [EventCodec] to and from JSON, so a test that forgets to
/// register an event type fails the same way it would against a real
/// server, instead of silently working because everything stayed in
/// memory as Dart objects.
class FakeSyncTransport implements SyncTransport {
  /// [registryFactory] builds a fresh [EventRegistry] with every event type
  /// this transport needs to decode registered on it. It must be a
  /// **top-level or static function** (not a method tear-off or a closure
  /// capturing anything) — [pull] sends it, unevaluated, to a worker
  /// isolate for large incoming batches, so it has to be safe to run there
  /// with no shared state. Same requirement, same reason, as
  /// `DriftEventStore`'s constructor.
  FakeSyncTransport(
    this.remoteStore,
    EventRegistry Function() registryFactory, {
    this.latency = Duration.zero,
    this.failNextCalls = 0,
  }) : _registryFactory = registryFactory,
       _codec = EventCodec(registryFactory());

  final EventStore remoteStore;
  final EventRegistry Function() _registryFactory;
  final EventCodec _codec;

  /// Artificial delay applied to every call, to exercise UI/async handling
  /// under realistic latency.
  Duration latency;

  /// Number of upcoming calls (push or pull) that should throw
  /// [SyncTransportException] before succeeding again. Sets itself back
  /// towards 0 as calls are made — use it to test retry behaviour.
  int failNextCalls;

  @override
  Future<void> push(List<DomainEvent> events) async {
    await _simulateNetwork();
    if (events.isEmpty) return;
    final onWire = events.map(_codec.encodeToJson).toList();
    final decoded = onWire.map(_codec.decodeFromJson).toList();
    await remoteStore.merge(decoded);
  }

  @override
  Future<PulledBatch> pull({
    required int afterSequence,
    int limit = 200,
  }) async {
    await _simulateNetwork();
    final page = await remoteStore.readAll(afterSequence: afterSequence);
    final limited = page.take(limit).toList();
    if (limited.isEmpty) return PulledBatch(const [], afterSequence);

    // `onWire` is what a real transport would actually receive over HTTP —
    // decoding it is the "incoming batch" that has to not block the
    // calling isolate once a caller asks for a large `limit`. Offloaded via
    // EventCodec.decodeManyFromJson, the same isolate-threshold pattern
    // DriftEventStore.readAll uses for the equivalent database-read path.
    final onWire = limited.map((s) => _codec.encodeToJson(s.event)).toList();
    final decoded = await EventCodec.decodeManyFromJson(
      onWire,
      _registryFactory,
    );
    return PulledBatch(decoded, limited.last.sequence);
  }

  Future<void> _simulateNetwork() async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    if (failNextCalls > 0) {
      failNextCalls--;
      throw SyncTransportException('simulated transient failure');
    }
  }
}
