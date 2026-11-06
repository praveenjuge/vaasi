# Vaasi

A teleprompter for Mac that sits in the notch, right under your camera, so you
can read your script and still look at the person you're talking to.

- **Notch or floating.** The prompter grows out of the camera notch, or floats
  anywhere as a resizable window. It shows on every Space and over full-screen apps.
- **Follows your voice.** Scrolls while you speak and waits when you stop.
  On-device speech recognition keeps the text at the line you're reading.
- **Only you see it.** The prompter and library are excluded from screen
  sharing and screenshots. Scripts and audio never leave your Mac.
- **Cues.** Split a script with `---` dividers (`--- Name` names the section)
  and jump between sections while presenting.
- **Control.** Hover to pause, stepped speed, countdown, end marker, and
  shortcuts that work from any app while presenting.
- **Editor.** Notes library with ⌘F search, import (Markdown, text, RTF, Word,
  HTML, PDF) by dropping files, and export.

Requires macOS 26.

## Layout

| Path | What |
|---|---|
| `Vaasi/` | The app (SwiftUI + AppKit). macOS today; iOS will be another destination of the same target. |
| `Packages/VaasiKit` | `VaasiCore`: platform-neutral logic: cues, scroll engine, voice detection, script follower. |
| `VaasiTests/` | Hosted tests: import/export, real on-device speech recognition. |
| `VaasiUITests/` | XCUITests that drive the real app. |
| `features.json` | Every feature and the tests that prove it. |
| `scripts/verify.sh` | Runs everything and reports per feature. |

## Develop

```bash
xcodegen generate
open Vaasi.xcodeproj
```

## Verify

```bash
scripts/verify.sh            # all layers + feature report
scripts/verify.sh --no-ui    # skip UI tests (they take over the pointer)
scripts/verify.sh --only prompter.cues,voice.activity
```

The report lands in `verification/LATEST.md`. A feature passes only when every
test listed for it in `features.json` ran and passed, plus any agent checks in
`verification/agent-checks.json` (see `verification/AGENT_CHECKS.md`).

To add a feature: implement it, add tests, and add an entry to `features.json`
pointing at them.

## Releases

Every push to `main` that changes more than docs runs
`.github/workflows/release.yml`. It takes the latest `v*` tag and bumps the patch
(the first release is `v0.1.0`), runs the core and app tests, then runs
`scripts/release.sh`:

1. Archives a universal Release build signed with Developer ID.
2. Checks version, architectures, hardened runtime and entitlements (sandboxed,
   no network access: Sparkle downloads through its own service).
3. Notarizes and staples the app, a DMG and a signed PKG.
4. Signs a Sparkle `appcast.xml` so installed copies update themselves.

CI then installs the PKG, checks Gatekeeper, launches the app, and publishes
the GitHub Release with DMG, ZIP, PKG and appcast.

Repository secrets:

| Secret | What |
|---|---|
| `DEVELOPER_ID_APPLICATION_P12`, `DEVELOPER_ID_INSTALLER_P12` | Base64 `.p12` exports of the two Developer ID identities |
| `DEVELOPER_ID_P12_PASSWORD` | Their export password |
| `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID` | App Store Connect API key used by `notarytool` |
| `SPARKLE_PRIVATE_KEY` | Update signing key; the public half is `SUPublicEDKey` in `Info.plist` |

The Sparkle key also lives in the login keychain under the account `vaasi`. To
restore it in CI:

```bash
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account vaasi -x key.txt
gh secret set SPARKLE_PRIVATE_KEY < key.txt && trash key.txt
```

Build a release locally (needs the identities in your keychain):

```bash
ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_<id>.p8 ASC_KEY_ID=<id> ASC_ISSUER_ID=<issuer> \
  scripts/release.sh 0.1.0
```
