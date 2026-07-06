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
        if command.localizedCaseInsensitiveContains("hermes") {
            return "Hermes Agent"
        }
        if command.localizedCaseInsensitiveContains("serve-forever")
            || command.localizedCaseInsensitiveContains("cli.ts serve") {
            return "lfg Server"
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

    static func collapsedNames(for processes: [ManagedProcess]) -> [String] {
        var counts: [String: Int] = [:]
        var orderedNames: [String] = []
        for process in processes {
            let name = process.displayName
            if counts[name] == nil {
                orderedNames.append(name)
            }
            counts[name, default: 0] += 1
        }
        return orderedNames.map { name in
            let count = counts[name, default: 1]
            return count > 1 ? "\(name) ×\(count)" : name
        }
    }
}

enum ProcessManager {
    private static let processKeywords = [
        "hermes",
        "cloudflare",
        "cloudflared",
        "caffeinate",
        "serve-forever"
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
    /// Parse `lsof -nP -iTCP:<port> -sTCP:LISTEN` output. lsof exits non-zero
    /// when nothing is listening, so an empty result means "stopped", not an
    /// error; a data line means the server is up and its pid is column 2.
    static func lfgServerStatus(from result: CommandResult, port: Int) -> ManagedService {
        for line in result.stdout.split(separator: "\n") {
            if line.hasPrefix("COMMAND") { continue }   // header row
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            if columns.count >= 2, let pid = Int(columns[1]) {
                return ManagedService(state: .running, summary: "pid \(pid), port \(port)")
            }
        }
        return ManagedService(state: .stopped, summary: "Not serving on port \(port)")
    }

    static func hermesGatewayStatus(from result: CommandResult) -> ManagedService {
        guard result.succeeded else {
            return ManagedService(state: .error, summary: cleanedError(from: result))
        }

        if let pid = firstMatch(in: result.stdout, patterns: [
            #""PID"\s*=\s*(\d+)\s*;"#,
            #"PID\s+(\d+)"#
        ]) {
            return ManagedService(state: .running, summary: "pid \(pid)")
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.localizedCaseInsensitiveContains("not installed") {
            return ManagedService(state: .stopped, summary: "Gateway service not installed")
        }

        return ManagedService(state: .stopped, summary: "Gateway stopped")
    }

    private static func firstMatch(in string: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }

            let range = NSRange(string.startIndex..., in: string)
            guard let match = expression.firstMatch(in: string, range: range),
                  match.numberOfRanges >= 2,
                  let valueRange = Range(match.range(at: 1), in: string) else {
                continue
            }

            return String(string[valueRange])
        }

        return nil
    }

    private static func cleanedError(from result: CommandResult) -> String {
        let message = result.stderr.isEmpty ? result.stdout : result.stderr
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Command failed with exit code \(result.exitCode)" : trimmed
    }
}
