//
//  AgentsTabView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct AgentsTabView: View {
    @ObservedObject var manager: AgentHubManager

    @Default(.showClaudeAgentProvider) private var showClaudeAgentProvider
    @Default(.showCodexAgentProvider) private var showCodexAgentProvider
    @Default(.showGeminiAgentProvider) private var showGeminiAgentProvider
    @Default(.showCursorAgentProvider) private var showCursorAgentProvider
    @Default(.showOpenCodeAgentProvider) private var showOpenCodeAgentProvider
    @Default(.showDroidAgentProvider) private var showDroidAgentProvider
    @Default(.showOpenClawAgentProvider) private var showOpenClawAgentProvider
    @Default(.enableAgentJumpAction) private var enableAgentJumpAction
    @Default(.agentPanelStyle) private var agentPanelStyle

    @State private var actionStatusMessage: String?
    @State private var actionStatusClearTask: Task<Void, Never>?

    @MainActor
    init(manager: AgentHubManager? = nil) {
        self.manager = manager ?? .shared
    }

    private var enabledProviders: Set<AgentProvider> {
        Set(AgentProvider.allCases.filter { isProviderEnabled($0) })
    }

    private func isProviderEnabled(_ provider: AgentProvider) -> Bool {
        switch provider {
        case .claude:
            return showClaudeAgentProvider
        case .codex:
            return showCodexAgentProvider
        case .gemini:
            return showGeminiAgentProvider
        case .cursor:
            return showCursorAgentProvider
        case .opencode:
            return showOpenCodeAgentProvider
        case .droid:
            return showDroidAgentProvider
        case .openclaw:
            return showOpenClawAgentProvider
        }
    }

    private var visibleSessions: [AgentSessionMeta] {
        manager.sessions.filter { enabledProviders.contains($0.provider) }
    }

    private var visibleActiveSessions: [AgentSessionMeta] {
        visibleSessions.filter(\.state.isActive)
    }

    private var visiblePendingActions: [AgentActionRequest] {
        manager.pendingActions.filter { enabledProviders.contains($0.provider) }
    }

    private var deniedProviders: [AgentProvider] {
        let providers = manager.scanDeniedRoots
            .map(\.provider)
            .filter { enabledProviders.contains($0) }
        return Array(Set(providers)).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var deniedProviderLabel: String {
        deniedProviders.map(\.displayName).joined(separator: ", ")
    }

    private var permissionHintMessage: String? {
        guard !deniedProviders.isEmpty else { return nil }
        return AgentLocalization.format(
            "agents.permission.banner",
            deniedProviderLabel
        )
    }

    private var latestPendingActionBySession: [String: AgentActionRequest] {
        var map: [String: AgentActionRequest] = [:]
        for request in visiblePendingActions.sorted(by: { $0.createdAt > $1.createdAt }) {
            let key = "\(request.provider.rawValue)::\(request.sessionId)"
            if map[key] == nil {
                map[key] = request
            }
        }
        return map
    }

    private var sortedSnapshots: [SessionSnapshot] {
        visibleActiveSessions
            .map { makeSnapshot(for: $0) }
            .sorted { lhs, rhs in
                if lhs.sortRank != rhs.sortRank {
                    return lhs.sortRank < rhs.sortRank
                }
                if lhs.activityDate != rhs.activityDate {
                    return lhs.activityDate > rhs.activityDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var visibleSnapshots: [SessionSnapshot] {
        sortedSnapshots
    }

    private var isDetailedPanelStyle: Bool {
        agentPanelStyle == .detailed
    }

    private var panelStackSpacing: CGFloat {
        isDetailedPanelStyle ? 9 : 6
    }

    private var listSpacing: CGFloat {
        isDetailedPanelStyle ? 7 : 4
    }

    private var outerPadding: CGFloat {
        isDetailedPanelStyle ? 9 : 6
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: panelStackSpacing) {
                if let errorMessage = manager.errorMessage?.trimmedNonEmpty {
                    statusBanner(errorMessage, tint: .red.opacity(0.7))
                } else if let permissionHintMessage {
                    statusBanner(permissionHintMessage, tint: .orange.opacity(0.65))
                } else if let actionStatusMessage {
                    statusBanner(actionStatusMessage, tint: .blue.opacity(0.6))
                }

                if visibleSnapshots.isEmpty {
                    emptyState
                } else {
                    AgentClosedSummaryView(
                        activeSessions: visibleActiveSessions.count,
                        pendingActions: visiblePendingActions.count,
                        totalTokens: manager.todayUsageSummary.totalTokens,
                        estimatedCostUSD: manager.todayUsageSummary.estimatedCostUSD,
                        scopeLabel: AgentLocalization.text("agents.summary.active"),
                        isRefreshing: manager.isRefreshing,
                        lastRefreshAt: manager.todayUsageSummary.updatedAt,
                        panelStyle: agentPanelStyle
                    )

                    LazyVStack(spacing: listSpacing) {
                        ForEach(visibleSnapshots) { snapshot in
                            AgentSessionRowView(
                                snapshot: snapshot.cardSnapshot,
                                panelStyle: agentPanelStyle,
                                onJump: {
                                    jump(snapshot.session)
                                },
                                onApprove: { _ in
                                    guard let request = snapshot.request else { return }
                                    approve(request)
                                },
                                onApproveChoice: { _, choice in
                                    guard let request = snapshot.request else { return }
                                    handleApprovalChoice(request, choice: choice)
                                },
                                onDeny: { _ in
                                    guard let request = snapshot.request else { return }
                                    deny(request)
                                },
                                onAnswerChoice: { _, choice in
                                    guard let request = snapshot.request else { return }
                                    answer(request, text: choice)
                                },
                                onAnswerText: { _, text in
                                    guard let request = snapshot.request else { return }
                                    answer(request, text: text)
                                }
                            )
                            .id("\(snapshot.id)-\(agentPanelStyle.rawValue)")
                        }
                    }
                }
            }
            .padding(outerPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.001))
        .task {
            await manager.refresh(includeFilesystem: false)
            Task(priority: .utility) {
                await manager.refresh(force: false, includeFilesystem: true)
            }
        }
        .onDisappear {
            actionStatusClearTask?.cancel()
            actionStatusClearTask = nil
        }
    }

    @ViewBuilder
    private func statusBanner(_ message: String, tint: Color) -> some View {
        Text(message)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.96))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AgentLocalization.text("agents.empty.title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(emptyStateMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SettingsWindowController.shared.showWindow()
            } label: {
                Label(AgentLocalization.text("agents.empty.open_settings"), systemImage: "gearshape")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.16))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var emptyStateMessage: String {
        if !deniedProviders.isEmpty {
            return AgentLocalization.format(
                "agents.permission.empty_message",
                deniedProviderLabel
            )
        }
        return AgentLocalization.text("agents.empty.default_message")
    }

    private func makeSnapshot(for session: AgentSessionMeta) -> SessionSnapshot {
        let request = latestPendingActionBySession[session.id]
        let usageText = usageText(for: session.usage)
        let detailText = request?.message?.trimmedNonEmpty ?? request?.details?.trimmedNonEmpty ?? session.summary?.trimmedNonEmpty
        let subagents = cardSubagents(for: session, request: request)
        let projectPath = request?.projectDir?.trimmedNonEmpty ?? session.projectDir?.trimmedNonEmpty
        let providerLabel = request?.sourceAlias?.trimmedNonEmpty
            ?? session.sourceAlias?.trimmedNonEmpty
            ?? session.provider.displayName

        let actionSnapshot: AgentSessionCardView.Snapshot.Action? = request.map { action in
            let actionKind = cardActionKind(for: action)
            return AgentSessionCardView.Snapshot.Action(
                id: action.id,
                kind: actionKind,
                title: action.title,
                prompt: action.message?.trimmedNonEmpty ?? action.details?.trimmedNonEmpty,
                choices: action.options,
                placeholder: action.kind == .question ? AgentLocalization.text("agents.action.type_reply") : nil
            )
        }

        let snapshot = AgentSessionCardView.Snapshot(
            id: session.id,
            provider: providerLabel,
            title: session.title,
            state: session.state.displayLabel,
            elapsedText: Self.relativeFormatter.localizedString(for: session.lastActiveAt, relativeTo: Date()),
            usageText: usageText,
            detailText: detailText,
            projectPath: projectPath,
            subagents: subagents,
            pendingActionCount: session.pendingActionCount,
            highlightState: session.state.highlightState,
            action: actionSnapshot,
            isJumpEnabled: enableAgentJumpAction
        )

        return SessionSnapshot(
            session: session,
            request: request,
            title: session.title,
            cardSnapshot: snapshot,
            state: session.state,
            activityDate: session.lastActiveAt,
            sortRank: session.state.sortRank
        )
    }

    private func cardSubagents(for session: AgentSessionMeta, request: AgentActionRequest?) -> [AgentSessionCardView.Snapshot.Subagent] {
        var merged: [AgentSubagentMeta] = []
        var seen = Set<String>()

        let candidates: [AgentSubagentMeta] = {
            var values: [AgentSubagentMeta] = []
            if let primary = session.subagent {
                values.append(primary)
            }
            values.append(contentsOf: session.childSubagents)
            if let requestSubagent = request?.subagent {
                values.append(requestSubagent)
            }
            return values
        }()

        for candidate in candidates {
            let normalizedName = candidate.displayName.trimmedNonEmpty ?? candidate.id
            let dedupeKey = "\(candidate.id.lowercased())::\(candidate.parentThreadId?.lowercased() ?? "")::\(normalizedName.lowercased())"
            guard seen.insert(dedupeKey).inserted else { continue }
            merged.append(candidate)
        }

        return merged.map { meta in
            AgentSessionCardView.Snapshot.Subagent(
                id: meta.id,
                name: meta.displayName,
                role: meta.role,
                type: meta.type
            )
        }
    }

    private func usageText(for usage: AgentUsageSnapshot?) -> String? {
        guard let usage else { return nil }
        var pieces: [String] = []
        if let totalTokens = usage.totalTokens {
            let tokenCount = Self.numberFormatter.string(from: NSNumber(value: totalTokens)) ?? "\(totalTokens)"
            pieces.append(AgentLocalization.format("agents.usage.tokens_format", tokenCount))
        }
        if let turnCount = usage.turnCount {
            pieces.append(AgentLocalization.format("agents.usage.turns_format", "\(turnCount)"))
        }
        if let cost = usage.estimatedCostUSD {
            pieces.append(Self.costFormatter.string(from: NSNumber(value: cost)) ?? String(format: "$%.2f", cost))
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " • ")
    }

    private func cardActionKind(for request: AgentActionRequest) -> AgentSessionCardView.Snapshot.Action.Kind {
        if request.kind == .question {
            return .question
        }
        if isLikelyPlanReview(request) {
            return .planReview
        }
        return .approve
    }

    private func isLikelyPlanReview(_ request: AgentActionRequest) -> Bool {
        let combined = [
            request.title?.trimmedNonEmpty,
            request.message?.trimmedNonEmpty,
            request.details?.trimmedNonEmpty
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        .lowercased()

        if combined.contains("plan") || combined.contains("diff") || combined.contains("patch") {
            return true
        }

        let markdownMarkers = ["```", "# ", "## ", "- ", "* ", "1. ", "|"]
        return markdownMarkers.contains(where: { combined.contains($0) })
    }

    private func jump(_ session: AgentSessionMeta) {
        guard enableAgentJumpAction else { return }
        Task {
            let success = await manager.jump(to: session)
            if success {
                showActionStatusMessage(
                    AgentLocalization.format(
                        "agents.action.opened_terminal",
                        session.provider.displayName
                    )
                )
            }
        }
    }

    private func approve(_ request: AgentActionRequest, mode: AgentApprovalMode = .standard) {
        Task {
            if await manager.approve(request, mode: mode) {
                let statusText: String
                switch mode {
                case .standard:
                    statusText = AgentLocalization.format(
                        "agents.action.approved_request",
                        request.requestId
                    )
                case .alwaysAllow:
                    statusText = "Always allow enabled for \(request.provider.displayName)"
                case .bypass:
                    statusText = "Bypass enabled for \(request.provider.displayName)"
                }
                showActionStatusMessage(
                    statusText
                )
            }
        }
    }

    private func deny(_ request: AgentActionRequest) {
        Task {
            if await manager.deny(request) {
                showActionStatusMessage(
                    AgentLocalization.format(
                        "agents.action.denied_request",
                        request.requestId
                    )
                )
            }
        }
    }

    private func answer(_ request: AgentActionRequest, text: String) {
        Task {
            if await manager.answer(request, text: text) {
                showActionStatusMessage(
                    AgentLocalization.format(
                        "agents.action.reply_sent",
                        request.provider.displayName
                    )
                )
            }
        }
    }

    private func handleApprovalChoice(_ request: AgentActionRequest, choice: String) {
        let token = normalizedApprovalChoice(choice)
        if token.contains("deny") || token.contains("reject") || token.contains("decline") {
            deny(request)
            return
        }

        if token.contains("always") || token.contains("forever") || token.contains("persist") {
            approve(request, mode: .alwaysAllow)
            return
        }

        if token.contains("bypass") || token.contains("skip") || token.contains("override") {
            approve(request, mode: .bypass)
            return
        }

        if token.contains("allow") || token.contains("approve") || token.contains("continue") {
            approve(request)
            return
        }

        // Fallback for provider-specific option labels that are not parseable as approval modes.
        answer(request, text: choice)
    }

    private func normalizedApprovalChoice(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }

    private func showActionStatusMessage(_ message: String) {
        actionStatusMessage = message
        actionStatusClearTask?.cancel()
        actionStatusClearTask = Task { [message] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if actionStatusMessage == message {
                    actionStatusMessage = nil
                }
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let costFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
}

private struct SessionSnapshot: Identifiable {
    let session: AgentSessionMeta
    let request: AgentActionRequest?
    let title: String
    let cardSnapshot: AgentSessionCardView.Snapshot
    let state: AgentSessionState
    let activityDate: Date
    let sortRank: Int

    var id: String { cardSnapshot.id }
}

private extension AgentSessionState {
    var displayLabel: String {
        switch self {
        case .idle: return AgentLocalization.text("agents.status.idle")
        case .running: return AgentLocalization.text("agents.status.running")
        case .waitingApproval: return AgentLocalization.text("agents.status.waiting_approval")
        case .waitingQuestion: return AgentLocalization.text("agents.status.waiting_question")
        case .completed: return AgentLocalization.text("agents.status.completed")
        case .failed: return AgentLocalization.text("agents.status.failed")
        }
    }

    var highlightState: AgentSessionCardView.Snapshot.HighlightState {
        switch self {
        case .idle: return .idle
        case .running: return .running
        case .waitingApproval: return .waitingApproval
        case .waitingQuestion: return .waitingQuestion
        case .completed: return .completed
        case .failed: return .failed
        }
    }

    var sortRank: Int {
        switch self {
        case .waitingApproval, .waitingQuestion:
            return 0
        case .running:
            return 1
        case .completed:
            return 2
        case .failed:
            return 3
        case .idle:
            return 4
        }
    }

    var isActive: Bool {
        switch self {
        case .running, .waitingApproval, .waitingQuestion:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    var isDone: Bool {
        switch self {
        case .completed, .failed:
            return true
        case .idle, .running, .waitingApproval, .waitingQuestion:
            return false
        }
    }
}
