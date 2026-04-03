import Foundation
import Darwin

enum AgentLocalization {
    static func text(_ key: String, comment: String = "") -> String {
        NSLocalizedString(key, comment: comment)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }
}

// MARK: - Providers

struct AgentProviderProfile {
    let provider: AgentProvider
    let displayName: String
    let commandName: String
    let resumeCommand: (String) -> String
    let scanRootPaths: [String]
    let allowedExtensions: Set<String>
}

enum AgentProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case codex
    case gemini
    case cursor
    case opencode
    case droid
    case openclaw

    var id: String { rawValue }

    static func resolved(from rawValue: String?) -> AgentProvider? {
        guard let rawValue = rawValue?.trimmedNonEmpty else { return nil }
        let normalized = normalizeLookupKey(rawValue)
        if let provider = AgentProvider(rawValue: normalized) {
            return provider
        }
        return aliasMap[normalized]?.provider
    }

    static func profile(for rawValue: String?) -> AgentProviderProfile? {
        guard let rawValue = rawValue?.trimmedNonEmpty else { return nil }
        let normalized = normalizeLookupKey(rawValue)
        if let provider = AgentProvider(rawValue: normalized) {
            return provider.profile
        }
        return aliasMap[normalized]
    }

    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .gemini:
            return "Gemini"
        case .cursor:
            return "Cursor"
        case .opencode:
            return "OpenCode"
        case .droid:
            return "Droid"
        case .openclaw:
            return "OpenClaw"
        }
    }

    var profile: AgentProviderProfile {
        AgentProviderProfile(
            provider: self,
            displayName: displayName,
            commandName: commandName,
            resumeCommand: resumeCommand(for:),
            scanRootPaths: scanRootPaths,
            allowedExtensions: allowedExtensions
        )
    }

    var commandName: String {
        switch self {
        case .claude:
            return "claude"
        case .codex:
            return "codex"
        case .gemini:
            return "gemini"
        case .cursor:
            return "cursor"
        case .opencode:
            return "opencode"
        case .droid:
            return "droid"
        case .openclaw:
            return "openclaw"
        }
    }

    private static let aliasMap: [String: AgentProviderProfile] = [
        "cursorai": AgentProvider.cursor.profile,
        "cursoragent": AgentProvider.cursor.profile,
        "cursorcli": AgentProvider.cursor.profile,
        "claudecode": AgentProvider.claude.profile,
        "anthropicclaude": AgentProvider.claude.profile,
        "codexcli": AgentProvider.codex.profile,
        "openaicodex": AgentProvider.codex.profile,
        "geminicli": AgentProvider.gemini.profile,
        "googlegemini": AgentProvider.gemini.profile,
        "droidagent": AgentProvider.droid.profile,
        "clawdroid": AgentProvider.droid.profile,
        "qoder": AgentProvider.opencode.profile
    ]

    func resumeCommand(for sessionId: String) -> String {
        let quotedSessionId = sessionId.shellQuoted
        switch self {
        case .claude:
            return "claude --resume \(quotedSessionId)"
        case .codex:
            return "codex resume \(quotedSessionId)"
        case .gemini:
            return "gemini --resume \(quotedSessionId)"
        case .cursor:
            return "cursor --resume \(quotedSessionId)"
        case .opencode:
            return "opencode resume \(quotedSessionId)"
        case .droid:
            return "droid resume \(quotedSessionId)"
        case .openclaw:
            return "openclaw agent --session-id \(quotedSessionId)"
        }
    }

    var scanRootPaths: [String] {
        switch self {
        case .claude:
            return [".claude/projects", ".claude/sessions"]
        case .codex:
            return [".codex/session_index.jsonl", ".codex/sessions", ".codex/archived_sessions"]
        case .gemini:
            return [".gemini/tmp", ".gemini/sessions", ".gemini/projects", ".gemini/projects.json", ".gemini/history", ".config/gemini-cli/sessions"]
        case .cursor:
            return [
                ".cursor/sessions",
                ".cursor/storage",
                ".config/cursor/sessions"
            ]
        case .opencode:
            return [
                ".local/share/opencode/opencode.db",
                ".local/share/opencode/storage/session",
                ".local/share/opencode/storage",
                ".config/opencode",
                ".opencode",
                ".qoder/sessions",
                ".config/qoder/sessions",
                ".local/share/qoder/sessions"
            ]
        case .droid:
            return [
                ".droid/sessions",
                ".config/droid/sessions",
                ".local/share/droid/sessions"
            ]
        case .openclaw:
            return [".openclaw/agents", ".openclaw/sessions", ".clawdbot/sessions"]
        }
    }

    var allowedExtensions: Set<String> {
        switch self {
        case .opencode:
            return ["json", "jsonl", "ndjson", "db", "sqlite", "sqlite3"]
        case .cursor, .droid, .openclaw:
            return ["json", "jsonl", "ndjson"]
        case .claude, .codex, .gemini:
            return ["json", "jsonl", "ndjson"]
        }
    }

    fileprivate static func normalizeLookupKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}

