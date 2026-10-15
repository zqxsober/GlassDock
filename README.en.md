<!-- Copyright 2026 zqxsober. SPDX-License-Identifier: Apache-2.0 -->

# GlassDock

[简体中文](README.md) · English

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange?logo=swift)](https://swift.org/)
[![Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

GlassDock is a native floating Dock for macOS 26 and later. It brings pinned apps and folders, windows on the current screen, and widgets for time, system status, calendars, reminders, music, and Codex usage into a resizable Liquid Glass strip.

[Download the latest release](https://github.com/zqxsober/GlassDock/releases/latest) · [Browse all releases](https://github.com/zqxsober/GlassDock/releases)

## Features

### Dock and windows

- Pin up to 12 apps or folders and reorder them.
- Show running app windows automatically. Multi-window apps get separate entries that activate the selected window.
- Window titles longer than 8 Swift characters are shortened with an ellipsis. The full title remains available to help and accessibility features.
- Right-click or Control-click a multi-window entry to close one window or unpin its app. Pinned apps and folders can also be removed from their context menus.
- Configure hover magnification, icon scale, Dock size (10–96 points), accent color, and visibility on launch.
- Press `⌘⇧D` to show or hide the floating Dock.
- Use Tab / Shift-Tab to move focus and Return to activate the selected entry or widget.

### Widgets

Add multiple independent widget instances and edit them in the control center. Available types include:

| Category | Widgets |
| --- | --- |
| Clocks and timers | Clock, world clock, stopwatch, focus timer, time progress, countdown, alarm, hydration reminder |
| Calendar and reminders | Date, next event, agenda, reminder list, next reminder, incomplete count |
| Notes | Editable sticky notes |
| Media | Playback information and controls for Apple Music (the macOS Music app) |
| System | Battery status, CPU and memory activity, network speed |
| AI | Codex account usage for the 5-hour and 7-day windows, shown as numbers, rings, bars, or capsules |
| System shortcuts | Run a named Shortcut, or choose files to share with AirDrop |

Weather widgets are currently UI placeholders. No weather provider is connected, so they do not show live weather data. Business-data and stock widgets are not available in this release.

## Install

1. Download the GlassDock DMG from [GitHub Releases](https://github.com/zqxsober/GlassDock/releases/latest).
2. Open the DMG, drag `GlassDock.app` into Applications, then launch it from there.
3. Grant the permissions requested by the features you choose to use.

The `v0.0.1` DMG is ad-hoc signed and has not been notarized by Apple. On first launch, Gatekeeper may warn that the developer cannot be verified or block the app. Check the release page for signing details and follow macOS prompts in **System Settings → Privacy & Security** to decide whether to allow it. Signing and notarization status for later versions will be stated in their release notes.

## Permissions and privacy

- **Accessibility**: When enabled, GlassDock can read ordinary app window titles and switch to or close an individual window. Window management uses the macOS Accessibility API and does not require Screen Recording permission. Window-level actions may be unavailable if access is denied.
- **Calendar and Reminders**: Access is requested only after you connect the corresponding widget.
- **Automation (Music)**: Control of the macOS Music app is requested only after you connect an Apple Music widget.
- **Codex usage**: Install the [Codex CLI](https://developers.openai.com/codex/cli/) and sign in with your ChatGPT account to read that account's plan usage. The widget requests quota status only; it does not send a conversation prompt or trigger model inference. Data includes remaining usage and reset times for the 5-hour and 7-day windows.
- **CPU temperature**: Only the CPU Temperature widget reads an undocumented sensor interface (IOHIDEventSystem on Apple silicon, AppleSMC on Intel) — read-only, never sent anywhere, and no extra permission is needed. If a macOS update makes the interface unavailable, the widget shows "Unavailable".
- **Local settings**: Dock layout and widget configuration are stored in local UserDefaults. GlassDock does not require a GlassDock account or provide cloud sync.

## Development

You need macOS 26 or later and Xcode with the Swift 6.2 toolchain and macOS 26 SDK. The SwiftPM package uses Swift tools version 6.2 and compiles in Swift 5 language mode.

```bash
git clone https://github.com/zqxsober/GlassDock.git
cd GlassDock
./build.sh
```

The local build creates `dist/GlassDock.app` and applies an ad-hoc signature by default. Run the tests with:

```bash
xcrun swift test --disable-sandbox
```

Set `DEVELOPER_ID_APPLICATION` to sign `build.sh` output with a Developer ID Application certificate. The release script targets a universal DMG for Apple silicon (`arm64`) and Intel (`x86_64`).

Create the `v0.0.1` release package with:

```bash
./scripts/release.sh --version 0.0.1
```

If a Developer ID Application certificate and `notarytool` credentials are configured, set `DEVELOPER_ID_APPLICATION` and `NOTARYTOOL_PROFILE` for signing and notarization. Check the release page for the script output and the release's actual signing status.

## Project layout

```text
Sources/GlassDock/       SwiftUI / AppKit app, floating Dock, and widgets
Sources/GlassDockCore/   Preferences, window grouping, widget and usage models
Tests/                  SwiftPM core-logic and UI tests
Resources/              App configuration and icon-generation resources
```

## License

GlassDock is licensed under the [Apache License 2.0](LICENSE).
