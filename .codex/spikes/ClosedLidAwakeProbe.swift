import Foundation
import IOKit
import IOKit.pwr_mgt

private let kPMSetClamshellSleepStateSelector: UInt32 = 12

enum ProbeError: Error, CustomStringConvertible {
    case powerManagementUnavailable
    case callFailed(IOReturn)

    var description: String {
        switch self {
        case .powerManagementUnavailable:
            return "IOPM root domain connection unavailable"
        case .callFailed(let code):
            return "IOConnectCallScalarMethod failed with IOReturn \(code)"
        }
    }
}

func setClamshellSleepDisabled(_ disabled: Bool) throws {
    let connection = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
    guard connection != IO_OBJECT_NULL else {
        throw ProbeError.powerManagementUnavailable
    }
    defer {
        IOServiceClose(connection)
    }

    var input: [UInt64] = [disabled ? 1 : 0]
    var outputCount: UInt32 = 0

    let result = IOConnectCallScalarMethod(
        connection,
        kPMSetClamshellSleepStateSelector,
        &input,
        UInt32(input.count),
        nil,
        &outputCount
    )

    guard result == kIOReturnSuccess else {
        throw ProbeError.callFailed(result)
    }
}

func usage() -> Never {
    fputs("Usage: ClosedLidAwakeProbe disable|enable|pulse\n", stderr)
    exit(64)
}

let command = CommandLine.arguments.dropFirst().first

do {
    switch command {
    case "disable":
        try setClamshellSleepDisabled(true)
        print("clamshell sleep disabled")
    case "enable":
        try setClamshellSleepDisabled(false)
        print("clamshell sleep enabled")
    case "pulse":
        try setClamshellSleepDisabled(true)
        print("clamshell sleep disabled for 5 seconds")
        sleep(5)
        try setClamshellSleepDisabled(false)
        print("clamshell sleep restored")
    default:
        usage()
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
