# ADR 0004: Riverpod, and the presentation layer only ever reads projections

Date: 2026-09-13
Status: Accepted

## Context

With write and read modeled as separate paths (see
[ADR 0001](0001-event-sourcing-and-cqrs.md)), the presentation layer
needs a state-management approach that can (a) hold and rebuild
projection state derived from the event log, (b) dispatch commands
without reaching back into domain internals, and (c) be tested without
a widget tree, since the domain and application layers already are.

## Decision

Riverpod is the state-management layer. Widgets read projections through
providers and dispatch `Command`s through the application layer; nothing
in `lib/features/*/presentation` constructs an aggregate, appends an
event, or touches `EventStore` directly — that boundary is also what
`test/architecture/layering_test.dart` checks by scanning imports, not
just documenting in prose.

## Consequences

- Providers are plain Dart objects Riverpod manages the lifecycle of,
  so the same command-handler and projection logic already unit-tested
  in `test/application` and `test/eventsourcing` is exercised again,
  unchanged, from provider tests — no separate presentation-layer
  reimplementation of business rules to keep in sync.
- Compile-time provider dependencies catch a wiring mistake (a screen
  reading a projection nothing populates) at build time rather than as
  a runtime null or an empty screen discovered manually.
- The write path has no separate "outbox" concept for the UI to manage:
  a command handler's job ends at "events appended," and `SyncService`
  reads whatever is unsent directly off the log's own cursor (see the
  main README's "Write path" section) — presentation code never
  orchestrates sync itself.

## Alternatives considered

- **Bloc** — an equally viable, more ceremony-heavy choice (explicit
  event/state classes per feature) for a project already using
  domain-level `DomainEvent`s as its central concept; Riverpod's plain
  providers avoid a second, presentation-only notion of "event" existing
  alongside the domain's real one.
- **setState/ChangeNotifier without a DI framework** — would work for a
  screen or two, but does not scale to enforcing "presentation only
  depends on projections" as the feature count grows, and has no
  provider-graph equivalent for the architecture test to check against.
