# Closed-Lid Awake Spike

Date: 2026-04-28

## Current Finding

Amphetamine-style closed-lid awake is a separate implementation from `caffeinate`.

`caffeinate -s -d` prevents idle sleep and display sleep while the lid is open, but it does not disable MacBook clamshell sleep behavior. Closed-lid awake appears to require calling the IOPM root domain clamshell sleep selector.

## API Path

Local SDK evidence:

- `IOPMLibDefs.h` defines `kPMSetClamshellSleepState = 12`.
- `IOPM.h` defines:
  - `AppleClamshellState`
  - `AppleClamshellCausesSleep`
  - `kIOPMDisableClamshell`
  - `kIOPMEnableClamshell`
  - `kIOPMMessageClamshellStateChange`
- `IOPMLib.h` exposes `IOPMFindPowerManagement`.

The working probe opens the IOPM root domain connection and calls:

```swift
IOConnectCallScalarMethod(
    connection,
    12,          // kPMSetClamshellSleepState
    [1],         // disable clamshell sleep
    1,
    nil,
    &outputCount
)
```

Use scalar `0` to restore normal clamshell sleep.

## Probe

Created:

- `.codex/spikes/ClosedLidAwakeProbe.swift`
- `.codex/spikes/ClosedLidAwakeProbe`

Commands:

```bash
swiftc .codex/spikes/ClosedLidAwakeProbe.swift -o .codex/spikes/ClosedLidAwakeProbe -framework IOKit

.codex/spikes/ClosedLidAwakeProbe disable
.codex/spikes/ClosedLidAwakeProbe enable
.codex/spikes/ClosedLidAwakeProbe pulse
```

Observed:

- The probe compiles as an arm64 Mach-O executable.
- `pulse` successfully disables clamshell sleep for five seconds and restores it.
- The call succeeds from a normal user process; no sudo prompt or helper was needed in this environment.
- Manual lid-close test succeeded after running `disable`: audio/video continued while the MacBook lid was closed.
- `enable` returned success afterward. `AppleClamshellCausesSleep` still reported `No` while the lid was open, so that registry value is not a sufficient standalone restore verification.

## Manual Test Protocol

Use this only while the MacBook is on a hard surface with normal ventilation.

1. Start audio or video playback.
2. In Terminal, run:

```bash
.codex/spikes/ClosedLidAwakeProbe disable
```

3. Close the MacBook lid for 15-30 seconds.
4. Confirm whether playback continues.
5. Open the lid.
6. Immediately restore normal behavior:

```bash
.codex/spikes/ClosedLidAwakeProbe enable
```

7. Confirm the Mac still sleeps normally when the lid is closed after restore.

Safety check:

```bash
ioreg -r -k AppleClamshellCausesSleep -d 1 | rg 'AppleClamshell|clamshellSleepDisabled'
```

## Product Recommendation

Do not merge this into the normal Always On toggle.

Add it as an explicit advanced option only after manual testing:

- Toggle: `Allow Closed-Lid Awake`
- Warning: `May increase heat. Keep the MacBook ventilated. Some Macs may still sleep after power changes.`
- Automatically stop on quit.
- Restore clamshell sleep on app termination.
- Consider auto-disable on low battery or elevated thermal state.

## Open Questions

- Does this reliably keep Eugene's specific MacBook awake after lid close?
- Does it survive power adapter disconnect/reconnect?
- Does it need a fallback if macOS ignores the call after sleep/wake transitions?
- Should the app combine this with `caffeinate -s -d`, or is clamshell sleep disable plus system sleep assertion enough?

## Sources

- Amphetamine closed-display mode docs: https://iffy.freshdesk.com/support/solutions/articles/48001077199-amphetamine-closed-display-mode
- Amphetamine failed closed-display session docs: https://iffy.freshdesk.com/support/solutions/articles/48001180528-about-failed-closed-display-mode-sessions
- Stack Overflow discussion with IOPM root-domain selector details: https://stackoverflow.com/questions/59594123/enabling-closed-display-mode-w-o-meeting-apples-requirements
- Local SDK headers: `IOPMLibDefs.h`, `IOPM.h`, `IOPMLib.h`
