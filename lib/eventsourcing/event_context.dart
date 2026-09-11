import 'package:ledger/core/clock/hlc.dart';
import 'package:meta/meta.dart';

/// Everything an aggregate's command method needs to stamp a freshly-raised
/// event: a fresh id and the current causal timestamp.
///
/// Passed in by the caller (a command handler) rather than generated inside
/// the aggregate, so the aggregate stays pure — no clock, no id generator,
/// deterministic given its inputs alone. That's what keeps `Aggregate`
/// subclasses trivial to unit test: no fake clock or id generator to wire
/// up, just call the command method and inspect what it raised.
@immutable
final class EventContext {
  const EventContext({required this.eventId, required this.timestamp});

  final String eventId;
  final Hlc timestamp;
}

/// Produces a fresh, globally unique event id (a UUID v7 in production).
/// Typedef'd so command handlers can be constructed with a deterministic
/// generator in tests instead of a real one.
typedef EventIdGenerator = String Function();
