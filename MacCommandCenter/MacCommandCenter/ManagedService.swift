//
//  ManagedService.swift
//  MacCommandCenter
//

import Foundation
import Darwin

struct ManagedService {
    var state: ServiceState = .unknown
    var summary = "Not checked"
    var isWorking = false
}

struct ManagedProcess: Identifiable, Equatable {
    let pid: Int32
    let command: String
    var isStopping = false

    var id: Int32 {
        pid
    }

    var displayName: String {
        if command.localizedCaseInsensitiveContains("cloudflared") {
            return "Cloudflared"
        }
        if command.localizedCaseInsensitiveContains("cloudflare") {
            return "Cloudflare"
        }
        if command.localizedCaseInsensitiveContains("openclaw") {
            return "OpenClaw"
        }
        if command.localizedCaseInsensitiveContains("caffeinate") {
            return "Caffeinate"
        }
        let executable = command.split(separator: " ").first.map(String.init) ?? ""
        return executable.isEmpty ? "Process \(pid)" : executable
    }

    var detail: String {
        "pid \(pid) - \(command)"
    }
}

enum ProcessManager {
    private static let processKeywords = [
        "openclaw",
        "cloudflare",
        "cloudflared",
        "caffeinate"
    ]

    static func listProcesses() async -> [ManagedProcess] {
        let result = await CommandRunner.run(
            "/usr/bin/pgrep",
            [
                "-U",
                String(getuid()),
                "-afil",
                processKeywords.joined(separator: "|")
            ]
        )
        guard result.succeeded else {
            return []
        }

        return result.stdout
            .split(separator: "\n")
            .compactMap { parseProcessLine(String($0)) }
            .filter { process in
                process.pid != ProcessInfo.processInfo.processIdentifier
                    && !process.command.localizedCaseInsensitiveContains("/usr/bin/pgrep")
                    && !process.command.localizedCaseInsensitiveContains("MacCommandCenter")
                    && processKeywords.contains { process.command.localizedCaseInsensitiveContains($0) }
            }
            .sorted { lhs, rhs in
                if lhs.displayName == rhs.displayName {
                    return lhs.pid < rhs.pid
                }
                return lhs.displayName < rhs.displayName
            }
    }

    static func stop(pid: Int32) async -> Bool {
        let result = await CommandRunner.run("/bin/kill", ["-TERM", String(pid)])
        return result.succeeded
    }

    private static func parseProcessLine(_ line: String) -> ManagedProcess? {
        let pattern = #"^\s*(\d+)\s*(.*)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 3,
              let pidRange = Range(match.range(at: 1), in: line),
              let commandRange = Range(match.range(at: 2), in: line),
              let pid = Int32(line[pidRange]) else {
            return nil
        }

        let command = String(line[commandRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return nil
        }

        return ManagedProcess(
            pid: pid,
            command: command
        )
    }
}

enum ServiceParser {
    static func openClawStatus(from result: CommandResult) -> ManagedService {
        guard result.succeeded else {
            return ManagedService(state: .error, summary: cleanedError(from: result))
        }

        guard let json = jsonObject(from: result.stdout) else {
            return ManagedService(state: .unknown, summary: "Status output was not JSON")
        }

        let service = json["service"] as? [String: Any]
        let runtime = service?["runtime"] as? [String: Any]
        let runtimeState = runtime?["state"] as? String
        let runtimeStatus = runtime?["status"] as? String
        let pid = runtime?["pid"] as? Int
        let rpc = json["rpc"] as? [String: Any]
        let rpcOK = rpc?["ok"] as? Bool ?? false
        let gateway = json["gateway"] as? [String: Any]
        let port = gateway?["port"] as? Int

        if runtimeState == "running" || runtimeStatus == "running" || rpcOK {
            let parts = [
                pid.map { "pid \($0)" },
                port.map { "port \($0)" },
                rpcOK ? "RPC OK" : nil
            ].compactMap { $0 }
            return ManagedService(state: .running, summary: parts.joined(separator: ", "))
        }

        return ManagedService(state: .stopped, summary: "Gateway stopped")
    }

    private static func jsonObject(from string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func cleanedError(from result: CommandResult) -> String {
        let message = result.stderr.isEmpty ? result.stdout : result.stderr
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Command failed with exit code \(result.exitCode)" : trimmed
    }
}
