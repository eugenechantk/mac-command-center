# Mac Command Center Plan

Date: 2026-04-27

## Recommendation

Build a native SwiftUI macOS utility app whose required primary interface is a menu bar popup. A small Settings window can exist for configuration, but daily control must happen from the menu bar popup. The first version should be a personal control plane, not a generalized process supervisor.

The app should own:

- A plugged-in awake mode using macOS power assertions.
- Runtime Remodex controls by shelling out to the already-installed `remodex` CLI.
- Runtime OpenClaw process/gateway controls for the already-installed OpenClaw setup.
- Later OpenClaw macOS app launch/open controls after the process-control spike is proven.
- Launch-at-login for the app itself.
- Health/status display, logs, and recovery actions.

The app should not initially own:

- Installing, updating, onboarding, pairing, or configuring Remodex/OpenClaw.
- Reimplementing Remodex or OpenClaw daemons.
- Reimplementing OpenClaw's macOS companion features, permissions management, node host, gateway broker, local/remote mode, or tool approvals.
- Editing system sleep settings with `pmset`.
- Defeating thermal sleep, shutdown, or battery safeguards.
- Amphetamine-style closed-lid awake behavior in the initial `caffeinate` implementation.
- A generalized launchd editor for arbitrary processes.

## Why This Shape

Remodex and OpenClaw already expose daemon/service paths:

- Remodex `up` installs/starts a macOS background bridge service, `start`/`restart`/`stop` manage it, and `status` reports launchd/bridge state.
- OpenClaw's recommended setup is `openclaw onboard --install-daemon`; the docs say this installs the Gateway daemon using launchd/systemd user services.

So this app should orchestrate those contracts and surface state clearly, rather than trying to be a second daemon manager underneath them.

Assumption for v1: Remodex and OpenClaw have already been installed and onboarded outside Mac Command Center. The app can report missing binaries/apps or unhealthy services, but it should not lead setup flows.

OpenClaw also has its own macOS companion app. Its docs describe it as a menu-bar companion that owns TCC permissions, manages or attaches to the Gateway locally, supports local/remote mode, exposes macOS-only node tools, and controls launchd for the per-user Gateway. Command Center should not duplicate that app. It should provide quick access to open it, show whether it appears healthy, and offer safe recovery actions that defer to OpenClaw's existing app/CLI/launchd contracts.

The awake feature is different: it is small enough to implement by supervising Apple’s built-in `/usr/bin/caffeinate` CLI for v1. `caffeinate` already creates the macOS power assertions we need, and we can move to direct IOKit assertions later only if child-process supervision becomes a practical problem.

## Product Surface

### Menu Bar Extra

This is a must-have requirement, not an optional convenience. The popup is the control surface for turning Always On, Remodex, and OpenClaw on or off without opening a full app window.

Primary state should be readable from the icon:

- Normal: app running, no awake assertion.
- Awake: plugged-in awake assertion active.
- Warning: one or more managed services unhealthy.
- Error: required binary missing or command failed.

Required popup capabilities:

- Header: overall status, power source, last check time.
- Awake control:
  - Toggle: "Keep Awake When Plugged In"
  - Optional sub-toggle: "Keep Display Awake"
  - Status text: "Active on power adapter", "Paused on battery", or "Off"
- Services:
  - Remodex row: status plus direct Start, Restart, Stop, and Logs/Watch actions.
  - OpenClaw row: process/gateway status plus direct Start, Stop, Restart, Doctor/Health, and Logs where the installed setup supports them.
  - Post-spike: add OpenClaw.app installed/running status and an Open App action.
- Quick actions:
  - Restart unhealthy services
  - Refresh status
  - Open Settings
  - Quit

Use `MenuBarExtra` with `.menuBarExtraStyle(.window)` for v1 because the popup needs richer state and multiple direct controls. A plain menu is too cramped for the required control surface.

### Settings Window

Keep settings sparse:

- General:
  - Launch Mac Command Center at login.
  - Start minimized/menu-bar-only.
- Awake:
  - Enable awake mode by default.
  - Only while plugged in.
  - Prevent display sleep.
- Remodex:
  - Binary path or auto-detected path.
  - Relay env vars, especially `REMODEX_RELAY`.
  - Start Remodex when app launches.
- OpenClaw:
  - Binary path or auto-detected path.
  - Gateway port, default `18789`.
  - Watch gateway/daemon health when app launches.
  - Auto-restart unhealthy gateway/daemon.
  - Post-spike: OpenClaw.app path or auto-detected app bundle.
- Diagnostics:
  - Command timeout.
  - Log file locations.
  - Export diagnostics.

