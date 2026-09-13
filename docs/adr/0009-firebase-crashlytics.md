# ADR 0009: Firebase Crashlytics for crash reporting, over Sentry

Date: 2026-09-13
Status: Accepted

## Context

Nothing in this app ever reported a crash anywhere — every bug this
project has ever caught was found by a test or by running the app and
watching it fail in front of a terminal (see the README's "A bug only a
real device could have caught" and its equivalents). That's a real gap
for a portfolio app claiming production engineering practices: a crash
on a device Thiago isn't personally holding produces nothing.

Two realistic options exist for a Flutter app: Sentry and Firebase
Crashlytics. Both have a genuinely free tier with no credit card
required. The distinction that mattered here: Sentry's free "Developer"
plan shares a monthly event quota across all of Sentry's products
(errors, performance, etc.) — generous for a portfolio app's real
traffic, but a quota that exists; Crashlytics has **no usage cap at all**
on Google's free Spark plan, because Crashlytics itself carries no paid
tier — it's free regardless of which Firebase plan a project is on.

## Decision

Firebase Crashlytics, specifically for the zero-ambiguity-about-cost
reason above. `flutterfire configure` registered the Android app on a
new Firebase project (`household-ledger-57965`, Spark plan, no billing
account) and generated `lib/firebase_options.dart`. `main.dart` wires
both error sources Crashlytics needs to actually catch everything:
`FlutterError.onError` (errors inside Flutter's own build/layout/paint
pipeline) and `PlatformDispatcher.instance.onError` (everything else —
an uncaught exception in an `async` gap, a stream listener, a timer
callback). Missing either one is a real, documented Crashlytics gap, not
a hypothetical one.

## Consequences

- No stored secret for this feature: `firebase_options.dart` and
  `android/app/google-services.json` contain a Firebase **API key**, not
  a credential — Google's own documentation is explicit that this value
  identifies a client app publicly and is safe to commit; access control
  is enforced by Firebase Security Rules and App Check, not by keeping
  this value secret. Committed accordingly, same as any other Firebase
  Flutter project's generated config.
- **Not yet verified on a real device** — the on-device end-to-end proof
  this project's whole testing philosophy insists on (see the README's
  "A bug only a real device could have caught") hasn't happened yet,
  because no physical device was connected to this machine when this
  checkpoint was built. The build itself was verified (a real signed
  release APK built successfully with the Crashlytics native library and
  `google-services` plugin applied — see the increased APK size), but
  "does a real crash on a real device actually show up in the Firebase
  console" is still an open item, not a claimed-but-unproven one. Do
  that verification the next time a device is available:
  `flutter run --release`, force a crash (e.g. throw inside a button
  handler), confirm it appears in Firebase Console → Crashlytics within
  a few minutes.
- Crashlytics' Gradle plugin automatically uploads the R8/ProGuard
  deobfuscation mapping file for release builds, so a reported stack
  trace stays readable despite minification — no manual step added for
  this, it comes from applying the plugin correctly.

## Alternatives considered

- **Sentry** — a real, viable choice (see Context) with a richer feature
  set (performance monitoring, release health) than Crashlytics offers;
  rejected specifically for having *any* usage cap on its free tier,
  however generous, when an alternative with none exists for the same
  core need.
- **No crash reporting** — the status quo this ADR replaces.