// MARK: - Session State

enum AgentSessionState: String, Codable, CaseIterable {
    case idle
    case running
    case waitingApproval
    case waitingQuestion
    case completed
    case failed
}

enum AgentActionKind: String, Codable, CaseIterable {
    case approve
    case deny
    case question
}

enum AgentResponseOutcome: String, Codable, CaseIterable {
    case approved
    case denied
    case answered
}

enum AgentApprovalMode: String, Codable, CaseIterable {
    case standard
    case alwaysAllow
    case bypass

    var responseMessage: String? {
        switch self {
        case .standard:
            return nil
        case .alwaysAllow:
            return "always_allow"
        case .bypass:
            return "bypass_sandbox"
        }
    }
}

enum AgentBridgeEventType: String, Codable, CaseIterable {
    case sessionStarted = "session.started"
    case sessionUpdated = "session.updated"
    case usageUpdated = "usage.updated"
    case actionRequested = "action.requested"
    case actionResolved = "action.resolved"
    case sessionCompleted = "session.completed"
    case sessionFailed = "session.failed"
    case actionResponded = "action.responded"
}

// MARK: - Models

struct AgentUsageSnapshot: Equatable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var estimatedCostUSD: Double?
    var turnCount: Int?
    var updatedAt: Date
}

struct AgentSubagentMeta: Equatable, Codable {
    var id: String
    var name: String?
    var role: String?
    var type: String?
    var parentThreadId: String?

    var displayName: String {
        name?.trimmedNonEmpty ?? role?.trimmedNonEmpty ?? id
    }
}

struct AgentTerminalContext: Equatable, Codable {
    var app: String?
    var sessionId: String?
    var tabId: String?
    var windowId: String?
    var tty: String?

    var hasAnyLocator: Bool {
        sessionId?.trimmedNonEmpty != nil
            || tabId?.trimmedNonEmpty != nil
            || windowId?.trimmedNonEmpty != nil
            || tty?.trimmedNonEmpty != nil
    }
}

struct AgentSessionMeta: Identifiable, Equatable {
    var id: String { "\(provider.rawValue)::\(sessionId)" }

    let provider: AgentProvider
    var sourceAlias: String? = nil
    var terminalContext: AgentTerminalContext? = nil
    let sessionId: String
    var title: String
    var summary: String?
    var projectDir: String?
    var createdAt: Date
    var lastActiveAt: Date
    var resumeCommand: String
    var sourcePath: String
    var state: AgentSessionState
    var usage: AgentUsageSnapshot?
    var pendingActionCount: Int
    var subagent: AgentSubagentMeta?
    var childSubagents: [AgentSubagentMeta]
}

struct AgentActionRequest: Identifiable, Equatable {
    var id: String { requestId }

    let requestId: String
    let provider: AgentProvider
    var sourceAlias: String? = nil
    let sessionId: String
    var kind: AgentActionKind
    var title: String?
    var message: String?
    var details: String?
    var options: [String]
    var projectDir: String?
    var createdAt: Date
    var updatedAt: Date
    var sourcePath: String?
    var isResolved: Bool
    var resolvedAt: Date?
    var subagent: AgentSubagentMeta?
}

struct AgentTodayUsageSummary: Equatable {
    var sessionCount: Int
    var runningSessionCount: Int
    var pendingActionCount: Int
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var estimatedCostUSD: Double
    var updatedAt: Date
}

struct AgentScanDeniedRoot: Identifiable, Equatable {
    var id: String { "\(provider.rawValue)::\(rootPath)" }

    let provider: AgentProvider
    let rootPath: String
    let requiresSecurityScope: Bool
}

struct AgentScanReport: Equatable {
    var sessions: [AgentSessionMeta]
    var deniedRoots: [AgentScanDeniedRoot]
}

struct AgentSessionDiagnosticItem: Codable {
    let id: String
    let provider: String
    let sourceAlias: String?
    let sessionId: String
    let title: String
    let state: String
    let pendingActionCount: Int
    let projectDir: String?
    let sourcePath: String
    let lastActiveAt: Date
    let terminalApp: String?
    let terminalSessionId: String?
    let terminalTabId: String?
    let terminalWindowId: String?
    let terminalTTY: String?
}

struct AgentPendingActionDiagnosticItem: Codable {
    let requestId: String
    let provider: String
    let sourceAlias: String?
    let sessionId: String
    let kind: String
    let title: String?
    let message: String?
    let details: String?
    let options: [String]
    let createdAt: Date
    let updatedAt: Date
    let isResolved: Bool
}

