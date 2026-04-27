//
//  MacCommandCenterUITestsLaunchTests.swift
//  MacCommandCenterUITests
//
//  Created by FlowDeck Studio on 21/10/25.
//

import XCTest

final class MacCommandCenterUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        throw XCTSkip("Phase 0 does not include menu bar launch screenshot automation yet.")
    }
}
