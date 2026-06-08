//
//  CommandCenterModel.swift
//  MacCommandCenter
//

import Foundation
import Combine
import AppKit
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
    @Published var codexDesktop = ManagedService()
    @Published var openClaw = ManagedService()
    @Published var processes: [ManagedProcess] = []
    @Published var lastRefreshedAt: Date?
    @Published var isRefreshing = false

    private let awakeController = AwakeController()
    private var powerSourceMonitor: PowerSourceMonitor?

    init(openCodexOnLaunch: Bool = true, startOpenClawOnLaunch: Bool = true) {
        powerSourceMonitor = PowerSourceMonitor { [weak self] isExternalPowerConnected in
            Task { @MainActor in
                self?.setExternalPowerConnected(isExternalPowerConnected)
            }
        }

        if openCodexOnLaunch || startOpenClawOnLaunch {
            Task {
                if openCodexOnLaunch {
                    await openCodexDesktop()
                }

                if startOpenClawOnLaunch {
                    await startOpenClawGatewayIfNeeded()
                }

                await refreshStatuses()
            }
        }
    }

    var overallStatus: String {
        if codexDesktop.state == .error || openClaw.state == .error {
            return "Needs attention"
        }

        if keepAwakeWhenPluggedIn || codexDesktop.state == .running || openClaw.state == .running {
            return "Active"
        }

        return "Idle"
    }

    func refreshStatuses() async {
        isRefreshing = true
        async let codexStatus = CodexDesktopController.status()
        async let openClawResult = CommandRunner.run("/opt/homebrew/bin/openclaw", ["gateway", "status", "--json"])
        async let processResult = ProcessManager.listProcesses()

        setExternalPowerConnected(PowerSourceMonitor.isExternalPowerConnected())
        updateAwakeSummary()
        codexDesktop = await codexStatus
        openClaw = ServiceParser.openClawStatus(from: await openClawResult)
        processes = await processResult
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

    func toggleCodexDesktop() async {
        let shouldStop = codexDesktop.state == .running
        codexDesktop.isWorking = true
        _ = shouldStop ? await CodexDesktopController.stop() : await CodexDesktopController.start()
        codexDesktop.isWorking = false
        await refreshStatuses()
    }

    func toggleOpenClaw() async {
        let shouldStop = openClaw.state == .running
        openClaw.isWorking = true
        _ = await CommandRunner.run("/opt/homebrew/bin/openclaw", ["gateway", shouldStop ? "stop" : "start", "--json"])
        openClaw.isWorking = false
        await refreshStatuses()
    }

    func stopProcess(_ process: ManagedProcess) async {
        guard let index = processes.firstIndex(where: { $0.pid == process.pid }) else {
            return
        }

        processes[index].isStopping = true
        _ = await ProcessManager.stop(pid: process.pid)
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
        } else if !isExternalPowerConnected {
            awakeSummary = "Plug in power to apply"
        } else if keepAwakeWhenPluggedIn {
            awakeSummary = "Requested, but caffeinate is not running"
        } else {
            awakeSummary = "Off"
        }
    }

    private func openCodexDesktop() async {
        codexDesktop.isWorking = true
        _ = await CodexDesktopController.start()
        codexDesktop = await CodexDesktopController.status()
    }

    private func startOpenClawGatewayIfNeeded() async {
        openClaw.isWorking = true

        let statusResult = await CommandRunner.run("/opt/homebrew/bin/openclaw", ["gateway", "status", "--json"])
        let currentStatus = ServiceParser.openClawStatus(from: statusResult)

        if currentStatus.state == .running {
            openClaw = currentStatus
            return
        }

        _ = await CommandRunner.run("/opt/homebrew/bin/openclaw", ["gateway", "start", "--json"])
        openClaw.isWorking = false
    }
}

@MainActor
private enum CodexDesktopController {
    private static let appName = "Codex"
    private static let bundleIdentifier = "com.openai.codex"
    private static let appURL = URL(fileURLWithPath: "/Applications/Codex.app")

    static func status() -> ManagedService {
        if let application = runningApplication() {
            return ManagedService(state: .running, summary: "pid \(application.processIdentifier)")
        }

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            return ManagedService(state: .stopped, summary: "\(appName).app not installed")
        }

        return ManagedService(state: .stopped, summary: "App stopped")
    }

    static func start() async -> Bool {
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false

        let didOpen = await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { application, error in
                continuation.resume(returning: application != nil && error == nil)
            }
        }

        if didOpen || runningApplication() != nil {
            await settleWindowsClosed()
        }

        return didOpen
    }

    static func stop() async -> Bool {
        guard let application = runningApplication() else {
            return true
        }

        if !application.terminate() {
            application.forceTerminate()
        }

        try? await Task.sleep(for: .milliseconds(700))
        return runningApplication() == nil
    }

    private static func runningApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { application in
            application.bundleIdentifier == bundleIdentifier
                || application.localizedName == appName
        }
    }

    private static func settleWindowsClosed() async {
        for _ in 0..<16 {
            runningApplication()?.hide()
            await closeWindows()
            runningApplication()?.hide()
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private static func closeWindows() async {
        _ = await CommandRunner.run(
            "/usr/bin/osascript",
            [
                "-e",
                """
                tell application "System Events"
                    if exists process "Codex" then
                        tell process "Codex"
                            repeat with appWindow in windows
                                try
                                    perform action "AXPress" of button 1 of appWindow
                                end try
                            end repeat
                        end tell
                    end if
                end tell
                """
            ]
        )
        runningApplication()?.hide()
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
