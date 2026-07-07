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
    @Published var keepAwakeOnBattery = false
    @Published var awakeSummary = "Off"
    @Published var isExternalPowerConnected = PowerSourceMonitor.isExternalPowerConnected()
    @Published var hermesAgent = ManagedService()
    @Published var lfgServer = ManagedService()
    @Published var processes: [ManagedProcess] = []
    @Published var lastRefreshedAt: Date?
    @Published var isRefreshing = false

    private let awakeController = AwakeController()
    private var powerSourceMonitor: PowerSourceMonitor?

    init(startHermesOnLaunch: Bool = true, startLfgOnLaunch: Bool = true) {
        powerSourceMonitor = PowerSourceMonitor { [weak self] isExternalPowerConnected in
            Task { @MainActor in
                self?.setExternalPowerConnected(isExternalPowerConnected)
            }
        }

        if startHermesOnLaunch || startLfgOnLaunch {
            Task {
                if startHermesOnLaunch {
                    await startHermesGatewayIfNeeded()
                }

                if startLfgOnLaunch {
                    await startLfgServerIfNeeded()
                }

                await refreshStatuses()
            }
        }
    }

    var overallStatus: String {
        if hermesAgent.state == .error || lfgServer.state == .error {
            return "Needs attention"
        }

        if keepAwakeWhenPluggedIn || hermesAgent.state == .running || lfgServer.state == .running {
            return "Active"
        }

        return "Idle"
    }

    func refreshStatuses() async {
        isRefreshing = true
        async let hermesStatus = HermesGatewayController.status()
        async let lfgStatus = LfgServerController.status()
        async let processResult = ProcessManager.listProcesses()

        setExternalPowerConnected(PowerSourceMonitor.isExternalPowerConnected())
        updateAwakeSummary()
        hermesAgent = await hermesStatus
        lfgServer = await lfgStatus
        processes = await processResult
        lastRefreshedAt = Date()
        isRefreshing = false
    }

    func setKeepAwake(_ enabled: Bool) {
        keepAwakeWhenPluggedIn = enabled
        clearDisplayAwakeIfIdle()
        reconcileAwake()
    }

    func setKeepDisplayAwake(_ enabled: Bool) {
        keepDisplayAwake = enabled
        reconcileAwake()
    }

    func setKeepAwakeOnBattery(_ enabled: Bool) {
        keepAwakeOnBattery = enabled
        clearDisplayAwakeIfIdle()
        reconcileAwake()
    }

    private func clearDisplayAwakeIfIdle() {
        if !keepAwakeWhenPluggedIn && !keepAwakeOnBattery {
            keepDisplayAwake = false
        }
    }

    func toggleHermesAgent() async {
        let shouldStop = hermesAgent.state == .running
        hermesAgent.isWorking = true
        _ = shouldStop ? await HermesGatewayController.stop() : await HermesGatewayController.start()
        hermesAgent.isWorking = false
        await refreshStatuses()
    }

    func toggleLfgServer() async {
        let shouldStop = lfgServer.state == .running
        lfgServer.isWorking = true
        if shouldStop {
            _ = await LfgServerController.stop()
        } else {
            _ = await LfgServerController.start()
            // serve-forever needs a moment to bind the port before status reads true.
            try? await Task.sleep(for: .milliseconds(1200))
        }
        lfgServer.isWorking = false
        await refreshStatuses()
    }

    func restartLfgServer() async {
        lfgServer.isWorking = true
        _ = await LfgServerController.restart()
        // serve-forever respawns the child after its backoff (≈1s on a healthy
        // run); give it room to rebind the port before status reads true.
        try? await Task.sleep(for: .milliseconds(1800))
        lfgServer.isWorking = false
        await refreshStatuses()
    }

    func launchInboxTerminal(command: String) async {
        _ = await TerminalLauncher.launchITerm(
            directory: "/Users/eugenechan/dev/inbox",
            command: command
        )
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
        // Each power state has its own independent toggle.
        let shouldRun = isExternalPowerConnected ? keepAwakeWhenPluggedIn : keepAwakeOnBattery
        awakeController.reconcile(enabled: shouldRun, keepDisplayAwake: keepDisplayAwake)
        updateAwakeSummary()
    }

    private func setExternalPowerConnected(_ isConnected: Bool) {
        guard isExternalPowerConnected != isConnected else {
            return
        }

        isExternalPowerConnected = isConnected

        // Reverting to AC power clears the battery toggle so it does not silently
        // persist into the next unplug and keep draining the battery.
        if isConnected {
            keepAwakeOnBattery = false
            clearDisplayAwakeIfIdle()
        }

        reconcileAwake()
    }

    private func updateAwakeSummary() {
        if let pid = awakeController.pid {
            let mode = keepDisplayAwake ? "system + display + closed lid" : "system + closed lid"
            let power = isExternalPowerConnected ? "" : " (on battery)"
            awakeSummary = "Active via caffeinate pid \(pid), \(mode)\(power)"
        } else if isExternalPowerConnected {
            awakeSummary = keepAwakeWhenPluggedIn ? "Requested, but caffeinate is not running" : "Off"
        } else if keepAwakeOnBattery {
            awakeSummary = "Requested, but caffeinate is not running"
        } else {
            awakeSummary = "On battery — enable \"Keep Awake on Battery\" to stay awake"
        }
    }

    private func startHermesGatewayIfNeeded() async {
        hermesAgent.isWorking = true

        let currentStatus = await HermesGatewayController.status()

        if currentStatus.state == .running {
            hermesAgent = currentStatus
            hermesAgent.isWorking = false
            return
        }

        _ = await HermesGatewayController.start()
        hermesAgent = await HermesGatewayController.status()
        hermesAgent.isWorking = false
    }

    private func startLfgServerIfNeeded() async {
        lfgServer.isWorking = true

        let currentStatus = await LfgServerController.status()

        if currentStatus.state == .running {
            lfgServer = currentStatus
            lfgServer.isWorking = false
            return
        }

        _ = await LfgServerController.start()
        try? await Task.sleep(for: .milliseconds(1200))
        lfgServer = await LfgServerController.status()
        lfgServer.isWorking = false
    }
}

