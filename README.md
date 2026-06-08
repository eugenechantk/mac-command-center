# Mac Command Center

Mac Command Center is a native macOS SwiftUI menu-bar app for managing local developer/runtime services and Mac awake behavior from one compact popover.

## What It Does

- Keeps the Mac awake while plugged in.
- Optionally keeps the Mac awake on battery via a one-shot override that clears itself when you plug back in.
- Supports closed-lid awake mode for MacBook use cases.
- Optionally keeps displays awake.
- Shows Remodex and OpenClaw process status.
- Starts and stops the Remodex bridge and OpenClaw gateway.
- Shows Remodex pairing details when Remodex publishes a pairing session.

The menu-bar popover is the primary control surface. It includes toggles for awake behavior and service rows for Remodex and OpenClaw.

## Awake Behavior

The app uses macOS-native power-management mechanisms:

- `/usr/bin/caffeinate -s -w <app-pid>` keeps the system awake while on AC power.
- `/usr/bin/caffeinate -s -d -w <app-pid>` also prevents display sleep when `Keep Display Awake` is enabled.
- IOKit power management disables normal clamshell sleep while `Keep Awake When Plugged In` is active.
- IOKit clamshell notifications detect lid-close events.
- `/usr/bin/pmset displaysleepnow` is called on lid close when display-awake mode is off.

By default the awake assertion only runs on external power. If unplugged while enabled, the awake assertion pauses until power is connected again. Enable `Keep Awake on Battery` to keep the assertion running on battery as well — this override turns itself off automatically the moment AC power is reconnected, so it never silently drains the battery on a later unplug.

## Prerequisites

- macOS on Apple Silicon or Intel Mac.
- Xcode or Xcode Command Line Tools.
- FlowDeck CLI for build/run/test automation.
- Remodex installed at `/opt/homebrew/bin/remodex`.
- OpenClaw installed at `/opt/homebrew/bin/openclaw`.
- App sandbox disabled for the macOS target, because the app needs to run local CLI tools and power-management commands.

Remodex and OpenClaw installation/onboarding are intentionally out of scope for this app. Install and configure them separately first.

## Project Layout

```text
MacCommandCenter/
  MacCommandCenter/          App source
  MacCommandCenterTests/     Unit tests
  MacCommandCenterUITests/   UI tests
  MacCommandCenter.xcodeproj Xcode project
.codex/
  brainstorm/                Planning notes
  spikes/                    Local spike artifacts
```

Key files:

- `CommandCenterPanel.swift`: menu-bar popover UI.
- `CommandCenterModel.swift`: app state and service coordination.
- `AwakeController.swift`: caffeinate, IOKit, and lid-close behavior.
- `ManagedService.swift`: Remodex/OpenClaw status parsing.
- `CommandRunner.swift`: external command execution.

## Development

Use FlowDeck from the Xcode project directory:

```bash
cd MacCommandCenter
flowdeck build
flowdeck run
flowdeck test
flowdeck apps
```

Do not use `xcodebuild` directly for this repository workflow. FlowDeck stores the selected project, scheme, and macOS target.

## Current Limitations

- The app expects Homebrew-style executable paths under `/opt/homebrew/bin`.
- Service installation and onboarding are not managed by the app.
- Some awake and lid-close behavior depends on macOS power-management APIs and may vary across hardware or OS versions.
