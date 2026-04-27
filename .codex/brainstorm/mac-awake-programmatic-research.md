# Programmatic Mac Awake Research

Date: 2026-04-27

## Recommendation

Implement Always On in v1 by supervising `/usr/bin/caffeinate` from the app. This is pragmatic, Apple-provided, and uses the same macOS power assertion system underneath.

Use:

- `caffeinate -s` for the default "keep awake while plugged in" behavior.
- `caffeinate -s -d` when the user explicitly wants the display kept awake too.
- `caffeinate -i` only if we later want a mode that also works while on battery.
- `IOPSGetProvidingPowerSourceType` plus a power-source notification to enforce "only while plugged in."
- `pmset -g assertions` only as a diagnostic/debugging tool, not as the implementation.

Avoid:

- Writing persistent power settings with `pmset`.
- Treating `caffeinate` as sufficient for lid-closed awake behavior.
- Trying to defeat user-initiated sleep, thermal sleep, or critical battery sleep.

Native IOKit assertions remain the later polish path if supervising a `caffeinate` child process creates state-management friction. They are not required to satisfy v1.

## What Is Actually Possible

macOS distinguishes idle sleep from forced sleep.

The app can prevent idle sleep: the machine is unused for long enough that macOS would normally sleep it.

The app cannot reliably prevent every forced sleep:

- User chooses Sleep from the Apple menu.
- Critical battery.
- Thermal emergency.
- Shutdown/restart/logout.
- Some hardware or OS-level power-management decisions.

Closed-lid behavior is a special case. `caffeinate` alone does not keep a MacBook awake when the lid closes, but Amphetamine documents that it can enable closed-display mode without Apple's normal external display/keyboard/power requirements by using a publicly accessible API. Local SDK headers expose a lower-level power-management selector named `kPMSetClamshellSleepState`, which is likely in the family of APIs involved. This needs a separate spike before we copy the behavior.

That boundary matters for product language. The current menu item should say something like "Prevent Idle Sleep", not "Never Sleep Under Any Circumstance." If we add closed-lid support, it should be an explicit advanced mode.

## How Existing Keep-Awake Apps Work

Most keep-awake apps are UI/session managers around macOS power assertions.

There are two common implementation styles:

1. Wrap `/usr/bin/caffeinate`.
   - Example: KeepingYouAwake's README says it is a small wrapper around Apple's `caffeinate` command-line utility.
   - This is simple and reliable because `caffeinate` itself creates macOS power assertions.
   - The app's value is the menu bar UX, timers, triggers, preferences, launch-at-login, and diagnostics.

2. Call IOKit/Foundation APIs directly.
   - Apps can create the same underlying assertions with `IOPMAssertionCreateWithDescription` or use `ProcessInfo.beginActivity`.
   - This avoids supervising a helper process and gives the app direct ownership of assertion IDs and error states.

Amphetamine appears to use native/system power-management APIs plus additional logic for triggers and closed-display behavior. Its support docs mention macOS API calls for closed-display behavior and also document that macOS/firmware can still fail or override this. That matches the same basic limit: these apps can control idle sleep well, but cannot guarantee every forced sleep path.

Bottom line: keep-awake apps are not bypassing macOS power management. They are asking macOS to hold an assertion, then presenting a better control surface around that assertion.

For closed-display mode specifically, Amphetamine does more than `caffeinate`. Its support docs say it disables Apple's usual closed-display requirements through a public API. It also has failure handling because some Macs can still fail closed-display sessions after power-source changes.

## API Options

### Option A: Spawn `/usr/bin/caffeinate`

This is the recommended v1 implementation.

- `caffeinate -i` prevents system idle sleep.
- `caffeinate -d` prevents display sleep.
- `caffeinate -s` prevents system sleep only on AC power.
- `caffeinate -t seconds` adds a timeout.
- `caffeinate -w pid` holds the assertion until another process exits.

Implementation notes:

