//
//  CommandCenterPanel.swift
//  MacCommandCenter
//

import SwiftUI

struct CommandCenterPanel: View {
    @ObservedObject var model: CommandCenterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            awakeSection

            Divider()

            servicesSection

            Divider()

            footerActions
        }
        .padding(16)
        .frame(width: 340)
        .task {
            await model.refreshStatuses()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "command.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mac Command Center")
                    .font(.headline)
                Text(model.overallStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await model.refreshStatuses()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help("Refresh status")
            .accessibilityIdentifier("refresh_status_button")
        }
    }

    private var awakeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Keep Awake When Plugged In",
                isOn: Binding(
                    get: { model.keepAwakeWhenPluggedIn },
                    set: { model.setKeepAwake($0) }
                )
            )
                .disabled(!model.isExternalPowerConnected)
                .accessibilityIdentifier("keep_awake_toggle")

            Toggle(
                "Keep Display Awake",
                isOn: Binding(
                    get: { model.keepDisplayAwake },
                    set: { model.setKeepDisplayAwake($0) }
                )
            )
                .disabled(!model.keepAwakeWhenPluggedIn || !model.isExternalPowerConnected)
                .accessibilityIdentifier("keep_display_awake_toggle")

            Text(model.awakeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var servicesSection: some View {
        VStack(spacing: 10) {
            ServiceStatusRow(
                title: "Remodex",
                service: model.remodex,
                actionTitle: model.remodex.state == .running ? "Stop" : "Start",
                action: {
                    Task {
                        await model.toggleRemodex()
                    }
                }
            )
            .accessibilityIdentifier("remodex_status_row")

            ServiceStatusRow(
                title: "OpenClaw",
                service: model.openClaw,
                actionTitle: model.openClaw.state == .running ? "Stop" : "Start",
                action: {
                    Task {
                        await model.toggleOpenClaw()
                    }
                }
            )
            .accessibilityIdentifier("openclaw_status_row")
        }
    }

    private var footerActions: some View {
        HStack {
            if let lastRefreshedAt = model.lastRefreshedAt {
                Text("Updated \(lastRefreshedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not refreshed yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit") {
                model.stopAwake()
                NSApplication.shared.terminate(nil)
            }
            .accessibilityIdentifier("quit_button")
        }
    }
}

private struct ServiceStatusRow: View {
    let title: String
    let service: ManagedService
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: service.isWorking ? "arrow.triangle.2.circlepath" : service.state.symbolName)
                .foregroundStyle(service.state == .running ? .green : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text("\(service.state.rawValue) - \(service.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(service.isWorking ? "Working" : actionTitle, action: action)
                .controlSize(.small)
                .disabled(service.isWorking)
                .accessibilityIdentifier("\(title.lowercased())_toggle_button")
        }
    }
}

#Preview {
    CommandCenterPanel(model: CommandCenterModel())
}
