//
//  AgentSessionRowView.swift
//  boringNotch
//

import SwiftUI

struct AgentSessionRowView: View {
    let snapshot: AgentSessionCardView.Snapshot
    let panelStyle: AgentPanelStyle
    let onJump: () -> Void
    let onApprove: ((AgentSessionCardView.Snapshot.Action) -> Void)?
    let onApproveChoice: ((AgentSessionCardView.Snapshot.Action, String) -> Void)?
    let onDeny: ((AgentSessionCardView.Snapshot.Action) -> Void)?
    let onAnswerChoice: ((AgentSessionCardView.Snapshot.Action, String) -> Void)?
    let onAnswerText: ((AgentSessionCardView.Snapshot.Action, String) -> Void)?

    @State private var answerDraft: String
    @State private var isDetailsExpanded: Bool

    init(
        snapshot: AgentSessionCardView.Snapshot,
        panelStyle: AgentPanelStyle,
        onJump: @escaping () -> Void,
        onApprove: ((AgentSessionCardView.Snapshot.Action) -> Void)? = nil,
        onApproveChoice: ((AgentSessionCardView.Snapshot.Action, String) -> Void)? = nil,
        onDeny: ((AgentSessionCardView.Snapshot.Action) -> Void)? = nil,
        onAnswerChoice: ((AgentSessionCardView.Snapshot.Action, String) -> Void)? = nil,
        onAnswerText: ((AgentSessionCardView.Snapshot.Action, String) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.panelStyle = panelStyle
        self.onJump = onJump
        self.onApprove = onApprove
        self.onApproveChoice = onApproveChoice
        self.onDeny = onDeny
        self.onAnswerChoice = onAnswerChoice
        self.onAnswerText = onAnswerText
        _answerDraft = State(initialValue: "")
        _isDetailsExpanded = State(initialValue: false)
    }

    private var isDetailedLayout: Bool {
        panelStyle == .detailed
    }

    private var rowCornerRadius: CGFloat {
        isDetailedLayout ? 12 : 10
    }

    private var rowPadding: EdgeInsets {
        isDetailedLayout
        ? EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 11)
        : EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
    }

    private var rowMinHeight: CGFloat {
        if snapshot.action != nil {
            return isDetailedLayout ? 76 : 50
        }
        return isDetailedLayout ? 62 : 40
    }

    private var hasAction: Bool {
        snapshot.action != nil
    }

    private var collapsedDetailText: String? {
        guard !hasAction else { return nil }
        guard isDetailedLayout else { return nil }
        return snapshot.detailText?.trimmedNonEmpty
    }

    private var subagentSummaryText: String? {
        guard !snapshot.subagents.isEmpty else { return nil }

        let names = snapshot.subagents
            .prefix(isDetailedLayout ? 3 : 2)
            .map { $0.name.trimmedNonEmpty ?? $0.id }
        guard !names.isEmpty else { return nil }

        if snapshot.subagents.count > names.count {
            return "\(names.joined(separator: " · ")) +\(snapshot.subagents.count - names.count)"
        }
        return names.joined(separator: " · ")
    }

    private var pendingText: String? {
        snapshot.pendingActionCount > 0 ? "\(snapshot.pendingActionCount)" : nil
    }

    private var detailedSecondaryLineText: String? {
        guard isDetailedLayout else { return nil }

        var components: [String] = []
        if let usageText = snapshot.usageText?.trimmedNonEmpty {
            components.append(usageText)
        }
        if let detailText = snapshot.detailText?.trimmedNonEmpty {
            components.append(detailText)
        } else if let projectPath = snapshot.projectPath?.trimmedNonEmpty {
            components.append(projectPath)
        }

        guard !components.isEmpty else { return nil }
        return components.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isDetailedLayout ? 6 : 5) {
            headerRow

            if let detailedSecondaryLineText {
                detailContentView(detailedSecondaryLineText, preferredLineLimit: 2)
            } else if let collapsedDetailText {
                detailContentView(collapsedDetailText, preferredLineLimit: 1)
            }

            if let action = snapshot.action {
                actionStrip(for: action)

                if isDetailsExpanded && shouldShowExpandedDetails(for: action) {
                    expandedActionDetails(for: action)
                }
            }
        }
        .padding(rowPadding)
        .frame(minHeight: rowMinHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundFill)
        .overlay(backgroundBorder)
        .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(providerAccent.opacity(0.78))
                .frame(width: isDetailedLayout ? 7 : 6, height: isDetailedLayout ? 7 : 6)
                .padding(.top, 2)