- Start a `Process` when the menu bar toggle turns on.
- Store the child PID and current command flags in app state.
- Terminate the process when the toggle turns off, app quits, or the user changes mode.
- Reconcile state on a timer and after wake by checking whether the child is still running.
- Use `pmset -g assertions` in diagnostics to prove the expected assertion is active.
- If using `-s`, macOS itself makes the assertion valid only while on AC power. The app should still show "Paused on battery" by observing power-source changes.

This is slightly less elegant than direct IOKit because we have to supervise a child process, but it is good enough for v1 and mirrors how existing lightweight menu bar apps work.

### Option B: IOKit Assertions

This is the recommended future implementation if `caffeinate` supervision becomes annoying or if we want tighter diagnostics/control. It is explicit, inspectable, and avoids child-process state.

Core APIs:

- `IOPMAssertionCreateWithDescription`
- `IOPMAssertionCreateWithName`
- `IOPMAssertionRelease`
- `IOPMCopyAssertionsStatus`
- `IOPMCopyAssertionsByProcess`

Relevant assertion types:

- `kIOPMAssertPreventUserIdleSystemSleep`
  - Prevents automatic idle system sleep.
  - Allows the display to dim/sleep.
  - Does not block lid close, Apple-menu sleep, low battery, or thermal sleep.
- `kIOPMAssertPreventUserIdleDisplaySleep`
  - Prevents the display from dimming/turning off due to idle activity.
  - While active, the system also cannot enter idle sleep.
  - Does not wake an already-off display; `IOPMAssertionDeclareUserActivity` is the API for that if ever needed.
- `kIOPMAssertionTypePreventSystemSleep`
  - Avoid for direct app implementation. The local SDK marks it deprecated and says to use `NetworkClientActive` or `PreventUserIdleSystemSleep` instead, even though `caffeinate -s` still creates a visible `PreventSystemSleep` assertion on AC power.

### Option C: `ProcessInfo.beginActivity`

This is higher-level and Swifty:

```swift
let activity = ProcessInfo.processInfo.beginActivity(
    options: [.idleSystemSleepDisabled],
    reason: "Mac Command Center keeping the Mac awake"
)

ProcessInfo.processInfo.endActivity(activity)
```

It is good for scoped work, but less ideal for this app because we need a persistent session toggle, diagnostics, and optional display behavior.

### Option D: `pmset`

Do not use this for v1.

`pmset` changes system-wide power settings. That is too broad for a personal menu bar toggle, can require elevated privileges for some settings, and creates persistent state that can outlive the app in surprising ways.

## Power Source Detection

Use IOKit power source APIs:

- `IOPSCopyPowerSourcesInfo()`
- `IOPSGetProvidingPowerSourceType(snapshot)`
- Compare against:
  - `kIOPMACPowerKey`
  - `kIOPMBatteryPowerKey`
  - `kIOPMUPSPowerKey`

For change notifications:

- `IOPSCreateLimitedPowerNotification` is suitable when we only care about transitions between unlimited power and limited power.
- `IOPSNotificationCreateRunLoopSource` is noisier and fires for more battery/charge changes.

Recommended behavior:

```text
on app launch:
  load user preference
  read current power source
  if alwaysOnEnabled && powerSource == AC:
    acquire system assertion
    optionally acquire display assertion

on menu toggle changed:
  update preference
  reconcile assertions

on power source changed:
  if on battery:
    release assertions
    show "Paused on battery"
  if on AC and enabled:
    acquire assertions

on app termination:
  release assertions
```

## Swift Sketch

