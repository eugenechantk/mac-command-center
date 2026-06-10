//
//  MacCommandCenterTests.swift
//  MacCommandCenterTests
//

import XCTest

final class MacCommandCenterTests: XCTestCase {

    @MainActor
    @objc
    func testOverallStatusStartsIdle() {
        let model = CommandCenterModel(openCodexOnLaunch: false, startOpenClawOnLaunch: false)

        XCTAssertEqual(model.overallStatus, "Idle")
    }

    @MainActor
    @objc
    func testCodexDesktopRunningMakesOverallStatusActive() {
        let model = CommandCenterModel(openCodexOnLaunch: false, startOpenClawOnLaunch: false)

        model.codexDesktop = ManagedService(state: .running, summary: "pid 1")

        XCTAssertEqual(model.overallStatus, "Active")
    }

    @MainActor
    @objc
    func testKeepAwakeOnBatteryIsIndependentOfPowerToggle() {
        let model = CommandCenterModel(openCodexOnLaunch: false, startOpenClawOnLaunch: false)

        model.setKeepAwakeOnBattery(true)

        XCTAssertTrue(model.keepAwakeOnBattery)
        XCTAssertFalse(model.keepAwakeWhenPluggedIn)
    }

    @MainActor
    @objc
    func testBothAwakeTogglesCanBeEnabledTogether() {
        let model = CommandCenterModel(openCodexOnLaunch: false, startOpenClawOnLaunch: false)

        model.setKeepAwake(true)
        model.setKeepAwakeOnBattery(true)

        XCTAssertTrue(model.keepAwakeWhenPluggedIn)
        XCTAssertTrue(model.keepAwakeOnBattery)
    }

    @MainActor
    @objc
    func testDisablingPowerToggleDoesNotClearBatteryToggle() {
        let model = CommandCenterModel(openCodexOnLaunch: false, startOpenClawOnLaunch: false)

        model.setKeepAwake(true)
        model.setKeepAwakeOnBattery(true)
        model.setKeepAwake(false)

        XCTAssertFalse(model.keepAwakeWhenPluggedIn)
        XCTAssertTrue(model.keepAwakeOnBattery)
    }

    @objc
    func testITermLaunchScriptChangesDirectoryBeforeRunningCommand() {
        let script = TerminalLauncher.iTermScript(
            directory: "/Users/eugenechan/dev/inbox",
            command: "codexy",
            bounds: nil
        )

        XCTAssertTrue(script.contains("tell application \"iTerm\""))
        XCTAssertTrue(script.contains("write text \"cd '/Users/eugenechan/dev/inbox' && codexy\""))
    }

    @objc
    func testITermLaunchScriptQuotesDirectoryForShell() {
        let script = TerminalLauncher.iTermScript(
            directory: "/tmp/it's here",
            command: "cy",
            bounds: nil
        )

        XCTAssertTrue(script.contains("cd '/tmp/it'\\\\''s here' && cy"))
    }

    @objc
    func testITermLaunchScriptEscapesDoubleQuotesForAppleScript() {
        let script = TerminalLauncher.iTermScript(
            directory: "/tmp",
            command: "echo \"hi\"",
            bounds: nil
        )

        XCTAssertTrue(script.contains("write text \"cd '/tmp' && echo \\\"hi\\\"\""))
    }

    @objc
    func testITermLaunchScriptWaitsForPromptBeforeWriting() {
        let script = TerminalLauncher.iTermScript(
            directory: "/tmp",
            command: "cy",
            bounds: nil
        )

        let waitIndex = script.range(of: "contents of current session of current tab")?.lowerBound
        let writeIndex = script.range(of: "write text")?.lowerBound
        XCTAssertNotNil(waitIndex)
        XCTAssertNotNil(writeIndex)
        if let waitIndex, let writeIndex {
            XCTAssertLessThan(waitIndex, writeIndex)
        }
        // Early `contents` reads raise -1728; the poll must be try-guarded or the
        // whole script aborts before write text.
        XCTAssertTrue(script.contains("try"))
        XCTAssertTrue(script.contains("missing value"))
    }

    @objc
    func testITermLaunchScriptSetsWindowBoundsWhenProvided() {
        let script = TerminalLauncher.iTermScript(
            directory: "/tmp",
            command: "cy",
            bounds: WindowBounds(left: 1280, top: 25, right: 1920, bottom: 1080)
        )

        XCTAssertTrue(script.contains("set bounds of newWindow to {1280, 25, 1920, 1080}"))
    }

    @objc
    func testITermLaunchScriptOmitsBoundsWhenUnavailable() {
        let script = TerminalLauncher.iTermScript(directory: "/tmp", command: "cy", bounds: nil)

        XCTAssertFalse(script.contains("set bounds"))
    }

    @objc
    func testRightThirdBoundsCoverRightmostThirdOfVisibleFrame() {
        let bounds = TerminalLauncher.rightThirdBounds(
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            primaryScreenHeight: 1080
        )

        XCTAssertEqual(bounds, WindowBounds(left: 1280, top: 25, right: 1920, bottom: 1080))
    }

    @objc
    func testRightThirdBoundsAccountForDockInset() {
        // Visible frame raised off the screen bottom by a 70pt dock.
        let bounds = TerminalLauncher.rightThirdBounds(
            visibleFrame: CGRect(x: 0, y: 70, width: 1800, height: 985),
            primaryScreenHeight: 1080
        )

        XCTAssertEqual(bounds, WindowBounds(left: 1200, top: 25, right: 1800, bottom: 1010))
    }

    @objc
    func testCollapsedNamesDeduplicateWithCounts() {
        let processes = [
            ManagedProcess(pid: 1, command: "/usr/bin/caffeinate -dims"),
            ManagedProcess(pid: 2, command: "/usr/bin/caffeinate -i"),
            ManagedProcess(pid: 3, command: "openclaw gateway")
        ]

        XCTAssertEqual(
            ManagedProcess.collapsedNames(for: processes),
            ["Caffeinate ×2", "OpenClaw"]
        )
    }

    @objc
    func testCollapsedNamesEmptyForNoProcesses() {
        XCTAssertEqual(ManagedProcess.collapsedNames(for: []), [])
    }

    @MainActor
    @objc
    func testDisplayAwakeClearsOnlyWhenBothAwakeTogglesOff() {
        let model = CommandCenterModel(openCodexOnLaunch: false, startOpenClawOnLaunch: false)

        model.setKeepAwake(true)
        model.setKeepAwakeOnBattery(true)
        model.setKeepDisplayAwake(true)

        model.setKeepAwake(false)
        XCTAssertTrue(model.keepDisplayAwake)

        model.setKeepAwakeOnBattery(false)
        XCTAssertFalse(model.keepDisplayAwake)
    }
}
