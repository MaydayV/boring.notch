import Foundation
import Combine

@MainActor
final class AgentHubManager: ObservableObject {
    static let shared = AgentHubManager()

    @Published private(set) var sessions: [AgentSessionMeta] = []
    @Published private(set) var pendingActions: [AgentActionRequest] = []
    @Published private(set) var todayUsageSummary = AgentTodayUsageSummary(
        sessionCount: 0,
        runningSessionCount: 0,
        pendingActionCount: 0,
        inputTokens: 0,
        outputTokens: 0,
        totalTokens: 0,
        estimatedCostUSD: 0,
        updatedAt: Date()
    )
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var scanDeniedRoots: [AgentScanDeniedRoot] = []

    private let bridgeClient: AgentBridgeClient
    private let providerScanner: AgentProviderScanner
    private let jumpService: AgentJumpService
    private let eventRefreshDebounceInterval: TimeInterval = 0.25
    private let filesystemScanCacheInterval: TimeInterval = 30
    private var cachedFilesystemReport: AgentScanReport?
    private var cachedFilesystemScanAt: Date?
    private var lastEventRefreshAt: Date?
    private var isEventRefreshInFlight = false

    private init(
        bridgeClient: AgentBridgeClient = AgentBridgeClient(),
        providerScanner: AgentProviderScanner = AgentProviderScanner(),
        jumpService: AgentJumpService = AgentJumpService()
    ) {
        self.bridgeClient = bridgeClient
        self.providerScanner = providerScanner
        self.jumpService = jumpService

        Task { [bridgeClient] in
            await bridgeClient.startWatchingEvents { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.refresh(force: false, includeFilesystem: false)
                }
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refresh(force: false, includeFilesystem: true)
        }
    }

    func refresh(force: Bool = false, includeFilesystem: Bool = true) async {
        if includeFilesystem {
            if isRefreshing {
                return
            }

            isRefreshing = true
            defer { isRefreshing = false }

            let scanReport = await filesystemReport(force: force)
            cachedFilesystemReport = scanReport
            cachedFilesystemScanAt = Date()
            scanDeniedRoots = scanReport.deniedRoots

            let bridgeEvents = await bridgeClient.loadEvents()
            apply(scanReport: scanReport, bridgeEvents: bridgeEvents)
            return
        }

        if !force, let lastEventRefreshAt,
           Date().timeIntervalSince(lastEventRefreshAt) < eventRefreshDebounceInterval {
            return
        }
        if !force, isEventRefreshInFlight {
            return
        }
        isEventRefreshInFlight = true
        defer { isEventRefreshInFlight = false }

            let scanReport = cachedFilesystemReport ?? AgentScanReport(sessions: [], deniedRoots: scanDeniedRoots)
            let bridgeEvents = await bridgeClient.loadEvents()
            apply(scanReport: scanReport, bridgeEvents: bridgeEvents)
        lastEventRefreshAt = Date()
        lastRefreshAt = lastEventRefreshAt
        errorMessage = nil
    }

    private func apply(scanReport: AgentScanReport, bridgeEvents: [AgentBridgeEvent]) {
        let state = merge(filesystemSessions: scanReport.sessions, bridgeEvents: bridgeEvents)
        sessions = state.sessions
        pendingActions = state.pendingActions
        todayUsageSummary = state.todayUsageSummary
        lastRefreshAt = Date()
        errorMessage = nil
    }

    private func filesystemReport(force: Bool) async -> AgentScanReport {
        if !force,
           let cachedFilesystemReport,
           let cachedFilesystemScanAt,
           Date().timeIntervalSince(cachedFilesystemScanAt) < filesystemScanCacheInterval {
            return cachedFilesystemReport
        }

        let report = await scanSessionsInBackground()
        cachedFilesystemReport = report
        cachedFilesystemScanAt = Date()
        return report
    }