struct AgentHookProviderDiagnosticItem: Codable {
    let provider: String
    let supportState: String
    let cliAvailable: Bool
    let hookInstalled: Bool
    let configPath: String
}

struct AgentDiagnosticsSnapshot: Codable {
    let generatedAt: Date
    let isRefreshing: Bool
    let lastRefreshAt: Date?
    let eventFilePath: String
    let responseFilePath: String
    let bridgeCommandPath: String
    let todaySessionCount: Int
    let todayRunningSessionCount: Int
    let todayPendingActionCount: Int
    let todayInputTokens: Int
    let todayOutputTokens: Int
    let todayTotalTokens: Int
    let todayEstimatedCostUSD: Double
    let scanDeniedRoots: [String]
    let sessions: [AgentSessionDiagnosticItem]
    let pendingActions: [AgentPendingActionDiagnosticItem]
    let hooks: [AgentHookProviderDiagnosticItem]
}

struct AgentActionResponseEnvelope: Codable {
    let schemaVersion: Int
    let event: String
    let provider: AgentProvider
    let sessionId: String
    let requestId: String
    let outcome: AgentResponseOutcome
    let message: String?
    let timestamp: Date
    let machineLocalOnly: Bool
    let projectDir: String?
    let sourcePath: String?

    init(
        provider: AgentProvider,
        sessionId: String,
        requestId: String,
        outcome: AgentResponseOutcome,
        message: String?,
        projectDir: String?,
        sourcePath: String?
    ) {
        schemaVersion = 1
        event = AgentBridgeEventType.actionResponded.rawValue
        self.provider = provider
        self.sessionId = sessionId
        self.requestId = requestId
        self.outcome = outcome
        self.message = message
        timestamp = Date()
        machineLocalOnly = true
        self.projectDir = projectDir
        self.sourcePath = sourcePath
    }
}

struct AgentBridgeEvent {
    let schemaVersion: Int?
    let type: AgentBridgeEventType?
    let provider: AgentProvider
    let sourceIdentifier: String?
    let sessionId: String
    let requestId: String?
    let timestamp: Date
    let payload: [String: Any]
    let subagent: AgentSubagentMeta?
}

enum AgentRuntimePaths {
    static var sandboxHomeDirectoryURL: URL { AgentPathResolver.sandboxHomeDirectoryURL.standardizedFileURL }
    static var realHomeDirectoryURL: URL { AgentPathResolver.realHomeDirectoryURL.standardizedFileURL }

    static var requiresRealHomeSecurityScope: Bool {
        AgentPathResolver.requiresRealHomeSecurityScope
    }

    static var bridgeDirectoryURL: URL {
        AgentHookPaths.bridgeDirectoryURL
    }

    static var bridgeCommandURL: URL {
        AgentHookPaths.bridgeCommandURL
    }

    static var supportDirectoryURL: URL {
        AgentHookPaths.supportDirectoryURL
    }

    static func providerConfigFileName(for provider: AgentProvider) -> String? {
        AgentPathResolver.providerConfigFileName(for: provider)
    }

    static func providerHiddenDirectoryName(for provider: AgentProvider) -> String? {
        AgentPathResolver.providerHiddenDirectoryName(for: provider)
    }

    static func defaultHookConfigURL(for provider: AgentProvider) -> URL? {
        AgentPathResolver.defaultHookConfigURL(for: provider)
    }

    static func defaultAuthorizationRootURL(for provider: AgentProvider) -> URL? {
        AgentPathResolver.defaultAuthorizationRootURL(for: provider)
    }

    static func displayScanPaths(for provider: AgentProvider) -> [String] {
        AgentPathResolver.displayScanPaths(for: provider)
    }

    static func resolvedHookConfigURL(for provider: AgentProvider, bookmarkRoot: URL) -> URL? {
        AgentPathResolver.resolvedHookConfigURL(for: provider, bookmarkRoot: bookmarkRoot)
    }
}

// MARK: - JSON Helpers

extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var shellQuoted: String {
        if isEmpty {
            return "''"
        }
        return "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension Dictionary where Key == String, Value == Any {
    func strictStringValue(for keys: [String]) -> String? {
        for key in keys {
            guard let resolved = self[key] else { continue }
            if let string = resolved as? String, let trimmed = string.trimmedNonEmpty {
                return trimmed
            }
            if let value = resolved as? Int {
                return "\(value)"
            }
            if let value = resolved as? Int64 {
                return "\(value)"
            }
            if let value = resolved as? Double {
                return "\(value)"
            }
            if let value = resolved as? NSNumber {
                return value.stringValue.trimmedNonEmpty
            }
        }
        return nil
    }

    func stringValue(for keys: [String]) -> String? {
        for key in keys {
            guard let resolved = rawValue(for: key) else { continue }
            if let string = resolved as? String, let trimmed = string.trimmedNonEmpty {
                return trimmed
            }
            if resolved is [String: Any] || resolved is [Any] {
                continue
            }
            if let value = resolved as? CustomStringConvertible {
                let string = value.description
                if let trimmed = string.trimmedNonEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    func intValue(for keys: [String]) -> Int? {
        for key in keys {
            guard let resolved = rawValue(for: key) else { continue }
            if let value = resolved as? Int {
                return value
            }
            if let value = resolved as? Int64 {
                return Int(value)
            }
            if let value = resolved as? Double {
                return Int(value)
            }
            if let value = resolved as? NSNumber {
                return value.intValue
            }
            if let value = resolved as? String, let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return number
            }
        }
        return nil
    }

    func doubleValue(for keys: [String]) -> Double? {
        for key in keys {
            guard let resolved = rawValue(for: key) else { continue }
            if let value = resolved as? Double {
                return value
            }
            if let value = resolved as? Int {
                return Double(value)
            }
            if let value = resolved as? Int64 {
                return Double(value)
            }
            if let value = resolved as? NSNumber {
                return value.doubleValue
            }
            if let value = resolved as? String {
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let number = Double(cleaned) {
                    return number
                }
            }
        }
        return nil
    }

    func dateValue(for keys: [String]) -> Date? {
        for key in keys {
            if let date = AgentDateParser.parse(rawValue(for: key)) {
                return date
            }
        }
        return nil
    }

    func nestedDictionaries(for keys: [String]) -> [[String: Any]] {
        var nested: [[String: Any]] = []
        for key in keys {
            if let dictionary = self[key] as? [String: Any] {
                nested.append(dictionary)
            } else if let array = self[key] as? [Any] {
                nested.append(contentsOf: array.compactMap { $0 as? [String: Any] })
            }
        }
        return nested
    }

    private func rawValue(for key: String) -> Any? {
        let normalizedKey = Self.normalizeLookupKey(key)
        return Self.findValue(for: normalizedKey, in: self, depth: 0)
    }

    private static func findValue(for normalizedKey: String, in dictionary: [String: Any], depth: Int) -> Any? {
        for (candidateKey, value) in dictionary {
            if normalizeLookupKey(candidateKey) == normalizedKey {
                return value
            }
        }

        guard depth < 3 else { return nil }

        let nestedContainers: Set<String> = [
            "payload", "data", "message", "info", "usage", "tokens", "session",
            "metadata", "meta", "result", "body", "content", "stats",
            "request", "action", "event", "source",
            "totaltokenusage", "lasttokenusage"
        ]
        for (candidateKey, value) in dictionary {
            guard nestedContainers.contains(normalizeLookupKey(candidateKey)) else { continue }
            if let nested = value as? [String: Any],
               let found = findValue(for: normalizedKey, in: nested, depth: depth + 1) {
                return found
            }
            if let array = value as? [Any] {
                for item in array {
                    guard let nested = item as? [String: Any] else { continue }
                    if let found = findValue(for: normalizedKey, in: nested, depth: depth + 1) {
                        return found
                    }
                }
            }
        }

        return nil
    }

    private static func normalizeLookupKey(_ key: String) -> String {
        AgentProvider.normalizeLookupKey(key)
    }
}

enum AgentDateParser {
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601NoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: Any?) -> Date? {
        guard let value else { return nil }

        if let date = value as? Date {
            return date
        }
        if let number = value as? Int {
            return date(from: Double(number))
        }
        if let number = value as? Int64 {
            return date(from: Double(number))
        }
        if let number = value as? Double {
            return date(from: number)
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return nil
            }
            if let milliseconds = Double(trimmed) {
                return date(from: milliseconds)
            }
            if let parsed = iso8601.date(from: trimmed) {
                return parsed
            }
            if let parsed = iso8601NoFraction.date(from: trimmed) {
                return parsed
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let parsed = formatter.date(from: trimmed) {
                return parsed
            }
        }
        return nil
    }

    private static func date(from rawValue: Double) -> Date {
        if rawValue > 10_000_000_000 {
            return Date(timeIntervalSince1970: rawValue / 1000.0)
        }
        return Date(timeIntervalSince1970: rawValue)
    }
}

func agentShortSummary(from text: String?, fallback: String?) -> String? {
    if let text = text?.trimmedNonEmpty {
        return String(text.prefix(220))
    }
    if let fallback = fallback?.trimmedNonEmpty {
        return String(fallback.prefix(220))
    }
    return nil
}
