# Agent guidance

Vaasi is a macOS app (SwiftUI, XcodeGen). Every build and test runs on macOS,
not in a Linux orb.

## Building and testing

- On a fresh Mac (for example an Amp Mac satellite), run
  `scripts/mac-setup.sh` once to install XcodeGen.
- Run the full verification with `scripts/verify.sh --no-ui` (`--no-ui` skips
  UI tests that take over the pointer). It generates the project, runs the
  VaasiCore package tests, builds, and runs the VaasiTests bundle, then fails
  if any "done" feature in `features.json` lacks a passing test.
- Or build directly: `xcodegen generate`, then
  `xcodebuild -project Vaasi.xcodeproj -scheme Vaasi -destination 'platform=macOS' -derivedDataPath build/DerivedData build`.
- On a machine without the `DEVELOPMENT_TEAM` certificates (team LW385M78LW),
  add `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO` to the xcodebuild
  invocation for ad-hoc signing; hardened runtime is disabled automatically.
- Human-facing visual checks on the real app are listed in
  `verification/AGENT_CHECKS.md`.

## Repo layout

- `project.yml` is the source of truth for `Vaasi.xcodeproj`; edit it, never
  the generated project, and regenerate after edits.
- `Packages/VaasiKit` (`VaasiCore`) is pure Foundation + swift-testing and
  builds standalone with `swift test` inside `Packages/VaasiKit`.
