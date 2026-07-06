//
//  MacCommandCenterTests.swift
//  MacCommandCenterTests
//

import XCTest

final class MacCommandCenterTests: XCTestCase {

    @MainActor
    @objc
    func testOverallStatusStartsIdle() {
        let model = CommandCenterModel(startHermesOnLaunch: false, startLfgOnLaunch: false)

        XCTAssertEqual(model.overallStatus, "Idle")
    }

    @MainActor
    @objc
    func testHermesAgentRunningMakesOverallStatusActive() {
        let model = CommandCenterModel(startHermesOnLaunch: false, startLfgOnLaunch: false)

        model.hermesAgent = ManagedService(state: .running, summary: "pid 88428")

        XCTAssertEqual(model.overallStatus, "Active")
    }

    @MainActor
    @objc
    func testLfgServerRunningMakesOverallStatusActive() {
        let model = CommandCenterModel(startHermesOnLaunch: false, startLfgOnLaunch: false)

        model.lfgServer = ManagedService(state: .running, summary: "pid 91625, port 8766")

        XCTAssertEqual(model.overallStatus, "Active")
    }

    @objc
    func testLfgServerStatusParsesListeningPid() {
        let result = CommandResult(
            exitCode: 0,
            stdout: """
            COMMAND   PID       USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
            bun     91625 eugenechan    4u  IPv4 0x7d65671e3bdaeb5a      0t0  TCP 127.0.0.1:8766 (LISTEN)
            """,
            stderr: ""
        )

        let service = ServiceParser.lfgServerStatus(from: result, port: 8766)

        XCTAssertEqual(service.state, .running)
        XCTAssertEqual(service.summary, "pid 91625, port 8766")
    }

    @objc
    func testLfgServerStatusTreatsEmptyLsofAsStopped() {
        // lsof exits non-zero with no stdout when nothing is listening.
        let result = CommandResult(exitCode: 1, stdout: "", stderr: "")

        let service = ServiceParser.lfgServerStatus(from: result, port: 8766)

        XCTAssertEqual(service.state, .stopped)
        XCTAssertEqual(service.summary, "Not serving on port 8766")
    }

    @objc
    func testLfgProcessDisplayNameRecognizesSupervisor() {
        let process = ManagedProcess(pid: 82367, command: "bash scripts/serve-forever.sh")

        XCTAssertEqual(process.displayName, "lfg Server")
    }

    @MainActor
    @objc
    func testKeepAwakeOnBatteryIsIndependentOfPowerToggle() {
        let model = CommandCenterModel(startHermesOnLaunch: false, startLfgOnLaunch: false)

        model.setKeepAwakeOnBattery(true)

        XCTAssertTrue(model.keepAwakeOnBattery)
        XCTAssertFalse(model.keepAwakeWhenPluggedIn)
    }

    @MainActor
    @objc
    func testBothAwakeTogglesCanBeEnabledTogether() {
        let model = CommandCenterModel(startHermesOnLaunch: false, startLfgOnLaunch: false)

        model.setKeepAwake(true)
        model.setKeepAwakeOnBattery(true)

        XCTAssertTrue(model.keepAwakeWhenPluggedIn)
        XCTAssertTrue(model.keepAwakeOnBattery)
    }

    @MainActor
    @objc
    func testDisablingPowerToggleDoesNotClearBatteryToggle() {
        let model = CommandCenterModel(startHermesOnLaunch: false, startLfgOnLaunch: false)

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
            ManagedProcess(pid: 3, command: "/Users/eugenechan/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run")
        ]

        XCTAssertEqual(
            ManagedProcess.collapsedNames(for: processes),
            ["Caffeinate ×2", "Hermes Agent"]
        )
    }

    @objc
    func testHermesProcessDisplayNameRecognizesGatewayCommand() {
        let process = ManagedProcess(
            pid: 88428,
            command: "/Users/eugenechan/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run"
        )

        XCTAssertEqual(process.displayName, "Hermes Agent")
    }

    @objc
    func testHermesGatewayStatusParsesRunningPid() {
        let result = CommandResult(
            exitCode: 0,
            stdout: """
            Launchd plist: /Users/eugenechan/Library/LaunchAgents/ai.hermes.gateway.plist
            Service definition matches the current Hermes install
            Gateway service is loaded
            {
            \t"PID" = 88428;
            \t"Label" = "ai.hermes.gateway";
            };
            """,
            stderr: ""
        )

        let service = ServiceParser.hermesGatewayStatus(from: result)

        XCTAssertEqual(service.state, .running)
        XCTAssertEqual(service.summary, "pid 88428")
    }

    @objc
    func testHermesGatewayStatusTreatsLoadedWithoutPidAsStopped() {
        let result = CommandResult(
            exitCode: 0,
            stdout: """
            Launchd plist: /Users/eugenechan/Library/LaunchAgents/ai.hermes.gateway.plist
            Service definition matches the current Hermes install
            Gateway service is loaded
            {
            \t"Label" = "ai.hermes.gateway";
            };
            """,
            stderr: ""
        )

        let service = ServiceParser.hermesGatewayStatus(from: result)

        XCTAssertEqual(service.state, .stopped)
        XCTAssertEqual(service.summary, "Gateway stopped")
    }

    @objc
    func testHermesGatewayStatusReportsCommandFailure() {
        let result = CommandResult(exitCode: 1, stdout: "", stderr: "launchctl failed")

        let service = ServiceParser.hermesGatewayStatus(from: result)

        XCTAssertEqual(service.state, .error)
        XCTAssertEqual(service.summary, "launchctl failed")
    }

    @objc
    func testCollapsedNamesEmptyForNoProcesses() {
        XCTAssertEqual(ManagedProcess.collapsedNames(for: []), [])
    }

    @MainActor
    @objc
    func testDisplayAwakeClearsOnlyWhenBothAwakeTogglesOff() {
        let model = CommandCenterModel(startHermesOnLaunch: false, startLfgOnLaunch: false)

        model.setKeepAwake(true)
        model.setKeepAwakeOnBattery(true)
        model.setKeepDisplayAwake(true)

        model.setKeepAwake(false)
        XCTAssertTrue(model.keepDisplayAwake)

        model.setKeepAwakeOnBattery(false)
        XCTAssertFalse(model.keepDisplayAwake)
    }
}
