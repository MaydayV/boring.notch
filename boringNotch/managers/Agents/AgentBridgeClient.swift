import Foundation
import Darwin

actor AgentBridgeClient {
    private static let maxEventReadBytes = 1_500_000
    private static let maxEventLines = 4_000

    nonisolated let eventFileURL: URL
    nonisolated let responsesFileURL: URL
    private let fileManager: FileManager
    private let eventsWatcherQueue = DispatchQueue(label: "boringNotch.agentBridge.eventsWatcher", qos: .utility)
    private var eventsWatcher: DispatchSourceFileSystemObject?
    private var eventsFileDescriptor: Int32 = -1
    private var eventsWatcherPath: String?
    private var cachedEvents: [AgentBridgeEvent] = []
    private var cachedEventFileSize: Int64?
    private var cachedEventModificationDate: Date?

    init(fileManager: FileManager = .default) {
        self.eventFileURL = Self.defaultEventFileURL()
        self.responsesFileURL = Self.defaultResponsesFileURL()
        self.fileManager = fileManager
    }

    init(
        eventFileURL: URL,
        responsesFileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.eventFileURL = eventFileURL
        self.responsesFileURL = responsesFileURL
        self.fileManager = fileManager
    }

    func startWatchingEvents(onChange: @escaping @Sendable () -> Void) {
        stopWatchingEvents()

        guard let watched = makeWatchedPath() else {
            return
        }

        let descriptor = open(watched.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: eventsWatcherQueue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.handleWatchedEventsChanged(onChange: onChange) }
        }
        source.setCancelHandler {
            close(descriptor)
        }

        eventsFileDescriptor = descriptor
        eventsWatcher = source
        eventsWatcherPath = watched.path
        source.resume()
    }

    func stopWatchingEvents() {
        eventsWatcher?.cancel()
        eventsWatcher = nil
        eventsWatcherPath = nil
        eventsFileDescriptor = -1
    }

    func loadEvents() -> [AgentBridgeEvent] {
        guard fileManager.fileExists(atPath: eventFileURL.path) else {
            cachedEvents = []
            cachedEventFileSize = nil
            cachedEventModificationDate = nil
            return []
        }

        let attributes = (try? fileManager.attributesOfItem(atPath: eventFileURL.path)) ?? [:]
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date

        if cachedEventFileSize == fileSize,
           cachedEventModificationDate == modificationDate,
           !cachedEvents.isEmpty {
            return cachedEvents
        }

        guard let data = readBoundedEventData() else {
            return []
        }

        let clampedData = clampEventData(data)
        guard let text = String(data: clampedData, encoding: .utf8), !text.isEmpty else {
            cachedEvents = []
            cachedEventFileSize = fileSize
            cachedEventModificationDate = modificationDate
            return []
        }

        var events: [AgentBridgeEvent] = []
        for rawLine in text.split(whereSeparator: \.isNewline).suffix(Self.maxEventLines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: lineData),
                  let dictionary = object as? [String: Any],
                  let event = parseEvent(from: dictionary) else {
                continue
            }
            events.append(event)
        }

        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.sessionId < rhs.sessionId
            }
            return lhs.timestamp < rhs.timestamp
        }
        cachedEvents = sortedEvents
        cachedEventFileSize = fileSize
        cachedEventModificationDate = modificationDate
        return sortedEvents
    }

    private func readBoundedEventData() -> Data? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: eventFileURL.path),
              let fileSizeNumber = attributes[.size] as? NSNumber else {
            return try? Data(contentsOf: eventFileURL)
        }

        let fileSize = max(0, fileSizeNumber.intValue)
        if fileSize <= Self.maxEventReadBytes {
            return try? Data(contentsOf: eventFileURL)
        }

        guard let handle = try? FileHandle(forReadingFrom: eventFileURL) else {
            return nil
        }
        defer { try? handle.close() }

        let offset = UInt64(max(0, fileSize - Self.maxEventReadBytes))
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd(), !data.isEmpty else {
            return nil
        }

        if offset > 0,
           let newlineIndex = data.firstIndex(of: 0x0A) {
            let start = data.index(after: newlineIndex)
            data = Data(data[start...])
        }
        return data
    }

    private func clampEventData(_ data: Data) -> Data {
        guard data.count > Self.maxEventReadBytes else {
            return data
        }
        let tail = data.suffix(Self.maxEventReadBytes)
        guard let newlineIndex = tail.firstIndex(of: 0x0A) else {
            return Data(tail)
        }
        let start = tail.index(after: newlineIndex)
        return Data(tail[start...])
    }

    func appendResponse(_ envelope: AgentActionResponseEnvelope) -> Bool {
        do {
            try ensureParentDirectoryExists()

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(envelope)
            guard var line = String(data: data, encoding: .utf8) else {
                return false
            }
            line.append("\n")

            if fileManager.fileExists(atPath: responsesFileURL.path) {
                let handle = try FileHandle(forWritingTo: responsesFileURL)
                defer { try? handle.close() }
                _ = handle.seekToEndOfFile()
                if let payload = line.data(using: .utf8) {
                    try handle.write(contentsOf: payload)
                }
            } else {
                try line.write(to: responsesFileURL, atomically: true, encoding: .utf8)
            }
            return true
        } catch {
            return false
        }
    }

    private func ensureParentDirectoryExists() throws {
        let directoryURL = responsesFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func parseEvent(from dictionary: [String: Any]) -> AgentBridgeEvent? {
        guard let providerResolution = resolveProvider(from: dictionary) else {
            return nil
        }
        let provider = providerResolution.provider

        let sessionId = inferSessionId(from: dictionary) ?? "unknown"
        let timestamp = inferTimestamp(from: dictionary) ?? Date()
        let schemaVersion = dictionary.intValue(for: ["schemaVersion", "schema_version"])
        let typeString = inferEventTypeString(from: dictionary, provider: provider)
        let requestId = inferRequestId(
            from: dictionary,
            eventType: typeString,
            provider: provider,
            sessionId: sessionId
        )
        let type = typeString.flatMap { AgentBridgeEventType(rawValue: $0) }
        let payload = filterPayload(from: dictionary)
        let subagent = inferSubagent(from: dictionary)

        return AgentBridgeEvent(
            schemaVersion: schemaVersion,
            type: type,
            provider: provider,
            sourceIdentifier: providerResolution.sourceAlias,
            sessionId: sessionId,
            requestId: requestId,
            timestamp: timestamp,
            payload: payload,
            subagent: subagent
        )
    }

    private func resolveProvider(from dictionary: [String: Any]) -> (provider: AgentProvider, sourceAlias: String?)? {
        let sourceCandidates: [String?] = [
            dictionary.stringValue(for: ["provider"]),
            dictionary.stringValue(for: ["source"]),
            dictionary.stringValue(for: ["sourceName", "source_name"]),
            dictionary.stringValue(for: ["providerName", "provider_name"]),
            dictionary.stringValue(for: ["agent", "agentName", "agent_name"]),
            dictionary.stringValue(for: ["command", "commandName", "command_name"])
        ]
        for candidate in sourceCandidates.compactMap({ $0 }) {
            let normalized = normalizeProviderIdentifier(candidate)
            if let provider = AgentProvider.resolved(from: normalized) {
                let alias = normalized.trimmedNonEmpty
                if let profile = AgentProvider.profile(for: normalized),
                   profile.displayName != provider.displayName {
                    return (provider: provider, sourceAlias: profile.displayName)
                }
                return (provider: provider, sourceAlias: alias == provider.rawValue ? nil : alias)
            }
        }
        return nil
    }

    private func inferSessionId(from dictionary: [String: Any]) -> String? {
        dictionary.strictStringValue(for: [
            "sessionId", "session_id", "sessionID", "sessionKey",
            "conversationId", "conversation_id", "threadId", "thread_id",
            "chatId", "chat_id", "parentThreadId", "parent_thread_id",
            "subagentParentThreadId", "subagent_parent_thread_id",
            "session"
        ])
    }

    private func inferRequestId(
        from dictionary: [String: Any],
        eventType: String?,
        provider: AgentProvider,
        sessionId: String
    ) -> String? {
        dictionary.strictStringValue(for: [
            "requestId", "request_id", "requestID",
            "actionId", "action_id", "actionID"
        ]) ?? {
            guard let eventType,
                  let event = AgentBridgeEventType(rawValue: eventType) else {
                return nil
            }
            switch event {
            case .actionRequested, .actionResolved, .actionResponded:
                if let explicitID = dictionary.stringValue(for: ["id"])?.trimmedNonEmpty {
                    return explicitID
                }
                let synthesized = synthesizedRequestId(
                    provider: provider,
                    sessionId: sessionId,
                    eventType: eventType,
                    payload: dictionary
                )
                print("⚠️ [AgentBridgeClient] Missing requestId for \(eventType) on \(provider.displayName) session \(sessionId); synthesized \(synthesized)")
                return synthesized
            case .sessionStarted, .sessionUpdated, .usageUpdated, .sessionCompleted, .sessionFailed:
                return nil
            }
        }()
    }

    private func synthesizedRequestId(
        provider: AgentProvider,
        sessionId: String,
        eventType: String,
        payload: [String: Any]
    ) -> String {
        let signature = actionRequestSignature(provider: provider, sessionId: sessionId, eventType: eventType, payload: payload)
        return "auto-\(fnv1a64(signature))"
    }

    private func actionRequestSignature(
        provider: AgentProvider,
        sessionId: String,
        eventType: String,
        payload: [String: Any]
    ) -> String {
        let kind = actionKindSignature(from: payload, eventType: eventType)
        let title = payload.stringValue(for: ["title", "label", "headline"]) ?? ""
        let message = payload.stringValue(for: ["message", "prompt", "content", "text"]) ?? ""
        let details = payload.stringValue(for: ["details", "detail", "description", "summary"]) ?? ""
        let options = firstStableStringArray(from: payload, keys: ["options", "choices", "responses", "buttons"])
        let projectDir = payload.stringValue(for: ["projectDir", "project_dir", "cwd", "workingDirectory", "workspacePath", "rootPath", "path"]) ?? ""
        let sourcePath = payload.stringValue(for: ["sourcePath", "source_path", "logPath", "log_path"]) ?? ""
        let subagentId = payload.stringValue(for: ["subagentId", "subagent_id", "subagentID", "id"]) ?? ""
        let parentThreadId = payload.stringValue(for: ["subagentParentThreadId", "subagent_parent_thread_id", "parentThreadId", "parent_thread_id"]) ?? ""

        return [
            provider.rawValue,
            sessionId,
            kind,
            title,
            message,
            details,
            options,
            projectDir,
            sourcePath,
            subagentId,
            parentThreadId
        ].joined(separator: "|")
    }

    private func actionKindSignature(from payload: [String: Any], eventType: String) -> String {
        if let explicitKind = AgentActionKind.from(rawString: payload.stringValue(for: ["actionKind", "action_kind", "requestKind", "kind"])) {
            return explicitKind.rawValue
        }

        let normalizedEventType = eventType
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
            .lowercased()

        if normalizedEventType == "actionrequested" {
            return "action"
        }

        let outcome = payload.stringValue(for: ["outcome", "result", "decision"])?.lowercased()
        switch outcome {
        case "approved", "allow", "allowed", "true":
            return AgentActionKind.approve.rawValue
        case "denied", "deny", "rejected", "reject", "false":
            return AgentActionKind.deny.rawValue
        case "answered", "answer":
            return AgentActionKind.question.rawValue
        default:
            return "action"
        }
    }

    private func firstStableStringArray(from dictionary: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let strings = dictionary[key] as? [String] {
                let trimmed = strings.compactMap { $0.trimmedNonEmpty }
                if !trimmed.isEmpty {
                    return trimmed.sorted().joined(separator: ",")
                }
            }
            if let strings = dictionary[key] as? [Any] {
                let trimmed = strings.compactMap { element in
                    if let string = element as? String {
                        return string.trimmedNonEmpty
                    }
                    if let value = element as? CustomStringConvertible {
                        return value.description.trimmedNonEmpty
                    }
                    return nil
                }
                if !trimmed.isEmpty {
                    return trimmed.sorted().joined(separator: ",")
                }
            }
            if let string = dictionary[key] as? String {
                let trimmed = string
                    .split(whereSeparator: { $0 == "\n" || $0 == "," })
                    .map { String($0).trimmedNonEmpty }
                    .compactMap { $0 }
                if !trimmed.isEmpty {
                    return trimmed.sorted().joined(separator: ",")
                }
            }
        }
        return ""
    }

    private func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return String(format: "%016llx", hash)
    }

    private func inferTimestamp(from dictionary: [String: Any]) -> Date? {
        dictionary.dateValue(for: [
            "timestamp", "createdAt", "created_at",
            "updatedAt", "updated_at", "time",
            "eventTime", "event_time"
        ])
    }

    private func inferEventTypeString(from dictionary: [String: Any], provider: AgentProvider) -> String? {
        if let explicit = dictionary.stringValue(for: ["event", "type", "kind"]) {
            return normalizeEventType(explicit, provider: provider)
        }
        if let hookEvent = dictionary.stringValue(for: ["hook_event_name", "hookEventName"]) {
            return normalizeEventType(hookEvent, provider: provider)
        }
        if let codexEvent = dictionary.stringValue(for: ["codex_event_type"]) {
            return normalizeEventType(codexEvent, provider: provider)
        }
        return nil
    }

    private func normalizeEventType(_ rawValue: String, provider: AgentProvider) -> String {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
            .lowercased()

        switch provider {
        case .claude:
            switch normalized {
            case "sessionstart", "hooksessionstart":
                return AgentBridgeEventType.sessionStarted.rawValue
            case "sessionend", "sessioncompleted", "stop", "subagentstop":
                return AgentBridgeEventType.sessionCompleted.rawValue
            case "userpromptsubmit", "hookuserpromptsubmit":
                return AgentBridgeEventType.sessionUpdated.rawValue
            case "permissionrequest", "hookpermissionrequest", "pretooluse", "hookpretooluse", "beforetool", "beforetooluse":
                return AgentBridgeEventType.actionRequested.rawValue
            case "posttooluse", "hookposttooluse", "aftertool", "aftertooluse", "afteragent", "notification":
                return AgentBridgeEventType.sessionUpdated.rawValue
            default:
                break
            }
        case .codex:
            switch normalized {
            case "sessionstart", "hooksessionstart":
                return AgentBridgeEventType.sessionStarted.rawValue
            case "sessionend", "sessioncompleted", "stop", "stopfailure", "subagentstop":
                return AgentBridgeEventType.sessionCompleted.rawValue
            case "userpromptsubmit", "hookuserpromptsubmit":
                return AgentBridgeEventType.sessionUpdated.rawValue
            case "permissionrequest", "hookpermissionrequest", "pretooluse", "hookpretooluse", "beforetool", "beforetooluse":
                return AgentBridgeEventType.actionRequested.rawValue
            case "posttooluse", "hookposttooluse", "aftertool", "aftertooluse", "afteragent", "notification":
                return AgentBridgeEventType.sessionUpdated.rawValue
            default:
                break
            }
        case .gemini:
            switch normalized {
            case "sessionstart", "beforeagent":
                return AgentBridgeEventType.sessionStarted.rawValue
            case "sessionend", "sessioncompleted", "stop", "afteragent", "subagentstop":
                return AgentBridgeEventType.sessionCompleted.rawValue
            case "beforetool", "beforetooluse":
                return AgentBridgeEventType.actionRequested.rawValue
            case "aftertool", "aftertooluse":
                return AgentBridgeEventType.sessionUpdated.rawValue
            default:
                break
            }
        case .cursor, .opencode, .droid, .openclaw:
            break
        }

        switch normalized {
        case "sessionstart", "hooksessionstart":
            return AgentBridgeEventType.sessionStarted.rawValue
        case "sessionend", "sessioncompleted", "sessioncomplete", "stop", "subagentstop":
            return AgentBridgeEventType.sessionCompleted.rawValue
        case "permissionrequest", "hookpermissionrequest", "pretooluse", "hookpretooluse", "beforetool", "beforetooluse":
            return AgentBridgeEventType.actionRequested.rawValue
        case "posttooluse", "hookposttooluse", "aftertool", "aftertooluse", "afteragent", "notification", "userpromptsubmit", "hookuserpromptsubmit":
            return AgentBridgeEventType.sessionUpdated.rawValue
        case "usageupdated":
            return AgentBridgeEventType.usageUpdated.rawValue
        case "actionrequested":
            return AgentBridgeEventType.actionRequested.rawValue
        case "actionresolved", "actionresponded":
            return AgentBridgeEventType.actionResolved.rawValue
        default:
            return rawValue
        }
    }

    private func inferSubagent(from dictionary: [String: Any]) -> AgentSubagentMeta? {
        let candidates: [[String: Any]]
        if let nested = firstSubagentContainer(in: dictionary) {
            candidates = [nested]
        } else {
            let explicitSignals = dictionary.strictStringValue(for: [
                "subagentId", "subagent_id", "subagentID",
                "subagentParentThreadId", "subagent_parent_thread_id",
                "subagentName", "subagentNickname", "subagentRole", "subagentType"
            ])
            guard explicitSignals != nil else {
                return nil
            }
            candidates = [dictionary]
        }

        for source in candidates {
            let id = source.strictStringValue(for: [
                "subagentId", "subagent_id", "subagentID", "id", "threadId", "thread_id", "sessionId", "session_id"
            ])
            let name = source.strictStringValue(for: [
                "subagentName", "subagent_name", "subagentNickname", "subagent_nickname",
                "nickname", "name", "title"
            ])
            let role = source.strictStringValue(for: [
                "subagentRole", "subagent_role", "role"
            ])
            let type = source.strictStringValue(for: [
                "subagentType", "subagent_type", "type"
            ])
            let parentThreadId = source.strictStringValue(for: [
                "subagentParentThreadId", "subagent_parent_thread_id",
                "parentThreadId", "parent_thread_id"
            ])

            guard id != nil || parentThreadId != nil || name != nil || role != nil else {
                continue
            }

            return AgentSubagentMeta(
                id: id ?? parentThreadId ?? UUID().uuidString,
                name: name,
                role: role,
                type: type,
                parentThreadId: parentThreadId
            )
        }

        return nil
    }

    private func firstSubagentContainer(in dictionary: [String: Any]) -> [String: Any]? {
        for key in [
            "subagent", "subagentInfo", "subagent_info",
            "childAgent", "child_agent", "agent", "agentInfo", "agent_info"
        ] {
            if let nested = dictionary[key] as? [String: Any] {
                return nested
            }
        }
        return nil
    }

    private func filterPayload(from dictionary: [String: Any]) -> [String: Any] {
        let ignoredKeys: Set<String> = [
            "schemaversion",
            "schema_version",
            "provider",
            "sessionid",
            "session_id",
            "sessionkey",
            "conversationid",
            "conversation_id",
            "threadid",
            "thread_id",
            "chatid",
            "chat_id",
            "event",
            "type",
            "kind",
            "timestamp",
            "createdat",
            "created_at",
            "updatedat",
            "updated_at",
            "requestid",
            "request_id",
            "requestid",
            "actionid",
            "action_id",
            "machineonly",
            "machinelocalonly"
        ]
        return dictionary.filter { key, _ in
            !ignoredKeys.contains(key.lowercased())
        }
    }

    private func makeWatchedPath() -> URL? {
        if fileManager.fileExists(atPath: eventFileURL.path) {
            return eventFileURL
        }

        let parentDirectory = eventFileURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parentDirectory.path) else {
            return nil
        }
        return parentDirectory
    }

    private func handleWatchedEventsChanged(onChange: @escaping @Sendable () -> Void) {
        onChange()

        if let watchedPath = eventsWatcherPath,
           watchedPath != eventFileURL.path,
           fileManager.fileExists(atPath: eventFileURL.path) {
            startWatchingEvents(onChange: onChange)
        }
    }

    private func normalizeProviderIdentifier(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0 == "/" || $0 == "\\" || $0 == ":" })
            .last
            .map(String.init) ?? value.lowercased()
    }

    static func defaultEventFileURL() -> URL {
        defaultBaseDirectory().appendingPathComponent("events.ndjson")
    }

    static func defaultResponsesFileURL() -> URL {
        defaultBaseDirectory().appendingPathComponent("responses.ndjson")
    }

    static func defaultBaseDirectory() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/boring.notch/Agents", isDirectory: true)
    }
}
