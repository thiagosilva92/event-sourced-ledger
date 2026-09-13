# ADR 0008: Real signed release builds, via `key.properties` locally and secrets in CI

Date: 2026-09-13
Status: Accepted

## Context

Flutter's default project template leaves `android/app/build.gradle.kts`
signing release builds with the **debug key** — fine for
`flutter run --release` during development, but it means "release build"
was never actually proven end-to-end: nothing in this repo had ever
produced an APK signed the way a real release would be.

## Decision

Generate a real upload keystore (`keytool`, RSA 2048, 10,000-day
validity, alias `upload`) and wire `android/app/build.gradle.kts` to sign
release builds with it when `android/key.properties` exists, falling
back to the debug key when it doesn't — so a fresh checkout without a
keystore still builds. `key.properties` and the `.jks` file are
git-ignored (Flutter's own template already ignores both); a committed
`key.properties.example` documents the format. In CI, a `release-build`
job (gated the same way `benchmark` is: push to `main` only) restores
the keystore from a base64-encoded GitHub secret plus three password/
alias secrets, builds `flutter build apk --release`, and — the point of
doing this at all — **verifies the resulting APK's signature with
`apksigner`** before uploading it as a build artifact, rather than
trusting that the build step not erroring means it's actually signed
with the real key.

## Consequences

- A real, downloadable, correctly-signed release APK is produced on
  every merge to `main` — verified by `apksigner verify --print-certs`
  printing the real key's fingerprint, not the debug key's, in the CI
  log itself.
- No signing credential is committed anywhere. Locally it's a git-ignored
  file; in CI it's four repository secrets, decoded only inside the
  running job.
- This project doesn't publish to the Play Store — there's no Play
  Console account, and this ADR doesn't claim there is. What's proven
  here is the *build* side of a release pipeline (a real signing
  identity, a real signed artifact, a real verification step), which is
  the same infrastructure a Play Store submission would need; the
  remaining step (uploading through Play Console) is an account Thiago
  would create himself if this app were ever actually published, the
  same account-creation boundary this whole portfolio project has kept
  throughout (see [[portfolio-github-account]]-style reasoning applied
  to Google Play instead of GitHub).
- iOS signing is out of scope: it requires an Apple Developer Program
  membership (a paid, per-year account), and every physical-device
  verification this project has ever done was on Android hardware — see
  the README's device-testing notes. Nothing about this decision blocks
  adding iOS signing later if that account ever exists.

## Alternatives considered

- **Leave release builds signed with the debug key** — the status quo
  this ADR replaces; means "release build" was an unverified claim.
- **Generate the keystore in CI on first run, store it as an artifact** —
  would avoid a manual local step, but a release signing key is supposed
  to be long-lived and stable (every future release must be signed with
  the *same* key); minting a fresh one automatically is the opposite of
  what a real release process wants.