Settings are secondary. Any control needed during normal daily use must also be available in the menu bar popup.

## Architecture

### App Modules

- `MacCommandCenterApp`
  - SwiftUI app entry.
  - Required `MenuBarExtra` popup.
  - Settings scene.
  - `LSUIElement = true` if menu-bar-only behavior is desired.

- `AppStateStore`
  - Single observable model for power state, service statuses, command output, and last errors.
  - Persists user settings via `UserDefaults` or SwiftData if history becomes useful.

- `AwakeController`
  - Observes AC/battery state.
  - Starts/stops a supervised `/usr/bin/caffeinate` child process.
  - Enforces "plugged in only" policy.

- `ServiceController`
  - Shared command runner and status model.
  - Handles binary discovery, environment, timeout, stdout/stderr capture, and log truncation.

- `RemodexService`
  - `start`: `remodex start` for normal service start.
  - `restart`: `remodex restart`.
  - `stop`: `remodex stop`.
  - `status`: `remodex status`.
  - `watch`: optional terminal/log view for `remodex watch`.

- `OpenClawService`
  - `status`: process check, gateway port probe, launchd state, and/or `openclaw doctor`.
  - `start`: start/resume the existing OpenClaw gateway/daemon using the safest installed CLI or launchd path verified during the spike.
  - `stop`: stop/pause the existing OpenClaw gateway/daemon using the safest installed CLI or launchd path verified during the spike.
  - `restart`: restart the existing gateway using OpenClaw's documented launchd label/CLI path, not by spawning a permanent gateway child process.
  - `doctor`: `openclaw doctor`.
  - `health`: `openclaw health --json` if available in the installed CLI.
  - `logs`: surface recent gateway/daemon output if the installed setup exposes a log path.

### OpenClaw Mac App Integration

Command Center should treat OpenClaw's macOS app as the owner of OpenClaw-specific Mac capabilities.

This is not part of the spike. The spike should only track OpenClaw process/gateway status and provide on/off controls for the existing process.

Responsibilities:

- Provide an "Open OpenClaw" button in the Command Center popup.
- Show whether `OpenClaw.app` is installed and running.
- Show a compact Gateway health state, but defer detailed diagnostics to OpenClaw.
- Use OpenClaw's documented launchd label, `ai.openclaw.gateway`, for recovery if the local Gateway is unhealthy.
- Prefer OpenClaw's own CLI health/status commands:
  - `openclaw gateway status`
  - `openclaw doctor`
  - `openclaw health --json` if present
- Optionally support `openclaw://` deep links later, such as `openclaw://agent?...`, but do not make this a v1 dependency.

Non-responsibilities:

- Do not manage OpenClaw TCC permissions.
- Do not implement OpenClaw local/remote mode.
- Do not manage OpenClaw Exec approvals.
- Do not expose Canvas, Camera, Screen Recording, `system.run`, or other OpenClaw node tools.
- Do not install the OpenClaw CLI from Command Center.
- Do not spawn the Gateway as a long-lived child process.

### Process Management Strategy

Use a three-tier strategy:

1. Assume each tool has already been installed/onboarded and prefer its own app/daemon contract.
2. Observe via CLI status, launchd state, process checks, and port checks.
3. If OpenClaw has no clean restart command, use launchd/service restart or show a clear manual recovery command instead of owning a permanent foreground child process.

This keeps the app resilient to upstream changes and avoids conflicts with Remodex/OpenClaw's own launchd configuration.

### Awake Strategy

Default behavior:

- If user enables "Keep Awake When Plugged In" and AC power is present, hold a `PreventUserIdleSystemSleep` assertion.
- For v1, create that assertion by running `caffeinate -s`.
- If "Keep Display Awake" is enabled, run `caffeinate -s -d`.
- If power source changes to battery, show "Paused on battery"; `caffeinate -s` is only valid on AC power, and the app can stop/restart the child process to keep UI state explicit.
- On app quit, terminate the `caffeinate` child process.
- On app crash, the supervised child should terminate with the app process group if launched correctly; diagnostics should still check for stale child processes.

Non-goals:

- No `pmset` writes.
- No sudo requirement.
- No battery override in v1.
- No native IOKit assertion implementation in v1 unless `caffeinate` supervision fails during the spike.
- No Amphetamine-style closed-lid awake mode until we run a dedicated power-management spike.

Future closed-lid mode:

- Amphetamine documents that it can keep Macs awake with the display/lid closed by using a publicly accessible API to disable Apple's normal closed-display requirements.
- `caffeinate -s -d` does not provide this behavior.
- Local SDK headers expose `kPMSetClamshellSleepState`, which should be investigated in a separate spike before implementing this app-side.
- Any closed-lid mode must be explicit in UI, include heat/battery warnings, and include fail-safe behavior.

