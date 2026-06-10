# Feature: iTerm Quick Launch + Collapsible Process List

## User Story

As Eugene, I want one-click buttons that open iTerm in `~/dev/inbox` with my AI CLI of choice already running, and a process list that stays compact until I need it, so the menu-bar panel is faster to use and less cluttered.

## User Flow

1. Open the Mac Command Center menu-bar panel.
2. See a new "Quick Launch" section with two buttons: **codexy** and **cy**.
3. Click **codexy** → iTerm opens a new window at `/Users/eugenechan/dev/inbox` and runs `codexy` (zsh alias for `codex --yolo`).
4. Click **cy** → iTerm opens a new window at `/Users/eugenechan/dev/inbox` and runs `cy` (zsh alias for `claude --dangerously-skip-permissions`).
5. The "Processes" section is collapsed by default, showing just the process names as a compact list.
6. Click the Processes header → expands to the existing scrollable list with details and Stop buttons. Click again → collapses.

## Success Criteria

- [x] SC1: Panel shows a Quick Launch section with two buttons (codexy, cy) — **Verify by:** screenshot of running panel.
- [x] SC2: Clicking codexy opens iTerm at `/Users/eugenechan/dev/inbox` running `codexy` — **Verify by:** runtime probe: trigger launch, confirm iTerm session at that directory running codex.
- [x] SC3: Clicking cy opens iTerm at `/Users/eugenechan/dev/inbox` running `cy` — **Verify by:** same runtime probe for claude.
- [x] SC4: Processes section is collapsed by default and lists process names only — **Verify by:** unit test for collapsed-name summary + screenshot of default state.
- [x] SC5: Clicking the Processes header expands to the existing scrollable detail list with Stop buttons; clicking again collapses — **Verify by:** interaction screenshots.
- [x] SC6: AppleScript sent to iTerm is correctly formed (cd to quoted directory, then command) — **Verify by:** unit tests on the script-builder function.
- [x] SC7: Launched iTerm windows open as the right third of the screen (1/3 width, full visible height, flush right) — **Verify by:** unit test on the bounds math + auditor measuring the actual window frame.
- [x] SC8 (bug fix): The command reliably executes even though the shell is wrapped by kiro-cli-term (slow init) — **Verify by:** script waits for rendered prompt before `write text`; auditor clicks codexy 3 times in a row, all must spawn codex in ~/dev/inbox.

## Platform & Stack

- **Platform:** macOS menu-bar app
- **Language:** Swift / SwiftUI
- **Key frameworks:** SwiftUI, AppKit; FlowDeck for build/test

## Steps to Verify

1. `cd MacCommandCenter && flowdeck build`
2. `flowdeck test`
3. `flowdeck run` → open the menu-bar panel
4. Click each Quick Launch button → verify iTerm window in `~/dev/inbox` with the right tool running
5. Observe Processes collapsed by default → expand → collapse

## Implementation Phases

### Phase 1: Terminal launcher + Quick Launch section

- Scope: new `TerminalLauncher.swift` (testable AppleScript builder + osascript runner), model method, new panel section with two buttons
- Success criteria covered: SC1, SC2, SC3, SC6
- Verification gate: unit tests for script builder, build passes

### Phase 2: Collapsible process list

- Scope: collapsed-by-default Processes section with name-only list, expandable to existing scrollable list; collapsed-name helper on `ManagedProcess`
- Success criteria covered: SC4, SC5
- Verification gate: unit test for collapsed-name summary, build passes, visual verification

## Decision Log

