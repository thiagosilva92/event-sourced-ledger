# ADR 0006: Enforce layering with a regex-based import scan, not an analyzer plugin dependency

Date: 2026-09-13
Status: Accepted

## Context

The architecture's central claim — `domain/` stays pure Dart, nothing
depends "upward" toward `presentation/`, `data/` doesn't leak into
`application/` — is only worth documenting if something actually checks
it. Without an automated check, the rule degrades over time as features
are added under time pressure, and nothing in CI would notice.

## Decision

`test/architecture/layering_test.dart` checks the real dependency rules
by scanning every `import` statement under `lib/` with regular
expressions and asserting the allowed-direction rules directly, rather
than depending on `package:analyzer` (or a dedicated architecture-testing
package) to parse and walk the import graph.

## Consequences

- Zero extra dependency surface for a check that, in practice, only
  needs to answer "does file X import something under directory Y" —
  `package:analyzer`'s full parsing machinery is more capability than
  this specific question needs.
- The check runs as an ordinary `flutter test`, in the same CI step and
  at the same speed as every other test — no separate tool, config file,
  or CI step to maintain.
- Trade-off: a regex-based scan is more naive than a real import-graph
  analysis (it cannot, for instance, resolve re-exports or conditional
  imports the way a full analyzer would) — acceptable here because the
  rule being enforced is a simple directory-to-directory direction
  check, not a question that needs full semantic resolution.

## Alternatives considered

- **`package:analyzer`-based custom lint rule** — more powerful and more
  correct for edge cases, but a meaningfully heavier dependency and
  implementation for a rule this project only needs to apply to plain,
  non-re-exported imports.
- **No automated check, rely on code review** — rejected: this is
  exactly the kind of rule that erodes silently under time pressure if
  nothing but human attention enforces it.
