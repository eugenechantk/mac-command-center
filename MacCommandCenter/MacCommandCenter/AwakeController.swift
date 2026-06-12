//
//  AwakeController.swift
//  MacCommandCenter
//

import Foundation
import IOKit
import IOKit.pwr_mgt

@MainActor
final class AwakeController {
    private let clamshellSleepSelector: UInt32 = 12

    private var process: Process?
    private var clamshellSleepDisabled = false
    private var clamshellNotificationPort: IONotificationPortRef?
    private var clamshellRunLoopSource: CFRunLoopSource?
    private var clamshellNotifier: io_object_t = IO_OBJECT_NULL
    private var clamshellRootDomain: io_service_t = IO_OBJECT_NULL
    private var sleepDisplaysOnLidClose = false

    init() {
        setClamshellSleepDisabled(false, force: true)
    }

    var isActive: Bool {
        process?.isRunning == true
    }

    var isClosedLidAwakeActive: Bool {
        clamshellSleepDisabled
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
            setClamshellSleepDisabled(true)
            configureLidMonitor(sleepDisplaysOnClose: !keepDisplayAwake)
        } else {
            stop()
        }
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        self.process = nil
        stopClamshellNotifications()
        setClamshellSleepDisabled(false, force: true)
    }

    private func start(keepDisplayAwake: Bool) {
        let appPID = String(ProcessInfo.processInfo.processIdentifier)
        // -i (prevent idle sleep) is honored on battery; -s (prevent system sleep) only on AC.
        // Both are needed so closed-lid keep-awake survives on battery power.
        let desiredArguments = keepDisplayAwake ? ["-i", "-s", "-d", "-w", appPID] : ["-i", "-s", "-w", appPID]

        if let process, process.isRunning, process.arguments == desiredArguments {
            return
        }

        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = desiredArguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            let processID = process.processIdentifier
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    if self?.process?.processIdentifier == processID {
                        self?.process = nil
                    }
                }
            }
            self.process = process
        } catch {
            self.process = nil
        }
    }

    private func sleepDisplaysNow() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            // Best effort: caffeinate still keeps the system awake if display sleep cannot be requested.
        }
    }

    private func configureLidMonitor(sleepDisplaysOnClose: Bool) {
        sleepDisplaysOnLidClose = sleepDisplaysOnClose
        startClamshellNotificationsIfNeeded()

        guard let lidClosed = isLidClosed() else {
            return
        }

        if lidClosed, sleepDisplaysOnClose {
            sleepDisplaysNow()
        }
    }

    private func startClamshellNotificationsIfNeeded() {
        guard clamshellNotificationPort == nil else {
            return
        }

        let rootDomain = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard rootDomain != IO_OBJECT_NULL else {
            return
        }

        guard let notificationPort = IONotificationPortCreate(kIOMainPortDefault),
              let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue() else {
            IOObjectRelease(rootDomain)
            return
        }

        var notifier: io_object_t = IO_OBJECT_NULL
        let result = IOServiceAddInterestNotification(
            notificationPort,
            rootDomain,
            kIOGeneralInterest,
            clamshellInterestCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &notifier
        )

        guard result == kIOReturnSuccess else {
            IONotificationPortDestroy(notificationPort)
            IOObjectRelease(rootDomain)
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        clamshellNotificationPort = notificationPort
        clamshellRunLoopSource = runLoopSource
        clamshellNotifier = notifier
        clamshellRootDomain = rootDomain
    }

    private func stopClamshellNotifications() {
        if let runLoopSource = clamshellRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if clamshellNotifier != IO_OBJECT_NULL {
            IOObjectRelease(clamshellNotifier)
            clamshellNotifier = IO_OBJECT_NULL
        }

        if let notificationPort = clamshellNotificationPort {
            IONotificationPortDestroy(notificationPort)
        }

        if clamshellRootDomain != IO_OBJECT_NULL {
            IOObjectRelease(clamshellRootDomain)
            clamshellRootDomain = IO_OBJECT_NULL
        }

        clamshellNotificationPort = nil
        clamshellRunLoopSource = nil
        sleepDisplaysOnLidClose = false
    }

    fileprivate func handleClamshellStateChange(flags: UInt) {
        let lidClosed = flags & UInt(kClamshellStateBit) != 0
        if lidClosed, sleepDisplaysOnLidClose {
            sleepDisplaysNow()
        }
    }

    private func isLidClosed() -> Bool? {
        let rootEntry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard rootEntry != IO_OBJECT_NULL else {
            return nil
        }
        defer {
            IOObjectRelease(rootEntry)
        }

        let property = IORegistryEntryCreateCFProperty(
            rootEntry,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()

        return property as? Bool
    }

    private func setClamshellSleepDisabled(_ disabled: Bool, force: Bool = false) {
        guard force || clamshellSleepDisabled != disabled else {
            return
        }

        let connection = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard connection != IO_OBJECT_NULL else {
            return
        }
        defer {
            IOServiceClose(connection)
        }

        var input: [UInt64] = [disabled ? 1 : 0]
        var outputCount: UInt32 = 0
        let result = IOConnectCallScalarMethod(
            connection,
            clamshellSleepSelector,
            &input,
            UInt32(input.count),
            nil,
            &outputCount
        )

        if result == kIOReturnSuccess {
            clamshellSleepDisabled = disabled
        }
    }
}

private let clamshellInterestCallback: IOServiceInterestCallback = { refCon, _, messageType, messageArgument in
    guard messageType == ioPMMessageClamshellStateChange,
          let refCon,
          let messageArgument else {
        return
    }

    let controller = Unmanaged<AwakeController>.fromOpaque(refCon).takeUnretainedValue()
    let flags = UInt(bitPattern: messageArgument)
    Task { @MainActor in
        controller.handleClamshellStateChange(flags: flags)
    }
}

// Swift does not import this macro from IOPM.h:
// iokit_family_msg(sub_iokit_powermanagement, 0x100).
private let ioPMMessageClamshellStateChange: UInt32 = 0xE0034100