- **Launch mechanism:** `osascript` with iTerm's AppleScript API (`create window with default profile` + `write text`), executed via the existing `CommandRunner`. Alternative was `open -a iTerm <dir>` + System Events keystrokes — rejected as fragile and unable to reliably run a command. The app already uses osascript (Codex window closing), so the automation-permission pattern is established.
- **Aliases work because** iTerm sessions run interactive zsh, which loads `~/.zshrc` where `codexy` and `cy` are defined. No need to expand the aliases in the app.
- **Button labels:** use the alias names themselves (`codexy`, `cy`) with a caption explaining what they do — Eugene refers to them by alias.
- **Collapsed list dedupes names with counts** (e.g. "Caffeinate ×2") so multiple identical processes don't bloat the collapsed view. Logged here since the request just said "names in a list".
- **Expansion state is `@State` in the view** (not the model) — UI-only concern; resets to collapsed each time the panel is recreated, which matches "collapsed by default".
- **Window placement computed in Swift via NSScreen** (visibleFrame of `NSScreen.main`, converted to AppleScript top-left coordinates), not via Finder AppleScript — testable math, correct on multi-display setups, and respects menu bar/Dock insets. "Right third" = right third of the *visible* frame, so the window does not tuck under a right-side Dock.
- **Readiness wait before `write text`:** poll up to 4s for the session to render real text, then settle 1s. Adds ~2s latency per launch; accepted as the price of reliability with the kiro-cli-term wrapper (see BUG1/BUG2).

## Verification Evidence

All evidence in `.claude/verification/iterm-quick-launch/` (rounds prefixed `01–05`, `r2-`, `r3-`).

**Round 1** (before SC7/SC8 existed):
- `flowdeck test`: 11/11 pass — covers SC6 + SC4 helper.
- Auditor 1: SC1/SC3/SC4/SC5 PASS; SC2 FLAKY (1 of 2 — BUG1).

**Round 2** (after BUG1 fix attempt + SC7 placement):
- `flowdeck test`: 16/16 pass (adds wait-order, bounds-line, right-third math ×2, omit-bounds tests).
- Auditor 2: SC7 PASS (bounds {1176, 40, 1764, 1169} = exactly visible-width/3, flush right, full height); regression PASS (Quick Launch + collapsed Processes render). SC8 FAIL 0/3 — BUG2 (my wait loop itself crashed the script).

**Round 3** (after BUG2 fix, which I first functionally tested standalone — echo payload executed and shell-evaluated `$((40+2))` in the new window):
- `flowdeck test`: 16/16 pass.
- Auditor 3: **SC8 PASS 3/3** — pids 95753/97037/97803 all `codex --yolo` with `lsof` cwd `/Users/eugenechan/dev/inbox`, windows all {1176, 40, 1764, 1169}; bonus cy click PASS (pid 98525 `claude --dangerously-skip-permissions`, same cwd/bounds). Full log: `r3-06-results.txt`.

| SC | Verified by | Result |
|---|---|---|
| SC1 | Auditor 1 screenshot + AX ids | PASS |
| SC2 | Auditor 3, 3/3 clicks, pid + lsof cwd | PASS |
| SC3 | Auditors 1 & 3, pid + lsof cwd | PASS |
| SC4 | Unit tests + auditor 1 zoom (no Stop buttons in AX tree) | PASS |
| SC5 | Auditor 1 expand/collapse screenshots + AX | PASS |
| SC6 | 3 script-builder unit tests | PASS |
| SC7 | 2 bounds unit tests + auditor 2 measured frame | PASS |
| SC8 | Standalone script test + auditor 3, 3/3 | PASS |

## Bugs

- **BUG1 (auditor round 1, FIXED): `write text` race with kiro-cli-term shell wrapper.** The session's visible shell is a kiro-cli-term proxy that spawns a nested `/bin/zsh --login`; commands written during wrapper init are rendered but never executed (~1/3 of clicks). Also makes iTerm's `session.path` report `~` regardless of real cwd — `lsof -p <pid> -a -d cwd` is the authoritative probe. Fix: poll session contents until real text renders, settle 1s, then `write text`. Verified round 3 (3/3).
- **BUG2 (auditor round 2, FIXED): the BUG1 fix itself aborted the script.** Reading `contents of current session of newWindow` immediately after window creation raises AppleScript error -1728 (and can return `missing value`), killing the script before `write text` — 0/3 launches. Fix: reference the session via `current session of current tab of newWindow`, wrap the poll in `try`, guard `missing value`. Verified standalone + round 3.
