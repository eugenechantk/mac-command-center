//
//  AwakeController.swift
//  MacCommandCenter
//

import Foundation

@MainActor
final class AwakeController {
    private var process: Process?

    var isActive: Bool {
        process?.isRunning == true
    }

    var pid: Int32? {
        guard let process, process.isRunning else {
            return nil
        }
        return process.processIdentifier
    }

    func reconcile(enabled: Bool, keepDisplayAwake: Bool) {
        if enabled {
            start(keepDisplayAwake: keepDisplayAwake)
        } else {
            stop()
        }
    }

    func stop() {
        guard let process else {
            return
        }

        if process.isRunning {
            process.terminate()
        }
        self.process = nil
    }

    private func start(keepDisplayAwake: Bool) {
        let desiredArguments = keepDisplayAwake ? ["-s", "-d"] : ["-s"]

        if let process, process.isRunning, process.arguments == desiredArguments {
            return
        }

        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = desiredArguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                if self?.process === process {
                    self?.process = nil
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            self.process = nil
        }
    }
}
