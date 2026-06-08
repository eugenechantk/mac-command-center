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
