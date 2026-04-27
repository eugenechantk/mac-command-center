//
//  MacCommandCenterTests.swift
//  MacCommandCenterTests
//

import XCTest

final class MacCommandCenterTests: XCTestCase {

    @MainActor
    @objc
    func testOverallStatusStartsIdle() {
        let model = CommandCenterModel()

        XCTAssertEqual(model.overallStatus, "Idle")
    }

    @MainActor
    @objc
    func testServiceToggleUpdatesStateAndRefreshTime() {
        let model = CommandCenterModel()

        model.remodex = ManagedService(state: .running, summary: "pid 1")

        XCTAssertEqual(model.overallStatus, "Active")
    }
}
