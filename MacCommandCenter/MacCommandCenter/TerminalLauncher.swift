//
//  TerminalLauncher.swift
//  MacCommandCenter
//

import AppKit
import Foundation

struct WindowBounds: Equatable {
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int
}

enum TerminalLauncher {
    @MainActor
    static func launchITerm(directory: String, command: String) async -> Bool {
        let result = await CommandRunner.run(
            "/usr/bin/osascript",
            ["-e", iTermScript(directory: directory, command: command, bounds: rightThirdOfMainScreen())]
        )
        return result.succeeded
    }

    static func iTermScript(directory: String, command: String, bounds: WindowBounds?) -> String {
        let shellCommand = "cd \(shellQuoted(directory)) && \(command)"
        let boundsLine = bounds.map {
            "\n    set bounds of newWindow to {\($0.left), \($0.top), \($0.right), \($0.bottom)}"
        } ?? ""
        // The shell may be wrapped (kiro-cli-term spawns a nested zsh); text written
        // during wrapper init is rendered but never executed. Wait for the prompt to
        // render real text, then settle before writing. Reading `contents` right after
        // window creation raises -1728 (and can be `missing value`), so the poll must
        // tolerate both without aborting the script.
        return """
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile)\(boundsLine)
            repeat with i from 1 to 40
                try
                    set sessionText to contents of current session of current tab of newWindow
                    if sessionText is not missing value then
                        if (count of words of sessionText) > 0 then exit repeat
                    end if
                end try
                delay 0.1
            end repeat
            delay 1
            tell current session of current tab of newWindow
                write text "\(appleScriptEscaped(shellCommand))"
            end tell
        end tell
        """
    }

    // AppleScript bounds use a top-left origin anchored to the primary screen;
    // AppKit frames use a bottom-left origin, hence the primaryScreenHeight flip.
    static func rightThirdBounds(visibleFrame: CGRect, primaryScreenHeight: CGFloat) -> WindowBounds {
        let width = (visibleFrame.width / 3).rounded()
        return WindowBounds(
            left: Int(visibleFrame.maxX - width),
            top: Int(primaryScreenHeight - visibleFrame.maxY),
            right: Int(visibleFrame.maxX),
            bottom: Int(primaryScreenHeight - visibleFrame.minY)
        )
    }

    @MainActor
    private static func rightThirdOfMainScreen() -> WindowBounds? {
        guard let screen = NSScreen.main, let primary = NSScreen.screens.first else {
            return nil
        }
        return rightThirdBounds(
            visibleFrame: screen.visibleFrame,
            primaryScreenHeight: primary.frame.maxY
        )
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
