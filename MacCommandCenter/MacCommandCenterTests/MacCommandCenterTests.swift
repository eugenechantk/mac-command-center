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
}
