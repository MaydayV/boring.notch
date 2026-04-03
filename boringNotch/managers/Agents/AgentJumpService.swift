import Foundation

struct AgentJumpService {
    private enum TerminalAppKind {
        case iTerm2
        case appleTerminal
        case thirdParty(identifier: String)
        case unknown
    }

    private struct JumpDiagnostics {
        let appIdentifier: String
        let appKind: String
        let locatorSummary: String

        var description: String {
            "app=\(appIdentifier) kind=\(appKind) locators=\(locatorSummary)"
        }
    }

    enum JumpError: Error {
        case emptyCommand
    }

    func openInTerminal(_ session: AgentSessionMeta) async throws {
        let command = session.resumeCommand.trimmedNonEmpty ?? session.provider.resumeCommand(for: session.sessionId)
        guard let command = command.trimmedNonEmpty else {
            throw JumpError.emptyCommand
        }

        let finalCommand: String
        if let projectDir = session.projectDir?.trimmedNonEmpty {
            finalCommand = "cd \(projectDir.shellQuoted) && \(command)"
        } else {
            finalCommand = command
        }

        if let terminalContext = session.terminalContext {
            let appKind = classifyTerminalApp(terminalContext.app)
            let diagnostics = JumpDiagnostics(
                appIdentifier: normalizeTerminalApp(terminalContext.app),
                appKind: appKindDescription(appKind),
                locatorSummary: locatorSummary(for: terminalContext)
            )

            switch appKind {
            case .iTerm2:
                if await tryJumpInITerm2(command: finalCommand, context: terminalContext) {
                    return
                }
            case .appleTerminal:
                if await tryJumpInTerminal(command: finalCommand, context: terminalContext) {
                    return
                }
            case .thirdParty(let identifier):
                // Keep the original terminal app in front when we do not have a direct locator bridge.
                _ = await activateTerminalApplication(identifier: identifier)
            case .unknown:
                break
            }

            if case .unknown = appKind, terminalContext.hasAnyLocator {
                if await tryJumpInITerm2(command: finalCommand, context: terminalContext) {
                    return
                }
                if await tryJumpInTerminal(command: finalCommand, context: terminalContext) {
                    return
                }
            }

            // Minimal diagnostic context stays available here for future error reporting without a logging system.
            _ = diagnostics
        }

        if await tryOpenITerm2(command: finalCommand) {
            return
        }
        if await openTerminalFallback(command: finalCommand, diagnostics: JumpDiagnostics(appIdentifier: "fallback", appKind: "open", locatorSummary: "none")) {
            return
        }
        _ = await openTerminalShellFallback(command: finalCommand, diagnostics: JumpDiagnostics(appIdentifier: "fallback", appKind: "shell", locatorSummary: "none"))
    }

