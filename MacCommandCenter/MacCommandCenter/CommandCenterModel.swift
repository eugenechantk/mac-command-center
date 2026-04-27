//
//  CommandCenterModel.swift
//  MacCommandCenter
//

import Foundation
import Combine
import IOKit.ps

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
    @Published var isExternalPowerConnected = PowerSourceMonitor.isExternalPowerConnected()
    @Published var remodex = ManagedService()
    @Published var openClaw = ManagedService()
    @Published var lastRefreshedAt: Date?
    @Published var isRefreshing = false

    private let awakeController = AwakeController()
    private var powerSourceMonitor: PowerSourceMonitor?

    init() {
        powerSourceMonitor = PowerSourceMonitor { [weak self] isExternalPowerConnected in
            Task { @MainActor in
                self?.setExternalPowerConnected(isExternalPowerConnected)
            }
        }
    }

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

        setExternalPowerConnected(PowerSourceMonitor.isExternalPowerConnected())
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
        awakeController.reconcile(enabled: keepAwakeWhenPluggedIn && isExternalPowerConnected, keepDisplayAwake: keepDisplayAwake)
        updateAwakeSummary()
    }

    private func setExternalPowerConnected(_ isConnected: Bool) {
        guard isExternalPowerConnected != isConnected else {
            return
        }

        isExternalPowerConnected = isConnected
        reconcileAwake()
    }

    private func updateAwakeSummary() {
        if let pid = awakeController.pid {
            let mode = keepDisplayAwake ? "system + display + closed lid" : "system + closed lid"
            awakeSummary = "Active via caffeinate pid \(pid), \(mode)"
        } else if keepAwakeWhenPluggedIn, !isExternalPowerConnected {
            awakeSummary = "Paused until power is connected"
        } else if keepAwakeWhenPluggedIn {
            awakeSummary = "Requested, but caffeinate is not running"
        } else if !isExternalPowerConnected {
            awakeSummary = "Plug in power to enable"
        } else {
            awakeSummary = "Off"
        }
    }
}

private final class PowerSourceMonitor {
    private let onChange: (Bool) -> Void
    private var runLoopSource: CFRunLoopSource?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        start()
    }

    deinit {
        stop()
    }

    static func isExternalPowerConnected() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSourceType = IOPSGetProvidingPowerSourceType(snapshot).takeUnretainedValue()
        return powerSourceType == kIOPMACPowerKey as CFString
    }

    fileprivate func handlePowerSourceChange() {
        onChange(Self.isExternalPowerConnected())
    }

    private func start() {
        guard runLoopSource == nil,
              let source = IOPSNotificationCreateRunLoopSource(
                powerSourceCallback,
                Unmanaged.passUnretained(self).toOpaque()
              )?.takeRetainedValue() else {
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    private func stop() {
        guard let runLoopSource else {
            return
        }

        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.runLoopSource = nil
    }
}

private let powerSourceCallback: IOPowerSourceCallbackType = { context in
    guard let context else {
        return
    }

    let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.handlePowerSourceChange()
}
