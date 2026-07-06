# Feature: Hermes Agent Gateway

## User Story

As Eugene, I want Mac Command Center to manage Hermes Agent instead of OpenClaw so that the active gateway can be started, stopped, and bootstrapped from the menu bar app.

## User Flow

1. Open Mac Command Center.
2. The app starts the Hermes Agent gateway if it is not already running.
3. The services section shows Hermes Agent status.
4. Use the Hermes Agent button to start or stop the gateway.

## Success Criteria

- [x] SC1: The services section shows Hermes Agent instead of OpenClaw. Verify with app build/UI code inspection.
- [x] SC2: Opening the command center starts Hermes Agent gateway when it is not running. Verify by stopping Hermes, launching Mac Command Center, and checking `hermes gateway status`.
- [x] SC3: Hermes Agent status is parsed from the installed CLI output. Verify with unit tests.
- [x] SC4: Managed process grouping recognizes Hermes Agent gateway processes. Verify with unit tests.
- [x] SC5: The Hermes Agent service row is wired to start/stop the Hermes gateway. Verify with code inspection and app build.

## Test Strategy

Use existing XCTest coverage for model defaults, status parsing, and process grouping. Use FlowDeck for macOS build and test execution.

## Tests

- `MacCommandCenterTests.swift`
  - Hermes gateway parser handles running PID output.
  - Hermes gateway parser treats loaded-without-PID output as stopped.
  - Hermes gateway parser reports command failures.
  - Hermes process display and collapsed names recognize Hermes Agent.

## Implementation Details

Replace the OpenClaw service state and commands with a Hermes-specific controller using `/Users/eugenechan/.local/bin/hermes gateway status/start/stop`.

## Residual Risks

UI clicking of the Hermes Agent toggle was not automated through Appium; the row wiring is covered by build/code inspection, and the actual Hermes start command was exercised by the app launch path.

## Bugs

None yet.

## Verification Evidence

- SC1, SC5: `flowdeck build` from `MacCommandCenter/` completed successfully.
- SC2: Stopped Mac Command Center with `flowdeck stop 56EB8FC4`, stopped Hermes with `/Users/eugenechan/.local/bin/hermes gateway stop`, confirmed `Gateway service is not loaded`, then ran `flowdeck run`. A follow-up `/Users/eugenechan/.local/bin/hermes gateway status` reported `Gateway service is loaded` with `PID = 95565`.
- SC3, SC4: `flowdeck test` passed 21/21 tests.
- Runtime check: `flowdeck apps` showed Mac Command Center running as app ID `C60B7BBC`, PID `94700`.