## Data Model

```swift
struct ManagedServiceStatus {
    enum Health { case unknown, running, stopped, degraded, missingBinary, error }
    var name: String
    var health: Health
    var pid: Int?
    var lastCheckedAt: Date?
    var lastStartedAt: Date?
    var lastExitCode: Int32?
    var summary: String
    var recentOutput: String
}

struct AwakeStatus {
    var enabled: Bool
    var acPowerOnly: Bool
    var powerSource: PowerSource
    var systemAssertionActive: Bool
    var displayAssertionActive: Bool
    var lastError: String?
}
```

## Milestones

### Milestone 1: Spike

Goal: prove the minimal SwiftUI menu bar app and process lifecycle controls before polishing UI or integrating OpenClaw.app.

- Create a minimal SwiftUI menu bar app.
- Implement AC power detection.
- Implement Always On by supervising `/usr/bin/caffeinate`.
- Show Remodex process/service status in the menu bar popup.
- Turn Remodex on/off from the menu bar popup.
- Show OpenClaw process/gateway status in the menu bar popup.
- Turn OpenClaw on/off from the menu bar popup using the existing installed CLI or launchd service mechanism.
- Run the minimum commands needed to discover actual lifecycle behavior:
  - `remodex status/start/stop`
  - `openclaw doctor`
  - `openclaw gateway status` if available
  - launchd/process/port checks for OpenClaw
- Document actual command output formats from Eugene's machine.

Exit criteria:

- Menu bar toggle keeps the Mac awake only while plugged in.
- Remodex can be started/stopped from the app.
- OpenClaw process/gateway can be started/stopped from the app.
- Remodex and OpenClaw status are visible directly in the menu bar popup.
- Always On, Remodex, and OpenClaw can each be controlled directly from the menu bar popup.

### Milestone 2: Usable Personal Tool

- Build the window-style menu bar panel.
- Add Settings.
- Add launch-at-login.
- Add binary path detection and editable overrides.
- Add service health-watch and auto-restart preferences.
- Add command output/error surfaces.
- Add lightweight logs.

Exit criteria:

- App is useful daily without Terminal for normal Remodex controls and OpenClaw gateway/daemon recovery.

### Milestone 3: Hardening

- Add structured diagnostics export.
- Add safer command timeouts and cancellation.
- Add integration tests for command runner parsing.
- Add UI tests for menu/panel state.
- Sign/notarize for local distribution.
- Consider packaging as a `.dmg`.

## Important Unknowns

- OpenClaw.app bundle path/bundle identifier, daemon label, log path, health commands, and restart command need to be verified against Eugene's installed setup. The app should not run onboarding; it should only open, monitor, and recover an existing install.
- Remodex `status` output may be human-readable rather than machine-readable. If there is no JSON mode, parsing should stay shallow and backed by launchd/process checks.
- Sandboxing may be incompatible with spawning global Node CLIs and reading user logs. For a personal utility, unsigned or Developer ID distribution without App Store sandboxing may be simpler.
- Menu bar-only apps can be awkward for Settings activation. This should be tested early.

## Recommended v1 Decisions

- Native SwiftUI, not Electron or Tauri.
- Required window-style `MenuBarExtra` popup plus secondary Settings window.
- App is a user-space utility, not a privileged helper.
- Use supervised `/usr/bin/caffeinate` for awake behavior in v1; keep native IOKit assertions as a later polish path.
- Use Remodex's existing daemon commands.
- Treat OpenClaw as install-once infrastructure with its own macOS companion app; open the app from Command Center, monitor gateway/app health, and restart the gateway through the existing service mechanism.
- Store settings locally only.
- No App Store target for v1.

## Source Notes

- Remodex README: local-first Codex bridge, macOS launchd service, `remodex up/start/restart/stop/status`, env vars including `REMODEX_RELAY`.
- OpenClaw README/docs: personal AI assistant, Node 24 or Node 22.14+, `openclaw onboard --install-daemon`, gateway default example on port `18789`, `openclaw doctor`, macOS companion app, `OpenClaw.app`, launchd label `ai.openclaw.gateway`, `openclaw://` deep links.
- Caffeinated README: Linux/systemd/Wayland utility, useful as a product reference but not a macOS implementation reference.
- Apple docs checked: SwiftUI `MenuBarExtra`, HIG Designing for macOS, HIG The menu bar, HIG Menus, HIG Settings, ServiceManagement, launchd agents/daemons, IOKit power assertion docs.
