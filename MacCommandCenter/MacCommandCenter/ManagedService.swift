//
//  ManagedService.swift
//  MacCommandCenter
//

import Foundation

struct ManagedService {
    var state: ServiceState = .unknown
    var summary = "Not checked"
    var isWorking = false
}

enum ServiceParser {
    static func remodexStatus(from result: CommandResult) -> ManagedService {
        guard result.succeeded else {
            return ManagedService(state: .error, summary: cleanedError(from: result))
        }

        guard let json = jsonObject(from: result.stdout) else {
            return ManagedService(state: .unknown, summary: "Status output was not JSON")
        }

        let installed = json["installed"] as? Bool ?? false
        let loaded = json["launchdLoaded"] as? Bool ?? false
        let launchdPid = json["launchdPid"] as? Int
        let bridgeStatus = json["bridgeStatus"] as? [String: Any]
        let state = bridgeStatus?["state"] as? String
        let connection = bridgeStatus?["connectionStatus"] as? String
        let bridgePid = bridgeStatus?["pid"] as? Int

        guard installed else {
            return ManagedService(state: .stopped, summary: "Service not installed")
        }

        if loaded, state == "running" || launchdPid != nil || bridgePid != nil {
            let pid = bridgePid ?? launchdPid
            let suffix = [pid.map { "pid \($0)" }, connection].compactMap { $0 }.joined(separator: ", ")
            return ManagedService(state: .running, summary: suffix.isEmpty ? "Running" : suffix)
        }

        return ManagedService(state: .stopped, summary: "Service stopped")
    }

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
