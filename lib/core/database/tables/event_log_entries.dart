import 'package:drift/drift.dart';

/// The append-only event log, persisted.
///
/// Rows are never updated or deleted by application code — only inserted.
/// `sequence` is the local, single-device write order (used to (re)build
/// projections); `eventId` is the globally unique id used to de-duplicate
/// events arriving from other devices during sync; the three `hlc*` columns
/// are the causal timestamp used to order and cursor over the log across
/// devices. See `Hlc` and `EventStore.readSince` for why the HLC columns
/// exist separately from `sequence`.
@DataClassName('EventLogRow')
@TableIndex(name: 'event_log_aggregate_id', columns: {#aggregateId})
@TableIndex(
  name: 'event_log_hlc',
  columns: {#hlcWallMillis, #hlcCounter, #hlcNodeId},
)
class EventLogEntries extends Table {
  /// Local append order. Not meaningful across devices — never sent over
  /// the wire, never used to order events for sync.
  IntColumn get sequence => integer().autoIncrement()();

  /// Globally unique (UUID v7 in practice). Enforced unique at the database
  /// level as a second line of defense behind the application-level check in
  /// `EventStore.merge`.
  TextColumn get eventId => text().unique()();

  /// The aggregate this event belongs to.
  TextColumn get aggregateId => text()();

  /// Stable discriminator used to look up the right deserializer in
  /// `EventRegistry`. See `DomainEvent.eventType`.
  TextColumn get eventType => text()();

  /// Hybrid Logical Clock, split into columns so `readSince` can filter and
  /// order on it in SQL without decoding every row first.
  IntColumn get hlcWallMillis => integer()();
  IntColumn get hlcCounter => integer()();
  TextColumn get hlcNodeId => text()();

  /// The event-specific fields (`DomainEvent.toPayload()`), as JSON.
  TextColumn get payloadJson => text()();

  /// Wall-clock time this row was written to *this* device's database.
  /// Diagnostic only — never used for ordering or sync; that's what the
  /// `hlc*` columns are for.
  DateTimeColumn get recordedAt => dateTime().withDefault(currentDateAndTime)();
}
