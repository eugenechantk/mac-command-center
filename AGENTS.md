# Repository Guidelines

## Project Structure & Module Organization

This repository contains a native macOS SwiftUI menu-bar app under `MacCommandCenter/`.

- `MacCommandCenter/MacCommandCenter/`: app source files.
- `MacCommandCenter/MacCommandCenter/Assets.xcassets/`: app icon, accent color, and image assets.
- `MacCommandCenter/MacCommandCenterTests/`: unit tests.
- `MacCommandCenter/MacCommandCenterUITests/`: UI tests.
- `.codex/brainstorm/` and `.codex/spikes/`: planning notes and local spike artifacts.

Core responsibilities are split by file: `CommandCenterModel.swift` owns app state, `CommandCenterPanel.swift` owns the menu UI, `AwakeController.swift` owns macOS power behavior, `ManagedService.swift` parses service status, and `CommandRunner.swift` runs external commands.

## Build, Test, and Development Commands

Use FlowDeck for Apple-platform automation from `MacCommandCenter/`:

```bash
cd MacCommandCenter
flowdeck build
flowdeck run
flowdeck test
flowdeck apps
```

- `flowdeck build`: builds the macOS app with the saved project config.
- `flowdeck run`: builds and launches the menu-bar app on `My Mac`.
- `flowdeck test`: runs the configured test target.
- `flowdeck apps`: lists FlowDeck-launched app instances and short IDs.

Do not use destructive git commands. Do not commit or push unless explicitly requested.

## Coding Style & Naming Conventions

Use idiomatic Swift and SwiftUI. Keep state mutations on `@MainActor` models when they affect UI. Prefer small, focused types over broad utility files. Use clear names such as `setKeepAwake(_:)`, `refreshStatuses()`, and `ServiceParser.remodexStatus(from:)`.

Follow existing formatting: 4-space indentation, one primary type per file where practical, concise comments only for non-obvious macOS or IOKit behavior.

## Testing Guidelines

Add tests under `MacCommandCenterTests/` for deterministic parsing and model logic. Add UI tests under `MacCommandCenterUITests/` for user-visible workflows when practical. Test names should describe behavior, for example `testRemodexStatusParsesPairingSession`.

Run `flowdeck build` before handing off code. Run `flowdeck test` when changing parsing, model behavior, or UI state logic.

## Commit & Pull Request Guidelines

Recent commits use concise imperative messages, for example:

- `Add phase 0 Mac command center`
- `Support closed-lid awake display behavior`
- `Pause awake mode while on battery`

PRs should include a short summary, verification commands, screenshots for UI changes, and notes for any macOS permission or power-management behavior.

## Security & Configuration Tips

The app shells out to local tools such as `remodex`, `openclaw`, `caffeinate`, and `pmset`. Keep command execution explicit: use absolute executable paths in app code and avoid shell interpolation. Treat pairing payloads and local service state as sensitive; do not log secrets or commit generated `.remodex` state.
