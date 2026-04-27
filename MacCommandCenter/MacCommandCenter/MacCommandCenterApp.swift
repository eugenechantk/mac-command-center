//
//  MacCommandCenterApp.swift
//  MacCommandCenter
//
//  Created by FlowDeck Studio on 21/10/25.
//

import SwiftUI

@main
struct MacCommandCenterApp: App {
    @StateObject private var model = CommandCenterModel()

    var body: some Scene {
        MenuBarExtra("Mac Command Center", systemImage: "command.circle") {
            CommandCenterPanel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
