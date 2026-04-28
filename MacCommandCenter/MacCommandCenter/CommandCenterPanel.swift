//
//  CommandCenterPanel.swift
//  MacCommandCenter
//

import SwiftUI
import CoreImage.CIFilterBuiltins

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

            processesSection

            Divider()

            footerActions
        }
        .padding(16)
        .frame(width: 380)
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
                .accessibilityIdentifier("keep_awake_toggle")

            Toggle(
                "Keep Display Awake",
                isOn: Binding(
                    get: { model.keepDisplayAwake },
                    set: { model.setKeepDisplayAwake($0) }
                )
            )
                .disabled(!model.keepAwakeWhenPluggedIn)
                .accessibilityIdentifier("keep_display_awake_toggle")

            Text(model.awakeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var servicesSection: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
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

                if let pairing = model.remodex.pairing {
                    PairingQRCodeView(pairing: pairing)
                        .padding(.leading, 28)
                }
            }

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

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Processes")
                .font(.subheadline)
                .fontWeight(.medium)

            if model.processes.isEmpty {
                Text("No managed processes found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.processes) { process in
                            ProcessRow(process: process) {
                                Task {
                                    await model.stopProcess(process)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 160)
            }
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

private struct ProcessRow: View {
    let process: ManagedProcess
    let stopAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(process.displayName)
                    .font(.caption)
                Text(process.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(process.isStopping ? "Stopping" : "Stop", action: stopAction)
                .controlSize(.small)
                .disabled(process.isStopping)
                .accessibilityIdentifier("stop_process_\(process.pid)_button")
        }
    }
}

private struct PairingQRCodeView: View {
    let pairing: ServicePairing

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let image = QRCodeRenderer.image(from: pairing.qrPayload) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityLabel("Remodex pairing QR code")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Scan to connect")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let code = pairing.code {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let expiresAt = pairing.expiresAt {
                    Text("Expires \(expiresAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private enum QRCodeRenderer {
    private static let context = CIContext()
    private static let filter = CIFilter.qrCodeGenerator()

    static func image(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 96, height: 96))
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
