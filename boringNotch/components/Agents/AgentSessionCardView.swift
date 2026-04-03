//
//  AgentSessionCardView.swift
//  boringNotch
//

import SwiftUI

struct AgentSessionCardView: View {
    struct Snapshot: Identifiable, Equatable {
        struct Subagent: Identifiable, Equatable {
            let id: String
            let name: String
            let role: String?
            let type: String?

            var secondaryLabel: String? {
                if let role = role?.trimmedNonEmpty {
                    return role
                }
                if let type = type?.trimmedNonEmpty {
                    return type
                }
                return nil
            }
        }

        struct Action: Identifiable, Equatable {
            enum Kind: Equatable {
                case approve
                case question
                case planReview
                case other(String)

                var badgeLabel: String {
                    switch self {
                    case .approve:
                        return AgentLocalization.text("agents.card.approve")
                    case .question:
                        return "Question"
                    case .planReview:
                        return "Plan Review"
                    case .other(let value):
                        return value
                    }
                }

                var symbolName: String {
                    switch self {
                    case .approve:
                        return "checkmark.circle.fill"
                    case .question:
                        return "questionmark.circle.fill"
                    case .planReview:
                        return "doc.text.magnifyingglass"
                    case .other:
                        return "bolt.horizontal.circle.fill"
                    }
                }
            }

            let id: String
            let kind: Kind
            let title: String?
            let prompt: String?
            let choices: [String]
            let placeholder: String?
        }

        enum HighlightState: Equatable {
            case waitingApproval
            case waitingQuestion
            case running
            case completed
            case failed
            case idle
        }

        let id: String
        let provider: String
        let title: String
        let state: String
        let elapsedText: String?
        let usageText: String?
        let detailText: String?
        let projectPath: String?
        let subagents: [Subagent]
        let pendingActionCount: Int
        let highlightState: HighlightState
        let action: Action?
        let isJumpEnabled: Bool
    }

    let snapshot: Snapshot
    let panelStyle: AgentPanelStyle
    let onJump: () -> Void
    let onApprove: ((Snapshot.Action) -> Void)?
    let onApproveChoice: ((Snapshot.Action, String) -> Void)?
    let onDeny: ((Snapshot.Action) -> Void)?
    let onAnswerChoice: ((Snapshot.Action, String) -> Void)?
    let onAnswerText: ((Snapshot.Action, String) -> Void)?

    init(
        snapshot: Snapshot,
        panelStyle: AgentPanelStyle,
        onJump: @escaping () -> Void,
        onApprove: ((Snapshot.Action) -> Void)? = nil,
        onApproveChoice: ((Snapshot.Action, String) -> Void)? = nil,
        onDeny: ((Snapshot.Action) -> Void)? = nil,
        onAnswerChoice: ((Snapshot.Action, String) -> Void)? = nil,
        onAnswerText: ((Snapshot.Action, String) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.panelStyle = panelStyle
        self.onJump = onJump
        self.onApprove = onApprove
        self.onApproveChoice = onApproveChoice
        self.onDeny = onDeny
        self.onAnswerChoice = onAnswerChoice
        self.onAnswerText = onAnswerText
    }

    var body: some View {
        AgentSessionRowView(
            snapshot: snapshot,
            panelStyle: panelStyle,
            onJump: onJump,
            onApprove: onApprove,
            onApproveChoice: onApproveChoice,
            onDeny: onDeny,
            onAnswerChoice: onAnswerChoice,
            onAnswerText: onAnswerText
        )
    }
}
