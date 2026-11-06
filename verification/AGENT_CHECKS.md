# Agent checks

Some things are best verified by using the real app: how it looks, real
microphones, other apps in front. An agent (or a person) runs these against a
fresh Debug build and records each result in `agent-checks.json`:

```json
{ "id": "notch-look", "result": "pass", "date": "2026-11-06", "evidence": "verification/agent/notch.png", "notes": "…" }
```

`result` is `pass` or `fail`. `scripts/feature_report.py` fails the run if a
feature lists a check that's missing or not passing.

## Setup

```bash
scripts/verify.sh --no-ui                     # builds the app
APP=build/DerivedData/Build/Products/Debug/Vaasi.app
open -n "$APP" --args -UITesting -AllowCapture -countdownSeconds 0
swift scripts/window-list.swift Vaasi         # window IDs for screenshots
screencapture -x -o -l <windowID> verification/agent/<name>.png
```

Capture only Vaasi's own windows (`-l`), never the whole screen.
`-AllowCapture` makes the windows visible to screenshots; leave it off for
`capture-hidden`.

## Checks

| ID | What to do | Pass when |
|---|---|---|
| `notch-look` | Start the Welcome note in notch mode and capture the prompter window. | Black shape flush with the top edge, wider than the notch, rounded bottom corners, centered monospaced white text below the camera area. |
| `floating-look` | Switch to floating, capture it. | Dark rounded window with pause (left) and return-to-notch and stop (right) on hover; text centered. |
| `beam-look` | Run voice mode with `VAASI_SYNTH_AUDIO="speak:…"`, capture while speaking and while silent. | Glow at the bottom is clearly brighter and larger while speaking. |
| `text-color` | Set a non-white text color and size in Settings › Prompter, start the prompter, capture. | Prompter text uses the chosen color and size; the Settings preview matched it. |
| `capture-hidden` | Launch **without** `-AllowCapture`, start the prompter, try `screencapture -l <prompter id>` and a full-screen `screencapture` cropped to the prompter's frame. | The window capture fails or is empty, and the prompter does not appear in the full-screen image. |
| `drop-import` | Drag a `.md` or `.docx` file onto the library window. | A new note appears with the file's text and is selected. |
| `real-mic` | Launch without `VAASI_SYNTH_AUDIO`, voice mode, speak into the Mac's microphone, then stop. | Scrolls while speaking, holds when quiet, beam follows your voice. |
| `noise-suppression` | Turn on Settings › Voice › Reduce background noise, run a session with a real mic. | Session runs, level meter works, no errors. |
| `global-shortcut-other-app` | Start the prompter, bring another app to the front, press ⇧→ and ⌥⇧Space. | Speed and pause change while the other app stays in front. |
| `menu` | Open the Vaasi app menu. | No Services submenu. |