            providerTag

            Text(snapshot.title)
                .font(isDetailedLayout ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            HStack(spacing: 4) {
                statusTag(text: snapshot.state, tint: stateTint)

                if isDetailedLayout, let elapsedText = snapshot.elapsedText?.trimmedNonEmpty {
                    metricTag(icon: "clock", text: elapsedText, tint: .secondary)
                }

                if let pendingText {
                    metricTag(icon: "bolt.horizontal.circle.fill", text: pendingText, tint: .yellow)
                }

                if isDetailedLayout, let subagentSummaryText {
                    metricTag(icon: "person.2.fill", text: subagentSummaryText, tint: .cyan)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

        }
    }

    @ViewBuilder
    private func actionStrip(for action: AgentSessionCardView.Snapshot.Action) -> some View {
        let approvalOptions = approvalQuickChoices(for: action)
        HStack(spacing: 6) {
            if shouldShowDetailsToggle(for: action) {
                rowActionButton(
                    title: actionToggleLabel(for: action),
                    systemImage: isDetailsExpanded ? "chevron.up" : "chevron.down",
                    tint: action.kind == .question ? Color.yellow.opacity(0.28) : Color.white.opacity(0.12)
                ) {
                    isDetailsExpanded.toggle()
                }
            }

            if showsApprovalControls(for: action) {
                rowActionButton(
                    title: AgentLocalization.text("agents.card.approve"),
                    systemImage: "checkmark",
                    tint: .green.opacity(0.9)
                ) {
                    onApprove?(action)
                }

                rowActionButton(
                    title: AgentLocalization.text("agents.card.deny"),
                    systemImage: "xmark",
                    tint: .red.opacity(0.9)
                ) {
                    onDeny?(action)
                }

                ForEach(approvalOptions, id: \.self) { choice in
                    rowActionButton(
                        title: approvalOptionButtonTitle(choice),
                        systemImage: approvalOptionSymbol(choice),
                        tint: approvalOptionTint(choice)
                    ) {
                        onApproveChoice?(action, choice)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func expandedActionDetails(for action: AgentSessionCardView.Snapshot.Action) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = action.title?.trimmedNonEmpty {
                Text(title)
                    .font(isDetailedLayout ? .callout.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let prompt = action.prompt?.trimmedNonEmpty {
                let preferMarkdown = shouldPrioritizePlanSnippet(for: action)
                detailContentView(
                    prompt,
                    preferredLineLimit: isDetailedLayout ? (preferMarkdown ? 8 : 4) : (preferMarkdown ? 4 : 2),
                    preferMarkdown: preferMarkdown
                )
            }

            if case .question = action.kind {
                if !action.choices.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: isDetailedLayout ? 88 : 74), spacing: 5)],
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(action.choices, id: \.self) { choice in
                            Button {
                                onAnswerChoice?(action, choice)
                                isDetailsExpanded = false
                            } label: {
                                Text(choice)
                                    .font(isDetailedLayout ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.vertical, isDetailedLayout ? 5 : 4)
                                    .padding(.horizontal, isDetailedLayout ? 10 : 8)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
                            )
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField(
                        action.placeholder ?? AgentLocalization.text("agents.action.type_reply"),
                        text: $answerDraft,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lineLimit(isDetailedLayout ? 1...3 : 1...2)
                    .padding(.horizontal, isDetailedLayout ? 10 : 8)
                    .padding(.vertical, isDetailedLayout ? 7 : 6)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: isDetailedLayout ? 10 : 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: isDetailedLayout ? 10 : 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .onSubmit {
                        submitAnswer(for: action)
                    }

                    Button {
                        submitAnswer(for: action)
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(isDetailedLayout ? .callout.weight(.semibold) : .caption.weight(.semibold))
                            .frame(width: isDetailedLayout ? 28 : 24, height: isDetailedLayout ? 28 : 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.white.opacity(isDetailedLayout ? 0.18 : 0.16))
                    .clipShape(Circle())
                    .disabled(answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(isDetailedLayout ? 10 : 8)
        .background(
            RoundedRectangle(cornerRadius: isDetailedLayout ? 11 : 10, style: .continuous)
                .fill(Color.yellow.opacity(snapshot.highlightState == .waitingQuestion ? (isDetailedLayout ? 0.14 : 0.10) : (isDetailedLayout ? 0.09 : 0.07)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: isDetailedLayout ? 11 : 10, style: .continuous)
                .stroke(Color.yellow.opacity(snapshot.highlightState == .waitingQuestion ? 0.34 : 0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func rowActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(isDetailedLayout ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                .padding(.horizontal, isDetailedLayout ? 10 : 8)
                .padding(.vertical, isDetailedLayout ? 6 : 4)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(tint)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var providerTag: some View {
        HStack(spacing: 3) {
            Image(systemName: providerSymbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
            Text(snapshot.provider)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    private var providerSymbolName: String {
        let normalized = snapshot.provider.lowercased()
        if normalized.contains("claude") {
            return "sparkles"
        }
        if normalized.contains("codex") {
            return "chevron.left.forwardslash.chevron.right"
        }
        if normalized.contains("gemini") {
            return "star.circle.fill"
        }
        if normalized.contains("cursor") {
            return "cursorarrow.rays"
        }
        if normalized.contains("droid") {
            return "cpu.fill"
        }
        if normalized.contains("opencode") {
            return "terminal.fill"
        }
        if normalized.contains("openclaw") {
            return "pawprint.fill"
        }
        return "circle.fill"
    }

    @ViewBuilder
    private func statusTag(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func metricTag(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font((isDetailedLayout ? Font.caption : Font.caption2).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, isDetailedLayout ? 6 : 4)
        .padding(.vertical, isDetailedLayout ? 3 : 2)
        .background(Color.black.opacity(0.10))
        .clipShape(Capsule())
    }

    private var backgroundFill: some ShapeStyle {
        switch snapshot.highlightState {
        case .waitingApproval, .waitingQuestion:
            return AnyShapeStyle(Color.white.opacity(snapshot.action == nil ? (isDetailedLayout ? 0.09 : 0.065) : (isDetailedLayout ? 0.11 : 0.085)))
        case .running:
            return AnyShapeStyle(Color.white.opacity(isDetailedLayout ? 0.07 : 0.05))
        case .completed, .failed, .idle:
            return AnyShapeStyle(Color.white.opacity(isDetailedLayout ? 0.05 : 0.035))
        }
    }

    private var backgroundBorder: some View {
        RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
            .stroke(borderColor, lineWidth: snapshot.highlightState == .idle ? 1 : (isDetailedLayout ? 1.2 : 1.1))
    }

    private var borderColor: Color {
        switch snapshot.highlightState {
        case .waitingApproval, .waitingQuestion:
            return Color.yellow.opacity(snapshot.action == nil ? (isDetailedLayout ? 0.52 : 0.38) : (isDetailedLayout ? 0.7 : 0.58))
        case .running:
            return Color.blue.opacity(isDetailedLayout ? 0.42 : 0.34)
        case .completed:
            return Color.green.opacity(isDetailedLayout ? 0.4 : 0.3)
        case .failed:
            return Color.red.opacity(isDetailedLayout ? 0.48 : 0.4)
        case .idle:
            return Color.white.opacity(isDetailedLayout ? 0.12 : 0.08)
        }
    }

    private var stateTint: Color {
        switch snapshot.highlightState {
        case .waitingApproval, .waitingQuestion:
            return .yellow
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .idle:
            return .secondary
        }
    }

    private var providerAccent: Color {
        switch snapshot.highlightState {
        case .waitingApproval, .waitingQuestion:
            return .yellow
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .idle:
            return .white
        }
    }

    private func submitAnswer(for action: AgentSessionCardView.Snapshot.Action) {
        let trimmed = answerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAnswerText?(action, trimmed)
        answerDraft = ""
        isDetailsExpanded = false
    }

    @ViewBuilder
    private func detailContentView(
        _ content: String,
        preferredLineLimit: Int,
        preferMarkdown: Bool? = nil
    ) -> some View {
        let shouldRenderMarkdown = preferMarkdown ?? looksLikeMarkdown(content)
        if shouldRenderMarkdown,
           let attributed = try? AttributedString(
               markdown: content,
               options: AttributedString.MarkdownParsingOptions(
                   interpretedSyntax: .full,
                   failurePolicy: .returnPartiallyParsedIfPossible
               )
           ) {
            Text(attributed)
                .font(isDetailedLayout ? .callout : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(preferredLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text(content)
                .font(isDetailedLayout ? .callout : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(preferredLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func actionToggleLabel(for action: AgentSessionCardView.Snapshot.Action) -> String {
        switch action.kind {
        case .question:
            return "Answer"
        case .planReview:
            return "Review"
        case .approve:
            return AgentLocalization.text("agents.card.approve")
        case .other:
            return "Details"
        }
    }

    private func shouldShowDetailsToggle(for action: AgentSessionCardView.Snapshot.Action) -> Bool {
        switch action.kind {
        case .question, .planReview:
            return true
        case .approve:
            return action.prompt?.trimmedNonEmpty != nil || snapshot.detailText?.trimmedNonEmpty != nil
        case .other:
            return action.prompt?.trimmedNonEmpty != nil || snapshot.detailText?.trimmedNonEmpty != nil
        }
    }

    private func approvalQuickChoices(for action: AgentSessionCardView.Snapshot.Action) -> [String] {
        guard showsApprovalControls(for: action) else { return [] }

        return action.choices
            .compactMap { $0.trimmedNonEmpty }
            .filter { choice in
                let lowered = normalizedChoiceToken(choice)
                return lowered.contains("always")
                    || lowered.contains("forever")
                    || lowered.contains("persist")
                    || lowered.contains("bypass")
                    || lowered.contains("skip")
                    || lowered.contains("override")
            }
            .prefix(2)
            .map { $0 }
    }

    private func normalizedChoiceToken(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }

    private func approvalOptionButtonTitle(_ choice: String) -> String {
        let lowered = normalizedChoiceToken(choice)
        if lowered.contains("always") || lowered.contains("forever") || lowered.contains("persist") {
            return "Always"
        }
        if lowered.contains("bypass") || lowered.contains("skip") || lowered.contains("override") {
            return "Bypass"
        }
        return choice
    }

    private func approvalOptionTint(_ choice: String) -> Color {
        let lowered = normalizedChoiceToken(choice)
        if lowered.contains("always") || lowered.contains("forever") || lowered.contains("persist") {
            return .orange.opacity(0.9)
        }
        if lowered.contains("bypass") || lowered.contains("skip") || lowered.contains("override") {
            return .yellow.opacity(0.78)
        }
        return .white.opacity(0.22)
    }

    private func approvalOptionSymbol(_ choice: String) -> String {
        let lowered = normalizedChoiceToken(choice)
        if lowered.contains("always") || lowered.contains("forever") || lowered.contains("persist") {
            return "checkmark.seal.fill"
        }
        if lowered.contains("bypass") || lowered.contains("skip") || lowered.contains("override") {
            return "bolt.shield"
        }
        return "checkmark.circle"
    }

    private func shouldShowExpandedDetails(for action: AgentSessionCardView.Snapshot.Action) -> Bool {
        switch action.kind {
        case .question:
            return true
        case .planReview:
            return true
        case .approve, .other:
            return action.prompt?.trimmedNonEmpty != nil || snapshot.detailText?.trimmedNonEmpty != nil
        }
    }

    private func shouldPrioritizePlanSnippet(for action: AgentSessionCardView.Snapshot.Action) -> Bool {
        guard let prompt = action.prompt?.trimmedNonEmpty else { return false }
        return isPlanAction(action) || looksLikeMarkdown(prompt)
    }

    private func isPlanAction(_ action: AgentSessionCardView.Snapshot.Action) -> Bool {
        if case .planReview = action.kind {
            return true
        }
        return false
    }

    private func looksLikeMarkdown(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let markers = ["```", "# ", "## ", "- ", "* ", "1. ", "> ", "|", "`"]
        return markers.contains(where: { trimmed.contains($0) })
    }

    private func showsApprovalControls(for action: AgentSessionCardView.Snapshot.Action) -> Bool {
        switch action.kind {
        case .approve, .planReview:
            return true
        case .question, .other:
            return false
        }
    }
}