    private func scanSessionsInBackground() async -> AgentScanReport {
        let scanner = providerScanner
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: scanner.scanAllSessionsReport())
            }
        }
    }

    func approve(_ request: AgentActionRequest, mode: AgentApprovalMode = .standard) async -> Bool {
        await respond(request, outcome: .approved, message: mode.responseMessage)
    }

    func deny(_ request: AgentActionRequest) async -> Bool {
        await respond(request, outcome: .denied, message: nil)
    }

    func answer(_ request: AgentActionRequest, text: String) async -> Bool {
        await respond(request, outcome: .answered, message: text.trimmedNonEmpty)
    }

    func respond(_ request: AgentActionRequest, outcome: AgentResponseOutcome, message: String?) async -> Bool {
        let envelope = AgentActionResponseEnvelope(
            provider: request.provider,
            sessionId: request.sessionId,
            requestId: request.requestId,
            outcome: outcome,
            message: message,
            projectDir: request.projectDir,
            sourcePath: request.sourcePath
        )

        let wrote = await bridgeClient.appendResponse(envelope)
        if wrote {
            await refresh(force: true, includeFilesystem: false)
        }
        return wrote
    }

    func jump(to session: AgentSessionMeta) async -> Bool {
        do {
            try await jumpService.openInTerminal(session)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func diagnosticsSnapshot(hooks: [AgentHookProviderDiagnosticItem]) -> AgentDiagnosticsSnapshot {
        let sessionItems = sessions.map { session in
            AgentSessionDiagnosticItem(
                id: session.id,
                provider: session.provider.rawValue,
                sourceAlias: session.sourceAlias,
                sessionId: session.sessionId,
                title: session.title,
                state: session.state.rawValue,
                pendingActionCount: session.pendingActionCount,
                projectDir: session.projectDir,
                sourcePath: session.sourcePath,
                lastActiveAt: session.lastActiveAt,
                terminalApp: session.terminalContext?.app,
                terminalSessionId: session.terminalContext?.sessionId,
                terminalTabId: session.terminalContext?.tabId,
                terminalWindowId: session.terminalContext?.windowId,
                terminalTTY: session.terminalContext?.tty
            )
        }

        let pendingItems = pendingActions.map { action in
            AgentPendingActionDiagnosticItem(
                requestId: action.requestId,
                provider: action.provider.rawValue,
                sourceAlias: action.sourceAlias,
                sessionId: action.sessionId,
                kind: action.kind.rawValue,
                title: action.title,
                message: action.message,
                details: action.details,
                options: action.options,
                createdAt: action.createdAt,
                updatedAt: action.updatedAt,
                isResolved: action.isResolved
            )
        }

        return AgentDiagnosticsSnapshot(
            generatedAt: Date(),
            isRefreshing: isRefreshing,
            lastRefreshAt: lastRefreshAt,
            eventFilePath: bridgeClient.eventFileURL.path,
            responseFilePath: bridgeClient.responsesFileURL.path,
            bridgeCommandPath: AgentRuntimePaths.bridgeCommandURL.path,
            todaySessionCount: todayUsageSummary.sessionCount,
            todayRunningSessionCount: todayUsageSummary.runningSessionCount,
            todayPendingActionCount: todayUsageSummary.pendingActionCount,
            todayInputTokens: todayUsageSummary.inputTokens,
            todayOutputTokens: todayUsageSummary.outputTokens,
            todayTotalTokens: todayUsageSummary.totalTokens,
            todayEstimatedCostUSD: todayUsageSummary.estimatedCostUSD,
            scanDeniedRoots: scanDeniedRoots.map { "\($0.provider.displayName): \($0.rootPath)" },
            sessions: sessionItems,
            pendingActions: pendingItems,
            hooks: hooks
        )
    }

    private func merge(filesystemSessions: [AgentSessionMeta], bridgeEvents: [AgentBridgeEvent]) -> AgentHubState {
        var sessionsByKey: [String: AgentSessionMeta] = [:]
        for session in filesystemSessions {
            if let current = sessionsByKey[session.id] {
                sessionsByKey[session.id] = merge(current, with: session)
            } else {
                sessionsByKey[session.id] = session
            }
        }
        var requestsById: [String: AgentActionRequest] = [:]
        var usageBySession: [String: AgentUsageSnapshot] = [:]
        var childSubagentsByParentKey: [String: [AgentSubagentMeta]] = [:]
        var terminalStateBySessionKey: [String: AgentSessionState] = [:]
        var sourceAliasBySessionKey: [String: String] = [:]
        var suppressRunningBySessionKey: Set<String> = []

        for event in bridgeEvents.sorted(by: { $0.timestamp < $1.timestamp }) {
            let key = "\(event.provider.rawValue)::\(event.sessionId)"
            if let sourceAlias = event.sourceIdentifier?.trimmedNonEmpty {
                sourceAliasBySessionKey[key] = sourceAlias
            }
            let eventSubagent = event.subagent ?? subagent(from: event.payload)
            let payloadChildSubagents = childSubagents(from: event.payload)
            let eventTerminalContext = terminalContext(from: event.payload)
            var session = sessionsByKey[key] ?? AgentSessionMeta(
                provider: event.provider,
                sourceAlias: event.sourceIdentifier?.trimmedNonEmpty,
                terminalContext: eventTerminalContext,
                sessionId: event.sessionId,
                title: "\(event.provider.displayName) \(event.sessionId.prefix(8))",
                summary: nil,
                projectDir: nil,
                createdAt: event.timestamp,
                lastActiveAt: event.timestamp,
                resumeCommand: event.provider.resumeCommand(for: event.sessionId),
                sourcePath: bridgeClient.eventFileURL.path,
                state: .running,
                usage: nil,
                pendingActionCount: 0,
                subagent: nil,
                childSubagents: []
            )
            if session.sourceAlias?.trimmedNonEmpty == nil {
                session.sourceAlias = event.sourceIdentifier?.trimmedNonEmpty
            }
            session.terminalContext = mergeTerminalContext(session.terminalContext, with: eventTerminalContext)

            session.lastActiveAt = max(session.lastActiveAt, event.timestamp)
            session.createdAt = min(session.createdAt, event.timestamp)

            if let title = event.payload.stringValue(for: ["title", "sessionTitle", "name", "conversationTitle", "displayName", "thread_name", "threadName"]) {
                session.title = title
            }
            if let summary = event.payload.stringValue(for: ["summary", "description", "notes", "subtitle"]) {
                session.summary = summary
            }
            if let projectDir = event.payload.stringValue(for: ["projectDir", "project_dir", "cwd", "workingDirectory", "workspacePath", "rootPath", "path"]) {
                session.projectDir = projectDir
            }
            if let sourcePath = event.payload.stringValue(for: ["sourcePath", "source_path", "logPath", "log_path"]) {
                session.sourcePath = sourcePath
            }
            if let resumeCommand = event.payload.stringValue(for: ["resumeCommand", "resume_command"]) {
                session.resumeCommand = resumeCommand
            }
            if let eventSubagent {
                session.subagent = mergeSubagent(session.subagent, with: eventSubagent)
                if let parentThreadId = eventSubagent.parentThreadId?.trimmedNonEmpty {
                    let parentKey = "\(event.provider.rawValue)::\(parentThreadId)"
                    if parentKey != key {
                        childSubagentsByParentKey[parentKey, default: []].append(eventSubagent)
                    }
                }
            }
            if !payloadChildSubagents.isEmpty {
                for child in payloadChildSubagents {
                    if let parentThreadId = child.parentThreadId?.trimmedNonEmpty {
                        let parentKey = "\(event.provider.rawValue)::\(parentThreadId)"
                        if parentKey != key {
                            childSubagentsByParentKey[parentKey, default: []].append(child)
                            continue
                        }
                    }
                    session.childSubagents.append(child)
                }
            }

            switch event.type {
            case .some(.sessionStarted), .some(.sessionUpdated):
                if !suppressRunningBySessionKey.contains(key) {
                    session.state = prioritize(.running, over: session.state)
                }
            case .some(.usageUpdated):
                if let usage = makeUsage(from: event, fallbackTimestamp: event.timestamp) {
                    session.usage = usage
                    usageBySession[key] = usage
                }
                if !suppressRunningBySessionKey.contains(key) {
                    session.state = prioritize(.running, over: session.state)
                }
            case .some(.actionRequested):
                if shouldIgnoreActionRequestEvent(event) {
                    if !suppressRunningBySessionKey.contains(key) {
                        session.state = prioritize(.running, over: session.state)
                    }
                    break
                }
                if let request = makeRequest(from: event, resolved: false) {
                    requestsById[request.requestId] = merge(requestsById[request.requestId], with: request, resolved: false, eventTimestamp: event.timestamp)
                }
                if let kind = AgentActionKind.from(rawString: event.payload.stringValue(for: ["actionKind", "action_kind", "requestKind", "kind"])) {
                    switch kind {
                    case .question:
                        session.state = prioritize(.waitingQuestion, over: session.state)
                    case .approve, .deny:
                        session.state = prioritize(.waitingApproval, over: session.state)
                    }
                }
            case .some(.actionResolved):
                suppressRunningBySessionKey.insert(key)
                upsertResolvedRequest(from: event, into: &requestsById)
                let pendingRequestsAfterResolution = requestsBySession(sessionId: session.sessionId, provider: session.provider, in: requestsById)
                if pendingRequestsAfterResolution.isEmpty, session.state == .waitingApproval || session.state == .waitingQuestion {
                    session.state = .idle
                }
            case .some(.actionResponded):
                upsertResolvedRequest(from: event, into: &requestsById)
                let pendingRequestsAfterResponse = requestsBySession(sessionId: session.sessionId, provider: session.provider, in: requestsById)
                if pendingRequestsAfterResponse.isEmpty, session.state == .waitingApproval || session.state == .waitingQuestion {
                    session.state = .idle
                }
            case .some(.sessionCompleted):
                session.state = .completed
                terminalStateBySessionKey[key] = .completed
            case .some(.sessionFailed):
                session.state = .failed
                terminalStateBySessionKey[key] = .failed
            case .none:
                break
            }

            session.pendingActionCount = requestsBySession(sessionId: session.sessionId, provider: session.provider, in: requestsById).count
            if session.usage == nil, let usage = usageBySession[key] {
                session.usage = usage
            }
            sessionsByKey[key] = session
        }

        for (parentKey, children) in childSubagentsByParentKey {
            guard var parent = sessionsByKey[parentKey] else { continue }
            parent.childSubagents = mergeSubagentList(parent.childSubagents, with: children)
            sessionsByKey[parentKey] = parent
        }

        var sessions = sessionsByKey.values.map { session -> AgentSessionMeta in
            var session = session
            let sessionKey = session.id
            let pendingRequests = requestsBySession(sessionId: session.sessionId, provider: session.provider, in: requestsById)
            session.pendingActionCount = pendingRequests.count
            if let terminalState = terminalStateBySessionKey[sessionKey] {
                session.state = terminalState
            } else if pendingRequests.isEmpty, suppressRunningBySessionKey.contains(sessionKey), session.state == .running || session.state == .waitingApproval || session.state == .waitingQuestion {
                session.state = .idle
            } else {
                session.state = normalizedState(
                    session.state,
                    lastActiveAt: session.lastActiveAt,
                    pendingRequests: pendingRequests,
                    allowRunning: !suppressRunningBySessionKey.contains(sessionKey)
                )
            }
            if session.sourceAlias?.trimmedNonEmpty == nil {
                session.sourceAlias = sourceAliasBySessionKey[sessionKey]
            }
            if session.title.trimmedNonEmpty == nil {
                session.title = "\(session.provider.displayName) \(session.sessionId.prefix(8))"
            }
            return session
        }

        sessions.sort { lhs, rhs in
            if lhs.lastActiveAt == rhs.lastActiveAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.lastActiveAt > rhs.lastActiveAt
        }

        let pendingActions = requestsById.values
            .filter { !$0.isResolved }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    if lhs.provider == rhs.provider {
                        return lhs.requestId < rhs.requestId
                    }
                    return lhs.provider.displayName < rhs.provider.displayName
                }
                return lhs.createdAt > rhs.createdAt
            }

        let summary = makeTodaySummary(sessions: sessions, pendingActions: pendingActions)
        return AgentHubState(sessions: sessions, pendingActions: pendingActions, todayUsageSummary: summary)
    }

    private func merge(_ lhs: AgentSessionMeta, with rhs: AgentSessionMeta) -> AgentSessionMeta {
        var merged = lhs
        merged.sourceAlias = rhs.sourceAlias?.trimmedNonEmpty ?? merged.sourceAlias
        merged.terminalContext = mergeTerminalContext(lhs.terminalContext, with: rhs.terminalContext)
        merged.title = rhs.title.trimmedNonEmpty ?? merged.title
        merged.summary = rhs.summary?.trimmedNonEmpty ?? merged.summary
        merged.projectDir = rhs.projectDir?.trimmedNonEmpty ?? merged.projectDir
        merged.createdAt = min(lhs.createdAt, rhs.createdAt)
        merged.lastActiveAt = max(lhs.lastActiveAt, rhs.lastActiveAt)
        merged.resumeCommand = rhs.resumeCommand.trimmedNonEmpty ?? merged.resumeCommand
        merged.sourcePath = rhs.sourcePath.trimmedNonEmpty ?? merged.sourcePath
        merged.state = mergeSessionState(
            lhs.state,
            lhsLastActiveAt: lhs.lastActiveAt,
            rhs.state,
            rhsLastActiveAt: rhs.lastActiveAt
        )
        merged.usage = rhs.usage ?? merged.usage
        merged.pendingActionCount = max(lhs.pendingActionCount, rhs.pendingActionCount)
        merged.subagent = mergeSubagent(lhs.subagent, with: rhs.subagent)
        merged.childSubagents = mergeSubagentList(lhs.childSubagents, with: rhs.childSubagents)
        return merged
    }

    private func makeUsage(from event: AgentBridgeEvent, fallbackTimestamp: Date) -> AgentUsageSnapshot? {
        let inputTokens = event.payload.intValue(for: ["inputTokens", "input_tokens", "prompt_tokens", "input"])
        let outputTokens = event.payload.intValue(for: ["outputTokens", "output_tokens", "completion_tokens", "output"])
        let totalTokens = event.payload.intValue(for: ["totalTokens", "total_tokens", "total"]) ?? {
            if let inputTokens, let outputTokens {
                return inputTokens + outputTokens
            }
            return inputTokens ?? outputTokens
        }()
        let cost = event.payload.doubleValue(for: ["estimatedCostUSD", "estimated_cost_usd", "cost", "usdCost", "usd_cost"])
        let turnCount = event.payload.intValue(for: ["turnCount", "turn_count", "message_count", "messages", "request_count"])
        let updatedAt = event.payload.dateValue(for: ["updatedAt", "updated_at", "timestamp", "time"]) ?? fallbackTimestamp
        guard inputTokens != nil || outputTokens != nil || totalTokens != nil || cost != nil || turnCount != nil else {
            return nil
        }
        return AgentUsageSnapshot(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            estimatedCostUSD: cost,
            turnCount: turnCount,
            updatedAt: updatedAt
        )
    }

    private func makeRequest(from event: AgentBridgeEvent, resolved: Bool) -> AgentActionRequest? {
        let requestId = stableRequestId(for: event)
        let kind = actionKind(from: event.payload)
        let options = extractStringArray(from: event.payload, keys: ["options", "choices", "responses", "buttons"])
        let message = event.payload.stringValue(for: ["message", "prompt", "content", "text"])
        let details = event.payload.stringValue(for: ["details", "detail", "description", "summary"])
        return AgentActionRequest(
            requestId: requestId,
            provider: event.provider,
            sourceAlias: event.sourceIdentifier?.trimmedNonEmpty,
            sessionId: event.sessionId,
            kind: kind,
            title: event.payload.stringValue(for: ["title", "label", "headline"]),
            message: message,
            details: details,
            options: options,
            projectDir: event.payload.stringValue(for: ["projectDir", "project_dir", "cwd", "workingDirectory", "workspacePath", "rootPath", "path"]),
            createdAt: event.payload.dateValue(for: ["createdAt", "created_at", "timestamp", "time"]) ?? event.timestamp,
            updatedAt: event.payload.dateValue(for: ["updatedAt", "updated_at", "timestamp", "time"]) ?? event.timestamp,
            sourcePath: event.payload.stringValue(for: ["sourcePath", "source_path", "logPath", "log_path"]),
            isResolved: resolved,
            resolvedAt: resolved ? event.timestamp : nil,
            subagent: event.subagent ?? subagent(from: event.payload)
        )
    }

    private func upsertResolvedRequest(from event: AgentBridgeEvent, into requestsById: inout [String: AgentActionRequest]) {
        guard let resolvedRequest = makeRequest(from: event, resolved: true) else {
            return
        }

        if let existing = requestsById[resolvedRequest.requestId] {
            requestsById[resolvedRequest.requestId] = merge(existing, with: resolvedRequest, resolved: true, eventTimestamp: event.timestamp)
        } else {
            requestsById[resolvedRequest.requestId] = resolvedRequest
        }
    }

    private func merge(_ lhs: AgentActionRequest?, with rhs: AgentActionRequest, resolved: Bool, eventTimestamp: Date) -> AgentActionRequest {
        guard let lhs else { return rhs }

        var merged = lhs
        merged.sourceAlias = rhs.sourceAlias?.trimmedNonEmpty ?? merged.sourceAlias
        merged.kind = rhs.kind
        merged.title = rhs.title?.trimmedNonEmpty ?? merged.title
        merged.message = rhs.message?.trimmedNonEmpty ?? merged.message
        merged.details = rhs.details?.trimmedNonEmpty ?? merged.details
        if !rhs.options.isEmpty {
            merged.options = rhs.options
        }
        merged.projectDir = rhs.projectDir?.trimmedNonEmpty ?? merged.projectDir
        merged.createdAt = min(lhs.createdAt, rhs.createdAt)
        merged.updatedAt = max(max(lhs.updatedAt, rhs.updatedAt), eventTimestamp)
        merged.sourcePath = rhs.sourcePath?.trimmedNonEmpty ?? merged.sourcePath
        merged.subagent = mergeSubagent(lhs.subagent, with: rhs.subagent)
        merged.isResolved = lhs.isResolved || rhs.isResolved || resolved
        if merged.isResolved {
            merged.resolvedAt = lhs.resolvedAt ?? rhs.resolvedAt ?? eventTimestamp
        } else {
            merged.resolvedAt = nil
        }
        return merged
    }

    private func makeTodaySummary(sessions: [AgentSessionMeta], pendingActions: [AgentActionRequest]) -> AgentTodayUsageSummary {
        let calendar = Calendar.current
        let now = Date()
        let todaysSessions = sessions.filter { calendar.isDate($0.lastActiveAt, inSameDayAs: now) || calendar.isDate($0.createdAt, inSameDayAs: now) }

        var inputTokens = 0
        var outputTokens = 0
        var totalTokens = 0
        var estimatedCostUSD = 0.0
        for session in todaysSessions {
            guard let usage = session.usage, calendar.isDate(usage.updatedAt, inSameDayAs: now) else { continue }
            inputTokens += usage.inputTokens ?? 0
            outputTokens += usage.outputTokens ?? 0
            totalTokens += usage.totalTokens ?? ((usage.inputTokens ?? 0) + (usage.outputTokens ?? 0))
            estimatedCostUSD += usage.estimatedCostUSD ?? 0
        }

        return AgentTodayUsageSummary(
            sessionCount: sessions.count,
            runningSessionCount: sessions.filter { $0.state == .running }.count,
            pendingActionCount: pendingActions.count,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            estimatedCostUSD: estimatedCostUSD,
            updatedAt: now
        )
    }

    private func requestsBySession(sessionId: String, provider: AgentProvider, in requests: [String: AgentActionRequest]) -> [AgentActionRequest] {
        requests.values.filter { $0.sessionId == sessionId && $0.provider == provider && !$0.isResolved }
    }

    private func subagent(from payload: [String: Any]) -> AgentSubagentMeta? {
        let nestedSources = payload.nestedDictionaries(for: [
            "subagent", "subagentInfo", "subagent_info",
            "childAgent", "child_agent", "agent"
        ])
        let explicitSignals = payload.strictStringValue(for: [
            "subagentId", "subagent_id", "subagentID",
            "subagentParentThreadId", "subagent_parent_thread_id",
            "subagentName", "subagentNickname", "subagentRole", "subagentType"
        ])
        let sources: [[String: Any]]
        if !nestedSources.isEmpty {
            sources = nestedSources
        } else if explicitSignals != nil {
            sources = [payload]
        } else {
            sources = []
        }
        for source in sources {
            let id = source.strictStringValue(for: ["subagentId", "subagent_id", "subagentID", "id", "sessionId", "session_id"])
            let name = source.strictStringValue(for: ["subagentName", "subagent_name", "subagentNickname", "subagent_nickname", "nickname", "name", "title"])
            let role = source.strictStringValue(for: ["subagentRole", "subagent_role", "role"])
            let type = source.strictStringValue(for: ["subagentType", "subagent_type", "type"])
            let parentThreadId = source.strictStringValue(for: ["subagentParentThreadId", "subagent_parent_thread_id", "parentThreadId", "parent_thread_id"])

            guard id != nil || name != nil || role != nil || parentThreadId != nil else {
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

    private func childSubagents(from payload: [String: Any]) -> [AgentSubagentMeta] {
        let sources = payload.nestedDictionaries(for: [
            "subagentSessions", "subagent_sessions",
            "childSubagents", "child_subagents",
            "subagents"
        ])
        return sources.compactMap { source in
            let id = source.strictStringValue(for: ["subagentId", "subagent_id", "subagentID", "id"])
            let name = source.strictStringValue(for: ["subagentName", "subagent_name", "subagentNickname", "subagent_nickname", "nickname", "name", "title"])
            let role = source.strictStringValue(for: ["subagentRole", "subagent_role", "role"])
            let type = source.strictStringValue(for: ["subagentType", "subagent_type", "type"])
            let parentThreadId = source.strictStringValue(for: ["subagentParentThreadId", "subagent_parent_thread_id", "parentThreadId", "parent_thread_id"])
            guard id != nil || name != nil || role != nil || parentThreadId != nil else {
                return nil
            }

            return AgentSubagentMeta(
                id: id ?? parentThreadId ?? UUID().uuidString,
                name: name,
                role: role,
                type: type,
                parentThreadId: parentThreadId
            )
        }
    }

    private func mergeSubagent(_ lhs: AgentSubagentMeta?, with rhs: AgentSubagentMeta?) -> AgentSubagentMeta? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (let value?, nil), (nil, let value?):
            return value
        case (let lhs?, let rhs?):
            return AgentSubagentMeta(
                id: rhs.id.trimmedNonEmpty ?? lhs.id,
                name: rhs.name?.trimmedNonEmpty ?? lhs.name,
                role: rhs.role?.trimmedNonEmpty ?? lhs.role,
                type: rhs.type?.trimmedNonEmpty ?? lhs.type,
                parentThreadId: rhs.parentThreadId?.trimmedNonEmpty ?? lhs.parentThreadId
            )
        }
    }

    private func mergeSubagentList(_ lhs: [AgentSubagentMeta], with rhs: [AgentSubagentMeta]) -> [AgentSubagentMeta] {
        var merged: [AgentSubagentMeta] = []
        var seen = Set<String>()

        for candidate in lhs + rhs {
            let key = candidate.parentThreadId?.trimmedNonEmpty ?? candidate.id.trimmedNonEmpty ?? candidate.displayName
            if seen.insert(key).inserted {
                merged.append(candidate)
            }
        }

        return merged
    }

    private func mergeSessionState(
        _ lhs: AgentSessionState,
        lhsLastActiveAt: Date,
        _ rhs: AgentSessionState,
        rhsLastActiveAt: Date
    ) -> AgentSessionState {
        if lhs == rhs {
            return lhs
        }

        let lhsRank = rank(lhs)
        let rhsRank = rank(rhs)
        if lhsRank != rhsRank {
            if lhsRank >= 2 || rhsRank >= 2 {
                return lhsRank >= rhsRank ? lhs : rhs
            }
            return lhsLastActiveAt >= rhsLastActiveAt ? lhs : rhs
        }

        return lhsLastActiveAt >= rhsLastActiveAt ? lhs : rhs
    }

    private func prioritize(_ lhs: AgentSessionState, over rhs: AgentSessionState) -> AgentSessionState {
        rank(lhs) >= rank(rhs) ? lhs : rhs
    }

    private func rank(_ state: AgentSessionState) -> Int {
        switch state {
        case .failed: return 5
        case .completed: return 4
        case .waitingQuestion: return 3
        case .waitingApproval: return 2
        case .running: return 1
        case .idle: return 0
        }
    }

    private func extractStringArray(from dictionary: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let strings = dictionary[key] as? [String] {
                return strings.compactMap { $0.trimmedNonEmpty }
            }
            if let strings = dictionary[key] as? [Any] {
                return strings.compactMap { element in
                    if let string = element as? String {
                        return string.trimmedNonEmpty
                    }
                    if let value = element as? CustomStringConvertible {
                        return value.description.trimmedNonEmpty
                    }
                    return nil
                }
            }
            if let string = dictionary[key] as? String {
                return string
                    .split(whereSeparator: { $0 == "\n" || $0 == "," })
                    .map { String($0).trimmedNonEmpty }
                    .compactMap { $0 }
            }
        }
        return []
    }

    private func actionKind(from payload: [String: Any]) -> AgentActionKind {
        AgentActionKind.from(rawString: payload.stringValue(for: ["actionKind", "action_kind", "requestKind", "kind"])) ?? .question
    }

    private func shouldIgnoreActionRequestEvent(_ event: AgentBridgeEvent) -> Bool {
        let hookEventName = event.payload
            .stringValue(for: ["hook_event_name", "hookEventName"])?
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .lowercased()

        guard let hookEventName else {
            return false
        }

        // Historical bridge versions occasionally emitted action.requested for
        // non-interactive lifecycle hooks (for example UserPromptSubmit).
        // Keep these from creating phantom "waiting input" cards.
        let nonInteractiveHookEvents: Set<String> = [
            "userpromptsubmit",
            "sessionstart",
            "sessionend",
            "hooksessionstart",
            "hooksessionend",
            "posttooluse",
            "hookposttooluse",
            "aftertool",
            "aftertooluse",
            "afteragent",
            "notification"
        ]
        guard nonInteractiveHookEvents.contains(hookEventName) else {
            return false
        }

        let hasInteractiveMarkers =
            event.payload.stringValue(for: ["permission", "permissionRequest", "permission_request", "approval", "approvalRequired", "approval_required"]) != nil
            || event.payload.intValue(for: ["optionsCount"]) != nil
            || !extractStringArray(from: event.payload, keys: ["options", "choices", "responses", "buttons"]).isEmpty
            || event.payload.stringValue(for: ["requestId", "request_id", "actionId", "action_id"]) != nil
            || AgentActionKind.from(rawString: event.payload.stringValue(for: ["actionKind", "action_kind", "requestKind", "kind"])) != nil

        return !hasInteractiveMarkers
    }

    private func normalizedState(
        _ state: AgentSessionState,
        lastActiveAt: Date,
        pendingRequests: [AgentActionRequest],
        allowRunning: Bool
    ) -> AgentSessionState {
        if !pendingRequests.isEmpty {
            let hasQuestion = pendingRequests.contains { $0.kind == .question }
            return hasQuestion ? .waitingQuestion : .waitingApproval
        }

        switch state {
        case .running:
            guard allowRunning else {
                return .idle
            }
            let isFresh = Date().timeIntervalSince(lastActiveAt) <= activeSessionWindow
            return isFresh ? .running : .idle
        case .waitingApproval, .waitingQuestion:
            // Waiting states are user-blocked and should not be downgraded by inactivity timeout.
            return state
        case .completed, .failed, .idle:
            return state
        }
    }

    private func stableRequestId(for event: AgentBridgeEvent) -> String {
        if let requestId = event.requestId?.trimmedNonEmpty {
            return requestId
        }

        let base = stableRequestSignature(
            provider: event.provider,
            sessionId: event.sessionId,
            eventType: event.type?.rawValue ?? event.payload.stringValue(for: ["event", "type", "kind"]) ?? "action",
            payload: event.payload
        )
        return "auto-\(fnv1a64(base))"
    }

    private func stableRequestSignature(
        provider: AgentProvider,
        sessionId: String,
        eventType: String,
        payload: [String: Any]
    ) -> String {
        let kind = actionKindSignature(from: payload, eventType: eventType)
        let title = payload.stringValue(for: ["title", "label", "headline"]) ?? ""
        let message = payload.stringValue(for: ["message", "prompt", "content", "text"]) ?? ""
        let details = payload.stringValue(for: ["details", "detail", "description", "summary"]) ?? ""
        let options = extractStringArray(from: payload, keys: ["options", "choices", "responses", "buttons"]).sorted().joined(separator: ",")
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

    private var activeSessionWindow: TimeInterval {
        if let raw = ProcessInfo.processInfo.environment["BORING_NOTCH_AGENT_ACTIVE_WINDOW_SECONDS"],
           let value = Double(raw),
           value > 0 {
            return value
        }
        return 120
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

    private func terminalContext(from payload: [String: Any]) -> AgentTerminalContext? {
        let terminalNode = payload.nestedDictionaries(for: ["terminal"]).first
        let app = payload.stringValue(for: [
            "terminalApp", "terminal_app",
            "terminalName", "terminal_name",
            "terminal", "appName", "app_name",
            "terminal/appName", "terminal/app", "terminal/name",
            "terminalProgram", "terminal_program",
            "termProgram", "term_program"
        ]) ?? terminalNode?.stringValue(for: ["appName", "app_name", "app", "name", "program"])
        let sessionId = payload.stringValue(for: [
            "itermSessionId", "iterm_session_id", "ITERM_SESSION_ID",
            "termSessionId", "term_session_id", "TERM_SESSION_ID",
            "terminalSessionId", "terminal_session_id"
        ]) ?? terminalNode?.stringValue(for: [
            "sessionId", "session_id",
            "terminalSessionId", "terminal_session_id",
            "itermSessionId", "iterm_session_id",
            "TERM_SESSION_ID", "ITERM_SESSION_ID"
        ])
        let tabId = payload.stringValue(for: [
            "itermTabId", "iterm_tab_id",
            "terminalTabId", "terminal_tab_id",
            "tabId", "tab_id"
        ]) ?? terminalNode?.stringValue(for: [
            "tabId", "tab_id",
            "terminalTabId", "terminal_tab_id",
            "itermTabId", "iterm_tab_id"
        ])
        let windowId = payload.stringValue(for: [
            "itermWindowId", "iterm_window_id",
            "terminalWindowId", "terminal_window_id",
            "windowId", "window_id"
        ]) ?? terminalNode?.stringValue(for: [
            "windowId", "window_id",
            "terminalWindowId", "terminal_window_id",
            "itermWindowId", "iterm_window_id"
        ])
        let tty = payload.stringValue(for: [
            "tty", "pty", "terminalTTY", "terminal_tty"
        ]) ?? terminalNode?.stringValue(for: ["tty", "pty", "terminalTTY", "terminal_tty"])

        let context = AgentTerminalContext(
            app: app,
            sessionId: sessionId,
            tabId: tabId,
            windowId: windowId,
            tty: tty
        )
        guard context.app?.trimmedNonEmpty != nil || context.hasAnyLocator else {
            return nil
        }
        return context
    }

    private func mergeTerminalContext(_ lhs: AgentTerminalContext?, with rhs: AgentTerminalContext?) -> AgentTerminalContext? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (let value?, nil), (nil, let value?):
            return value
        case (let lhs?, let rhs?):
            return AgentTerminalContext(
                app: rhs.app?.trimmedNonEmpty ?? lhs.app,
                sessionId: rhs.sessionId?.trimmedNonEmpty ?? lhs.sessionId,
                tabId: rhs.tabId?.trimmedNonEmpty ?? lhs.tabId,
                windowId: rhs.windowId?.trimmedNonEmpty ?? lhs.windowId,
                tty: rhs.tty?.trimmedNonEmpty ?? lhs.tty
            )
        }
    }
}

private struct AgentHubState {
    let sessions: [AgentSessionMeta]
    let pendingActions: [AgentActionRequest]
    let todayUsageSummary: AgentTodayUsageSummary
}