```swift
import Foundation
import IOKit.pwr_mgt
import IOKit.ps

final class AwakeController {
    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0

    var enabled = false
    var preventDisplaySleep = false

    func reconcile() {
        guard enabled, isOnACPower() else {
            releaseAssertions()
            return
        }

        if systemAssertion == 0 {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithDescription(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                "Mac Command Center Always On" as CFString,
                "Keeping the Mac awake while plugged in" as CFString,
                "Mac Command Center is keeping this Mac awake while connected to power." as CFString,
                nil,
                0,
                nil,
                &id
            )
            if result == kIOReturnSuccess {
                systemAssertion = id
            }
        }

        if preventDisplaySleep, displayAssertion == 0 {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithDescription(
                kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                "Mac Command Center Display Awake" as CFString,
                "Keeping the display awake while plugged in" as CFString,
                "Mac Command Center is keeping the display awake." as CFString,
                nil,
                0,
                nil,
                &id
            )
            if result == kIOReturnSuccess {
                displayAssertion = id
            }
        } else if !preventDisplaySleep {
            releaseDisplayAssertion()
        }
    }

    func releaseAssertions() {
        if systemAssertion != 0 {
            IOPMAssertionRelease(systemAssertion)
            systemAssertion = 0
        }
        releaseDisplayAssertion()
    }

    private func releaseDisplayAssertion() {
        if displayAssertion != 0 {
            IOPMAssertionRelease(displayAssertion)
            displayAssertion = 0
        }
    }

    private func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }
        let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        return source == kIOPMACPowerKey as CFString
    }
}
```

## Verification Plan

Manual checks:

1. Turn Always On off.
2. Run `pmset -g assertions` and confirm Mac Command Center has no active assertion.
3. Turn Always On on while plugged in.
4. Run `pmset -g assertions` and confirm `PreventUserIdleSystemSleep` is active for Mac Command Center.
5. Enable display awake.
6. Confirm `PreventUserIdleDisplaySleep` becomes active.
7. Unplug power.
8. Confirm assertions release and UI says "Paused on battery."
9. Plug power back in.
10. Confirm assertions reacquire if the user preference remains enabled.
11. Quit the app.
12. Confirm assertions release.

Automated/unit checks:

- Unit-test state reconciliation with a mock power-source provider and mock assertion client.
- Integration-test the real assertion client behind a manual test flag.
- Avoid sleep-duration tests in CI; they are slow and flaky.

## Product Implications

Recommended menu bar copy:

- Toggle: "Prevent Idle Sleep"
- Status on AC: "Active on power adapter"
- Status on battery: "Paused on battery"
- Display option: "Keep Display Awake"
- Future advanced option: "Allow Closed-Lid Awake"

Avoid:

- "Never sleep"
- "Always on no matter what"

## Closed-Lid Awake Spike

Goal: determine whether we can safely implement Amphetamine-style closed-display mode without private APIs or a privileged helper.

Known facts:

- Amphetamine 5.0+ supports keeping a Mac awake when closing the display/lid.
- Amphetamine's support docs say it uses a publicly accessible API to disable Apple's closed-display requirements.
- Amphetamine also documents failure cases where macOS stops honoring the closed-display session, especially around power-source changes on some Macs.
- `caffeinate -s -d` is not enough for this behavior.
- The local macOS SDK exposes `kPMSetClamshellSleepState` in `IOPMLibDefs.h`, but this is lower-level than the public `caffeinate` path and needs a focused implementation spike.

Spike tasks:

1. Identify the exact callable API and whether Swift can invoke it without private symbols.
2. Confirm whether the app needs additional entitlements, accessibility permissions, helper tools, or user approval.
3. Test on Eugene's MacBook with:
   - power connected
   - power disconnected
   - lid close while audio/video plays
   - power disconnect/reconnect while lid remains closed
4. Add UI only if the behavior is reliable enough:
   - "Allow Closed-Lid Awake"
   - warning copy about heat and model-specific failures
   - automatic fail-safe when battery is low or thermal state is elevated

## Sources Checked

- Apple `IOPMLib.h` SDK header for assertion semantics and deprecations.
- Apple `IOPMLibDefs.h` SDK header for lower-level clamshell sleep state selector.
- Apple `IOPowerSources.h` SDK header for AC/battery detection and notifications.
- Amphetamine support docs on closed-display mode and failed closed-display sessions.
- Apple Technical Q&A QA1340 on idle versus forced sleep.
- Apple Energy Efficiency Guide for Mac Apps on `NSProcessInfo` activities and `pmset -g assertions`.
- Local macOS `caffeinate(8)` manpage.
- `pmset -g assertions` on Eugene's machine to confirm assertion names and runtime visibility.
