//
//  MacCommandCenterApp.swift
//  MacCommandCenter
//
//  Created by FlowDeck Studio on 21/10/25.
//

import SwiftUI

@main
struct MacCommandCenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