private enum HermesGatewayController {
    private static var executablePath: String? {
        [
            "\(NSHomeDirectory())/.local/bin/hermes",
            "/opt/homebrew/bin/hermes",
            "/usr/local/bin/hermes"
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func status() async -> ManagedService {
        guard let executablePath else {
            return ManagedService(state: .stopped, summary: "Hermes CLI not installed")
        }

        let result = await CommandRunner.run(executablePath, ["gateway", "status"])
        return ServiceParser.hermesGatewayStatus(from: result)
    }

    static func start() async -> Bool {
        guard let executablePath else {
            return false
        }

        let result = await CommandRunner.run(executablePath, ["gateway", "--accept-hooks", "start"])
        return result.succeeded
    }

    static func stop() async -> Bool {
        guard let executablePath else {
            return true
        }

        let result = await CommandRunner.run(executablePath, ["gateway", "stop"])
        return result.succeeded
    }
}

/// The lfg agent control-plane server. It serves HTTP/SSE on 127.0.0.1:8766
/// (loopback) and is run via `scripts/serve-forever.sh` (a foreground supervisor
/// that restarts the Bun server on crash). Start also exposes it on the tailnet
/// via `tailscale serve` (tailnet-only HTTPS at this machine's MagicDNS URL →
/// loopback:8766) so the iOS client can reach it; that mapping persists (`--bg`)
/// and is intentionally left in place on stop so a brief restart doesn't drop it.
/// Status is read from the port listener; start spawns the supervisor detached so
/// it survives this app; stop kills the supervisor (so it stops respawning) and
/// the server child.
private enum LfgServerController {
    // The lfg repo lives in iCloud Drive (synced across machines). Space + literal
    // ~ in the folder name are fine in a Swift string; shellQuoted() handles them.
    static let repoPath = "\(NSHomeDirectory())/Library/Mobile Documents/com~apple~CloudDocs/_Dev/personal/lfg"
    static let port = 8766

    static func status() async -> ManagedService {
        guard FileManager.default.fileExists(atPath: repoPath) else {
            return ManagedService(state: .stopped, summary: "lfg repo not found at \(repoPath)")
        }

        let result = await CommandRunner.run(
            "/usr/sbin/lsof",
            ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        )
        return ServiceParser.lfgServerStatus(from: result, port: port)
    }

    static func start() async -> Bool {
        guard FileManager.default.fileExists(atPath: repoPath) else {
            return false
        }

        // serve-forever.sh is a foreground supervisor. Launch it through a login
        // shell (so bun + the pinned version resolve from the user's PATH) and
        // detach it with nohup + background + disown so it keeps running after
        // this app — and this spawn call — returns.
        let script = "cd \(shellQuoted(repoPath)) && nohup bash scripts/serve-forever.sh >> /tmp/lfg-serve.log 2>&1 & disown"
        let result = await CommandRunner.run("/bin/zsh", ["-lc", script])

        // Expose lfg on the tailnet: `tailscale serve --bg <port>` proxies this
        // machine's MagicDNS HTTPS URL → 127.0.0.1:8766 (where lfg listens). This
        // is the reachability path for the iOS client — point it at
        // https://<magicdns>.ts.net. Tailnet-ONLY (`serve`, never `funnel`) since
        // the lfg API is unauthenticated. Idempotent; `--bg` persists across
        // reboots; left in place on stop. Runs via a login shell so `tailscale`
        // resolves on PATH. Needs the user set as Tailscale operator once
        // (`tailscale set --operator=$USER`) so it doesn't require sudo.
        _ = await CommandRunner.run(
            "/bin/zsh",
            ["-lc", "tailscale serve --bg \(port)"]
        )

        return result.succeeded
    }

    static func stop() async -> Bool {
        let uid = String(getuid())
        // Kill the supervisor first so it stops respawning the server, then the
        // server child. pkill exits non-zero when nothing matched — that's fine
        // for an idempotent stop, so we don't gate on success.
        _ = await CommandRunner.run("/usr/bin/pkill", ["-U", uid, "-f", "scripts/serve-forever.sh"])
        _ = await CommandRunner.run("/usr/bin/pkill", ["-U", uid, "-f", "src/cli.ts serve"])
        return true
    }

    /// Restart the Bun server so it picks up new code, the lightest way: if the
    /// serve-forever supervisor is alive, kill ONLY the Bun child — the
    /// supervisor respawns it after its backoff, so there's no supervisor
    /// teardown/relaunch and no second supervisor racing for the port. If the
    /// supervisor isn't running, fall back to a fresh start.
    static func restart() async -> Bool {
        let uid = String(getuid())
        let supervisor = await CommandRunner.run(
            "/usr/bin/pgrep",
            ["-U", uid, "-f", "scripts/serve-forever.sh"]
        )
        if supervisor.succeeded {
            _ = await CommandRunner.run("/usr/bin/pkill", ["-U", uid, "-f", "src/cli.ts serve"])
            return true
        }
        return await start()
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
