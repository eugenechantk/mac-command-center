//
//  SettingsView.swift
//  MacCommandCenter
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("General") {
                Text("Phase 0 scaffold")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420, height: 180)
    }
}

#Preview {
    SettingsView()
}