    private func normalizeTerminalApp(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func classifyTerminalApp(_ value: String?) -> TerminalAppKind {
        let normalized = normalizeTerminalApp(value)
        guard !normalized.isEmpty else {
            return .unknown
        }
        if isItermApp(normalized) {
            return .iTerm2
        }
        if isAppleTerminalApp(normalized) {
            return .appleTerminal
        }
        return .thirdParty(identifier: normalized)
    }

    private func isItermApp(_ value: String) -> Bool {
        value.contains("iterm")
    }

    private func isAppleTerminalApp(_ value: String) -> Bool {
        value == "terminal"
            || value == "com.apple.terminal"
            || value == "apple terminal"
            || value.contains("apple_terminal")
            || value.contains("apple terminal")
    }

    private func appKindDescription(_ kind: TerminalAppKind) -> String {
        switch kind {
        case .iTerm2:
            return "iTerm2"
        case .appleTerminal:
            return "AppleTerminal"
        case .thirdParty(let identifier):
            return "thirdParty:\(identifier)"
        case .unknown:
            return "unknown"
        }
    }

    private func locatorSummary(for context: AgentTerminalContext) -> String {
        let parts = [
            context.sessionId?.trimmedNonEmpty.map { "session=\($0)" },
            context.tabId?.trimmedNonEmpty.map { "tab=\($0)" },
            context.windowId?.trimmedNonEmpty.map { "window=\($0)" },
            context.tty?.trimmedNonEmpty.map { "tty=\($0)" }
        ].compactMap { $0 }
        return parts.isEmpty ? "none" : parts.joined(separator: ",")
    }

    private func activateTerminalApplication(identifier: String) async -> Bool {
        let normalizedIdentifier = identifier.trimmedNonEmpty ?? identifier
        guard !normalizedIdentifier.isEmpty else {
            return false
        }

        let arguments: [String]
        if isBundleIdentifier(normalizedIdentifier) {
            arguments = ["-b", normalizedIdentifier]
        } else {
            arguments = ["-a", normalizedIdentifier]
        }

        if runProcess("/usr/bin/open", arguments: arguments) {
            return true
        }

        let escapedIdentifier = normalizedIdentifier.escapedForAppleScriptString
        let script = """
        tell application "\(escapedIdentifier)"
            activate
        end tell
        """
        return (try? await AppleScriptHelper.executeVoid(script)) != nil
    }

    private func isBundleIdentifier(_ value: String) -> Bool {
        value.contains(".") && !value.contains(" ")
    }

    private func tryJumpInITerm2(command: String, context: AgentTerminalContext) async -> Bool {
        let escapedCommand = command.escapedForAppleScriptString
        let targetSession = (context.sessionId ?? "").escapedForAppleScriptString
        let targetTTY = (context.tty ?? "").escapedForAppleScriptString
        let targetTab = (context.tabId ?? "").escapedForAppleScriptString
        let targetWindow = (context.windowId ?? "").escapedForAppleScriptString
        let script = """
        on fuzzyMatch(candidate, target)
            if target is "" then
                return false
            end if
            if candidate is target then
                return true
            end if
            if candidate contains target then
                return true
            end if
            if target contains candidate then
                return true
            end if
            return false
        end fuzzyMatch

        tell application "iTerm2"
            activate
            set targetSession to "\(targetSession)"
            set targetTTY to "\(targetTTY)"
            set targetTab to "\(targetTab)"
            set targetWindow to "\(targetWindow)"
            repeat with w in windows
                set windowMatches to true
                if targetWindow is not "" then
                    try
                        set windowMatches to my fuzzyMatch((id of w as text), targetWindow)
                    end try
                end if
                if windowMatches then
                    repeat with t in tabs of w
                        set tabMatches to true
                        if targetTab is not "" then
                            try
                                set tabMatches to my fuzzyMatch((id of t as text), targetTab)
                            end try
                        end if
                        if tabMatches then
                            repeat with s in sessions of t
                                set matchBySession to false
                                set matchByTTY to false
                                if targetSession is not "" then
                                    try
                                        set matchBySession to my fuzzyMatch((id of s as text), targetSession)
                                        if not matchBySession then
                                            set matchBySession to my fuzzyMatch((name of s as text), targetSession)
                                        end if
                                    end try
                                end if
                                if targetTTY is not "" then
                                    try
                                        set matchByTTY to my fuzzyMatch((tty of s as text), targetTTY)
                                    end try
                                end if
                                set matchByName to false
                                if targetSession is not "" then
                                    try
                                        if my fuzzyMatch((name of s as text), targetSession) then
                                            set matchByName to true
                                        end if
                                    end try
                                end if
                                if (targetSession is "" and targetTTY is "") or matchBySession or matchByTTY or matchByName then
                                    set current window to w
                                    set current tab of w to t
                                    tell s to write text "\(escapedCommand)"
                                    return "1"
                                end if
                            end repeat
                        end if
                    end repeat
                end if
            end repeat
        end tell
        return "0"
        """
        return await runBooleanAppleScript(script)
    }

    private func tryJumpInTerminal(command: String, context: AgentTerminalContext) async -> Bool {
        let escapedCommand = command.escapedForAppleScriptString
        let targetTTY = (context.tty ?? "").escapedForAppleScriptString
        let targetSession = (context.sessionId ?? "").escapedForAppleScriptString
        let targetTab = (context.tabId ?? "").escapedForAppleScriptString
        let targetWindow = (context.windowId ?? "").escapedForAppleScriptString
        let script = """
        on fuzzyMatch(candidate, target)
            if target is "" then
                return false
            end if
            if candidate is target then
                return true
            end if
            if candidate contains target then
                return true
            end if
            if target contains candidate then
                return true
            end if
            return false
        end fuzzyMatch

        tell application "Terminal"
            activate
            set targetTTY to "\(targetTTY)"
            set targetSession to "\(targetSession)"
            set targetTab to "\(targetTab)"
            set targetWindow to "\(targetWindow)"
            repeat with w in windows
                set windowMatches to true
                if targetWindow is not "" then
                    try
                        set windowMatches to my fuzzyMatch((id of w as text), targetWindow)
                    end try
                end if
                if windowMatches then
                    repeat with t in tabs of w
                        set tabMatches to true
                        if targetTab is not "" then
                            try
                                set tabMatches to my fuzzyMatch((id of t as text), targetTab)
                            end try
                        end if
                        if tabMatches then
                            set matchByTTY to false
                            set matchBySession to false
                            if targetTTY is not "" then
                                try
                                    if my fuzzyMatch((tty of t as text), targetTTY) then
                                        set matchByTTY to true
                                    end if
                                end try
                            end if
                            if targetSession is not "" then
                                try
                                    if my fuzzyMatch((custom title of t as text), targetSession) then
                                        set matchBySession to true
                                    end if
                                end try
                                if not matchBySession then
                                    try
                                        if my fuzzyMatch((name of t as text), targetSession) then
                                            set matchBySession to true
                                        end if
                                    end try
                                end if
                            end if
                            if (targetTTY is "" and targetSession is "") or matchByTTY or matchBySession then
                                set selected tab of w to t
                                do script "\(escapedCommand)" in t
                                return "1"
                            end if
                        end if
                    end repeat
                end if
            end repeat
        end tell
        return "0"
        """
        return await runBooleanAppleScript(script)
    }

    private func tryOpenITerm2(command: String) async -> Bool {
        let escapedCommand = command.escapedForAppleScriptString
        let script = """
        tell application "iTerm2"
            activate
            if (count of windows) is 0 then
                create window with default profile
            end if
            tell current session of current window
                write text "\(escapedCommand)"
            end tell
            return "1"
        end tell
        """
        return await runBooleanAppleScript(script)
    }

    private func openTerminalFallback(command: String, diagnostics: JumpDiagnostics) async -> Bool {
        let debugContext = diagnostics.description
        _ = debugContext
        let escapedCommand = command.escapedForAppleScriptString
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """
        return (try? await AppleScriptHelper.executeVoid(script)) != nil
    }

    private func openTerminalShellFallback(command: String, diagnostics: JumpDiagnostics) async -> Bool {
        let debugContext = diagnostics.description
        _ = debugContext
        let escapedCommand = command.escapedForAppleScriptString
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """
        _ = runProcess("/usr/bin/open", arguments: ["-a", "Terminal"])
        return runProcess("/usr/bin/osascript", arguments: ["-e", script])
    }

    private func runProcess(_ launchPath: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runBooleanAppleScript(_ script: String) async -> Bool {
        guard let descriptor = try? await AppleScriptHelper.execute(script) else {
            return false
        }
        if let value = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return value == "1" || value.caseInsensitiveCompare("true") == .orderedSame
        }
        return descriptor.int32Value != 0
    }
}

private extension String {
    var escapedForAppleScriptString: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
}
