//
//  CommandCenterModel.swift
//  MacCommandCenter
//

import Foundation
import Combine

enum ServiceState: String, CaseIterable {
    case unknown = "Unknown"
    case running = "Running"
    case stopped = "Stopped"
    case error = "Error"

    var symbolName: String {
        switch self {
        case .unknown:
            "questionmark.circle"
        case .running:
            "checkmark.circle.fill"
        case .stopped:
            "pause.circle"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class CommandCenterModel: ObservableObject {
    @Published var keepAwakeWhenPluggedIn = false
    @Published var keepDisplayAwake = false
    @Published var awakeSummary = "Off"
    @Published var remodex = ManagedService()
    @Published var openClaw = ManagedService()
    @Published var lastRefreshedAt: Date?
    @Published var isRefreshing = false

    private let awakeController = AwakeController()

    var overallStatus: String {
        if remodex.state == .error || openClaw.state == .error {
            return "Needs attention"
        }

        if keepAwakeWhenPluggedIn || remodex.state == .running || openClaw.state == .running {
            return "Active"
        }

        return "Idle"
    }

    func refreshStatuses() async {
        isRefreshing = true
        async let remodexResult = CommandRunner.run("/opt/homebrew/bin/remodex", ["status", "--json"])
        async let openClawResult = CommandRunner.run("/opt/homebrew/bin/openclaw", ["gateway", "status", "--json"])

        updateAwakeSummary()
        remodex = ServiceParser.remodexStatus(from: await remodexResult)
        openClaw = ServiceParser.openClawStatus(from: await openClawResult)
        lastRefreshedAt = Date()
        isRefreshing = false
    }

    func setKeepAwake(_ enabled: Bool) {
        keepAwakeWhenPluggedIn = enabled
        if !enabled {
            keepDisplayAwake = false
        }
        reconcileAwake()
    }

    func setKeepDisplayAwake(_ enabled: Bool) {
        keepDisplayAwake = enabled
        reconcileAwake()
    }

    func toggleRemodex() async {
        let shouldStop = remodex.state == .running
        remodex.isWorking = true
        _ = await CommandRunner.run("/opt/homebrew/bin/remodex", [shouldStop ? "stop" : "start", "--json"])
        remodex.isWorking = false
        await refreshStatuses()
    }

    func toggleOpenClaw() async {
        let shouldStop = openClaw.state == .running
        openClaw.isWorking = true
        _ = await CommandRunner.run("/opt/homebrew/bin/openclaw", ["gateway", shouldStop ? "stop" : "start", "--json"])
        openClaw.isWorking = false
        await refreshStatuses()
    }

    func stopAwake() {
        awakeController.stop()
        updateAwakeSummary()
    }

    private func reconcileAwake() {
        awakeController.reconcile(enabled: keepAwakeWhenPluggedIn, keepDisplayAwake: keepDisplayAwake)
        updateAwakeSummary()
    }

    private func updateAwakeSummary() {
        if let pid = awakeController.pid {
            let mode = keepDisplayAwake ? "system + display + closed lid" : "system + closed lid"
            awakeSummary = "Active via caffeinate pid \(pid), \(mode)"
        } else if keepAwakeWhenPluggedIn {
            awakeSummary = "Requested, but caffeinate is not running"
        } else {
            awakeSummary = "Off"
        }
    }
}
