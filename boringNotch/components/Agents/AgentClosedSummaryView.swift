//
//  AgentClosedSummaryView.swift
//  boringNotch
//

import SwiftUI

struct AgentClosedSummaryView: View {
    let activeSessions: Int
    let pendingActions: Int
    let totalTokens: Int?
    let estimatedCostUSD: Double?
    let scopeLabel: String
    let isRefreshing: Bool
    let lastRefreshAt: Date?
    let panelStyle: AgentPanelStyle

    init(
        activeSessions: Int,
        pendingActions: Int,
        totalTokens: Int?,
        estimatedCostUSD: Double?,
        scopeLabel: String,
        isRefreshing: Bool,
        lastRefreshAt: Date?,
        panelStyle: AgentPanelStyle
    ) {
        self.activeSessions = activeSessions
        self.pendingActions = pendingActions
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.scopeLabel = scopeLabel
        self.isRefreshing = isRefreshing
        self.lastRefreshAt = lastRefreshAt
        self.panelStyle = panelStyle
    }

    var body: some View {
        HStack(spacing: panelStyle == .detailed ? 6 : 4) {
            if panelStyle == .detailed {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isRefreshing ? Color.cyan : Color.green)
                        .frame(width: 5, height: 5)
                    Text(scopeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }

            metricChip(
                icon: "person.2.fill",
                value: "\(activeSessions)",
                tint: .green
            )
            metricChip(
                icon: pendingActions > 0 ? "bolt.horizontal.circle.fill" : "checkmark.circle.fill",
                value: "\(pendingActions)",
                tint: pendingActions > 0 ? .yellow : .green
            )

            if panelStyle == .detailed {
                metricChip(
                    icon: "number",
                    value: totalTokens.map { Self.numberFormatter.string(from: NSNumber(value: $0)) ?? "\($0)" } ?? "—",
                    tint: .white
                )
                metricChip(
                    icon: "dollarsign.circle.fill",
                    value: estimatedCostUSD.map { Self.currencyFormatter.string(from: NSNumber(value: $0)) ?? Self.fallbackCostString(for: $0) } ?? "—",
                    tint: .white
                )

                Spacer(minLength: 0)

                Text(refreshValue)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(panelStyle == .detailed ? 8 : 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundFill)
        .overlay(backgroundBorder)
        .clipShape(RoundedRectangle(cornerRadius: panelStyle == .detailed ? 12 : 10, style: .continuous))
    }

    private var refreshStatusText: String {
        if isRefreshing {
            return AgentLocalization.text("agents.status.running")
        }
        guard let lastRefreshAt else {
            return "—"
        }
        return Self.relativeFormatter.localizedString(for: lastRefreshAt, relativeTo: Date())
    }

    private var refreshValue: String {
        if isRefreshing {
            return "…"
        }
        guard let lastRefreshAt else {
            return "—"
        }
        return Self.relativeFormatter.localizedString(for: lastRefreshAt, relativeTo: Date())
    }

    @ViewBuilder
    private func metricChip(icon: String, value: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 10, height: 10)

            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
        .background(Color.black.opacity(0.14))
        .clipShape(Capsule())
        .overlay(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private var backgroundFill: some ShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: panelStyle == .detailed
                ? [Color.white.opacity(0.08), Color.white.opacity(0.045)]
                : [Color.white.opacity(0.05), Color.white.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var backgroundBorder: some View {
        RoundedRectangle(cornerRadius: panelStyle == .detailed ? 12 : 10, style: .continuous)
            .stroke(Color.white.opacity(panelStyle == .detailed ? 0.1 : 0.07), lineWidth: 1)
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

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static func fallbackCostString(for value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
