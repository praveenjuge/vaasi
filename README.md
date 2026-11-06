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
