import 'package:ledger/core/clock/hlc.dart';
import 'package:ledger/eventsourcing/eventsourcing.dart';

/// A deterministic [EventContext] source for tests, shared across every
/// feature's aggregate tests so each one doesn't reinvent it.
///
/// Real code gets its `EventContext` from a command handler wired to a real
/// `HybridLogicalClock` and a UUID generator (see
/// `features/*/application/`); tests just need unique, increasing
/// eventId/timestamp pairs without a real clock or device id.

int _seq = 0;

/// Resets the counter. Call from `setUp` in every test file that uses
/// [nextEventContext], so ids/timestamps don't leak state across files.
void resetEventContextFixture() => _seq = 0;

EventContext nextEventContext() {
  final n = _seq++;
  return EventContext(
    eventId: 'evt-${n.toString().padLeft(4, '0')}',
    timestamp: Hlc(wallMillis: 1000 + n, counter: 0, nodeId: 'test'),
  );
}
