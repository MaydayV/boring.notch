//
//  AgentsSettingsView.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI

struct AgentsSettingsView: View {
    private let hookInstaller = AgentHookInstaller()
    private let hookProviders: [AgentProvider] = AgentProvider.allCases
    private let agentHubManager = AgentHubManager.shared

    @Default(.agentPanelStyle) private var agentPanelStyle
    @Default(.claudeAgentRootBookmark) private var claudeAgentRootBookmark
    @Default(.codexAgentRootBookmark) private var codexAgentRootBookmark
    @Default(.geminiAgentRootBookmark) private var geminiAgentRootBookmark
    @Default(.cursorAgentRootBookmark) private var cursorAgentRootBookmark
    @Default(.openCodeAgentRootBookmark) private var openCodeAgentRootBookmark
    @Default(.droidAgentRootBookmark) private var droidAgentRootBookmark
    @Default(.openClawAgentRootBookmark) private var openClawAgentRootBookmark

    @State private var hookStatuses: [AgentHookProviderStatus] = []
    @State private var hookStatusMessage: String?
    @State private var isRepairingHooks = false
    @State private var isPreparingDiagnostics = false
    @State private var diagnosticsStatusMessage: String?
    @State private var selectedProviderPaths: [AgentProvider: String] = [:]
    @State private var hookStatusRefreshTask: Task<Void, Never>?

    private var bridgeCommandPath: String {
        AgentRuntimePaths.bridgeCommandURL.path
    }

    private var hookStatusesByProvider: [AgentProvider: AgentHookProviderStatus] {
        Dictionary(uniqueKeysWithValues: hookStatuses.map { ($0.provider, $0) })
    }

    var body: some View {
        Form {
            Section {
                panelStylePreview

                HStack(spacing: 12) {
                    styleOptionCard(
                        style: .compact,
                        title: AgentLocalization.text("agents.settings.style.compact"),
                        subtitle: AgentLocalization.text("agents.settings.style.compact_help"),
                        icon: "rectangle.grid.1x2.fill"
                    )

                    styleOptionCard(
                        style: .detailed,
                        title: AgentLocalization.text("agents.settings.style.detailed"),
                        subtitle: AgentLocalization.text("agents.settings.style.detailed_help"),
                        icon: "list.bullet.rectangle.portrait.fill"
                    )
                }
            } header: {
                Text(AgentLocalization.text("agents.settings.panel_style"))
            } footer: {
                Text(AgentLocalization.text("agents.settings.panel_style_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AgentLocalization.text("agents.settings.bridge_command"))
                            .font(.callout.weight(.semibold))
                        Text(bridgeCommandPath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button {
                        Task {
                            await repairHooks()
                        }
                    } label: {
                        if isRepairingHooks {
                            ProgressView()
                        } else {
                            Text(AgentLocalization.text("agents.settings.install_repair"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRepairingHooks)
                }
            } header: {
                Text(AgentLocalization.text("agents.settings.cli_hooks"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AgentLocalization.text("agents.settings.bridge_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let hookStatusMessage {
                        Text(hookStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await copyDiagnosticsReport()
                        }
                    } label: {
                        if isPreparingDiagnostics {
                            ProgressView()
                        } else {
                            Label("Copy diagnostics", systemImage: "doc.on.doc")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPreparingDiagnostics)

                    Button {
                        Task {
                            await exportDiagnosticsReport()
                        }
                    } label: {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPreparingDiagnostics)
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Export hook/session/action diagnostics for troubleshooting and issue reports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let diagnosticsStatusMessage {
                        Text(diagnosticsStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                providerToggleRow(
                    provider: .claude,
                    toggleKey: .showClaudeAgentProvider,
                    bookmarkData: claudeAgentRootBookmark
                )
                providerToggleRow(
                    provider: .codex,
                    toggleKey: .showCodexAgentProvider,
                    bookmarkData: codexAgentRootBookmark
                )
                providerToggleRow(
                    provider: .gemini,
                    toggleKey: .showGeminiAgentProvider,
                    bookmarkData: geminiAgentRootBookmark
                )
                providerToggleRow(
                    provider: .cursor,
                    toggleKey: .showCursorAgentProvider,
                    bookmarkData: cursorAgentRootBookmark
                )
                providerToggleRow(
                    provider: .opencode,
                    toggleKey: .showOpenCodeAgentProvider,
                    bookmarkData: openCodeAgentRootBookmark
                )
                providerToggleRow(
                    provider: .droid,
                    toggleKey: .showDroidAgentProvider,
                    bookmarkData: droidAgentRootBookmark
                )
                providerToggleRow(
                    provider: .openclaw,
                    toggleKey: .showOpenClawAgentProvider,
                    bookmarkData: openClawAgentRootBookmark
                )
            } header: {
                Text(AgentLocalization.text("agents.settings.providers"))
            } footer: {
                Text(AgentLocalization.text("agents.settings.providers_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            if hookStatuses.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text(AgentLocalization.text("agents.settings.cli_hooks_loading"))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                ForEach(hookProviders, id: \.self) { provider in
                                    hookStatusRow(for: provider)
                                }
                            }
                        }

                        Divider()

                        providerPathManagementRow(
                            provider: .claude,
                            bookmarkData: claudeAgentRootBookmark,
                            selectedPath: selectedProviderPaths[.claude],
                            select: { selectDirectory(for: .claude) },
                            clear: { clearDirectory(for: .claude) }
                        )
                        providerPathManagementRow(
                            provider: .codex,
                            bookmarkData: codexAgentRootBookmark,
                            selectedPath: selectedProviderPaths[.codex],
                            select: { selectDirectory(for: .codex) },
                            clear: { clearDirectory(for: .codex) }
                        )
                        providerPathManagementRow(
                            provider: .gemini,
                            bookmarkData: geminiAgentRootBookmark,
                            selectedPath: selectedProviderPaths[.gemini],
                            select: { selectDirectory(for: .gemini) },
                            clear: { clearDirectory(for: .gemini) }
                        )
                        providerPathManagementRow(
                            provider: .cursor,
                            bookmarkData: cursorAgentRootBookmark,
                            selectedPath: selectedProviderPaths[.cursor],
                            select: { selectDirectory(for: .cursor) },
                            clear: { clearDirectory(for: .cursor) }
                        )
                        providerPathManagementRow(
                            provider: .opencode,
                            bookmarkData: openCodeAgentRootBookmark,
                            selectedPath: selectedProviderPaths[.opencode],
                            select: { selectDirectory(for: .opencode) },
                            clear: { clearDirectory(for: .opencode) }
                        )
                        providerPathManagementRow(
                            provider: .droid,
                            bookmarkData: droidAgentRootBookmark,
                            selectedPath: selectedProviderPaths[.droid],
                            select: { selectDirectory(for: .droid) },
                            clear: { clearDirectory(for: .droid) }
                        )
                        providerPathManagementRow(
                            provider: .openclaw,
                            bookmarkData: openClawAgentRootBookmark,
                            selectedPath: selectedProviderPaths[.openclaw],
                            select: { selectDirectory(for: .openclaw) },
                            clear: { clearDirectory(for: .openclaw) }
                        )
                    }
                    .padding(.top, 4)
                } label: {
                    Text(AgentLocalization.text("agents.settings.advanced_troubleshooting"))
                }
            } footer: {
                Text(AgentLocalization.text("agents.settings.providers_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .showAgentsTab) {
                    Text(AgentLocalization.text("agents.settings.show_tab"))
                }

                Defaults.Toggle(key: .enableAgentJumpAction) {
                    Text(AgentLocalization.text("agents.settings.enable_jump"))
                }
            } header: {
                Text(AgentLocalization.text("agents.settings.general"))
            } footer: {
                Text(AgentLocalization.text("agents.settings.jump_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle(AgentLocalization.text("agents.title"))
        .task {
            refreshSelectedProviderPaths()
            scheduleHookStatusRefresh(immediate: true)
        }
        .onDisappear {
            hookStatusRefreshTask?.cancel()
            hookStatusRefreshTask = nil
        }
    }

    @ViewBuilder
    private var panelStylePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.17, green: 0.12, blue: 0.32),
                                Color(red: 0.14, green: 0.17, blue: 0.44),
                                Color(red: 0.28, green: 0.18, blue: 0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 96)

                HStack {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 8, height: 16)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                            .frame(width: 8, height: 12)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                            .frame(width: 8, height: 18)
                    }

                    Spacer(minLength: 0)

                    Text(AgentLocalization.format("agents.settings.preview.session_count", "2"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            Text(AgentLocalization.text("agents.settings.preview_help"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    private func styleOptionCard(
        style: AgentPanelStyle,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        Button {
            agentPanelStyle = style
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(style == agentPanelStyle ? .white : .secondary)
                        .padding(8)
                        .background(style == agentPanelStyle ? Color.accentColor.opacity(0.22) : Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Spacer(minLength: 0)
                }

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(style == agentPanelStyle ? Color.accentColor.opacity(0.10) : Color.black.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(style == agentPanelStyle ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func providerToggleRow(
        provider: AgentProvider,
        toggleKey: Defaults.Key<Bool>,
        bookmarkData: Data?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Defaults.Toggle(key: toggleKey) {
                Text(provider.displayName)
            }
            Spacer(minLength: 0)
            if bookmarkData != nil {
                Image(systemName: "folder.badge.checkmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func providerPathManagementRow(
        provider: AgentProvider,
        bookmarkData: Data?,
        selectedPath: String?,
        select: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        let status = hookStatusesByProvider[provider]
        let supportState = status?.supportState ?? .notInstalled
        let configPath = hookConfigPath(for: provider, status: status)
        let pathLabel = AgentLocalization.text("agents.settings.using_default_paths")

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(provider.displayName)
                    .font(.callout.weight(.semibold))

                Spacer(minLength: 0)

                Text(statusLabel(for: supportState))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint(for: supportState))
            }

            Text(statusContextLabel(status: status))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Path")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let selectedPath,
               shouldShowSelectedPath(provider: provider, selectedPath: selectedPath) {
                Text(selectedPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(pathLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(defaultScanPathsPreview(for: provider))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(configPath)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("Operation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(AgentLocalization.text("agents.settings.select_folder"), action: select)
                    .buttonStyle(.bordered)

                Button(AgentLocalization.text("agents.settings.clear"), role: .destructive, action: clear)
                    .buttonStyle(.bordered)
                    .disabled(bookmarkData == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func selectDirectory(for provider: AgentProvider) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = selectedDirectoryURL(for: provider)
        panel.prompt = AgentLocalization.text("agents.settings.select")
        panel.title = AgentLocalization.text("agents.settings.grant_folder_title")

        if panel.runModal() == .OK, let selectedURL = panel.url,
           let bookmarkData = try? selectedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
           ) {
            switch provider {
            case .claude:
                claudeAgentRootBookmark = bookmarkData
            case .codex:
                codexAgentRootBookmark = bookmarkData
            case .gemini:
                geminiAgentRootBookmark = bookmarkData
            case .cursor:
                cursorAgentRootBookmark = bookmarkData
            case .opencode:
                openCodeAgentRootBookmark = bookmarkData
            case .droid:
                droidAgentRootBookmark = bookmarkData
            case .openclaw:
                openClawAgentRootBookmark = bookmarkData
            }
            selectedProviderPaths[provider] = selectedURL.path
            scheduleHookStatusRefresh()
        }
    }

    private func selectedDirectoryURL(for provider: AgentProvider) -> URL {
        if let bookmarkData = bookmarkData(for: provider),
           let resolvedPath = resolvedPath(from: bookmarkData) {
            let resolvedURL = URL(fileURLWithPath: resolvedPath, isDirectory: true)
            let standardizedResolvedPath = resolvedURL.standardizedFileURL.path
            let homePath = AgentRuntimePaths.realHomeDirectoryURL.standardizedFileURL.path

            if standardizedResolvedPath == homePath,
               let providerRoot = AgentRuntimePaths.defaultAuthorizationRootURL(for: provider) {
                return providerRoot
            }

            return resolvedURL
        }

        if let providerRoot = AgentRuntimePaths.defaultAuthorizationRootURL(for: provider) {
            return providerRoot
        }

        return AgentRuntimePaths.realHomeDirectoryURL
    }

    private func bookmarkData(for provider: AgentProvider) -> Data? {
        switch provider {
        case .claude:
            return claudeAgentRootBookmark
        case .codex:
            return codexAgentRootBookmark
        case .gemini:
            return geminiAgentRootBookmark
        case .cursor:
            return cursorAgentRootBookmark
        case .opencode:
            return openCodeAgentRootBookmark
        case .droid:
            return droidAgentRootBookmark
        case .openclaw:
            return openClawAgentRootBookmark
        }
    }

    private func clearDirectory(for provider: AgentProvider) {
        switch provider {
        case .claude:
            claudeAgentRootBookmark = nil
        case .codex:
            codexAgentRootBookmark = nil
        case .gemini:
            geminiAgentRootBookmark = nil
        case .cursor:
            cursorAgentRootBookmark = nil
        case .opencode:
            openCodeAgentRootBookmark = nil
        case .droid:
            droidAgentRootBookmark = nil
        case .openclaw:
            openClawAgentRootBookmark = nil
        }
        selectedProviderPaths.removeValue(forKey: provider)

        scheduleHookStatusRefresh()
    }

    @ViewBuilder
    private func hookStatusRow(for provider: AgentProvider) -> some View {
        let status = hookStatusesByProvider[provider]
        let supportState = status?.supportState ?? .notInstalled
        let configPath = hookConfigPath(for: provider, status: status)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(provider.displayName)
                    .font(.callout.weight(.semibold))

                Spacer(minLength: 0)

                Text(statusLabel(for: supportState))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint(for: supportState))
            }

            Text(statusContextLabel(status: status))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(configPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func statusLabel(for supportState: AgentHookSupportState) -> String {
        switch supportState {
        case .installed:
            return AgentLocalization.text("agents.settings.hook_status.installed")
        case .notInstalled:
            return AgentLocalization.text("agents.settings.hook_status.not_installed")
        case .permissionRequired:
            return AgentLocalization.text("agents.settings.hook_status.permission_required")
        case .cliNotFound:
            return AgentLocalization.text("agents.settings.hook_status.cli_not_found")
        case .unsupported:
            return AgentLocalization.text("agents.settings.hook_status.unsupported")
        }
    }

    private func statusTint(for supportState: AgentHookSupportState) -> Color {
        switch supportState {
        case .installed:
            return .green
        case .notInstalled:
            return .secondary
        case .permissionRequired:
            return .orange
        case .cliNotFound:
            return .orange
        case .unsupported:
            return .secondary
        }
    }

    private func scheduleHookStatusRefresh(immediate: Bool = false) {
        hookStatusRefreshTask?.cancel()
        hookStatusRefreshTask = Task(priority: .utility) {
            if !immediate {
                try? await Task.sleep(nanoseconds: 160_000_000)
            }
            guard !Task.isCancelled else {
                return
            }
            let statuses = await inspectHookStatusesInBackground()
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                hookStatuses = statuses
            }
        }
    }

    private func repairHooks() async {
        await MainActor.run {
            isRepairingHooks = true
            hookStatusMessage = nil
        }

        let preflightStatuses = await inspectHookStatusesInBackground()
        let providersNeedAuthorization = providersNeedingAuthorization(from: preflightStatuses)
        if !providersNeedAuthorization.isEmpty {
            let granted = await requestAuthorizationBookmark(for: providersNeedAuthorization)
            if !granted {
                let refreshed = await inspectHookStatusesInBackground()
                await MainActor.run {
                    hookStatuses = refreshed
                    hookStatusMessage = hookInstallMessage(
                        base: AgentLocalization.text("agents.settings.hook_install_cancelled"),
                        statuses: refreshed,
                        limit: 3
                    )
                    isRepairingHooks = false
                }
                return
            }
        }

        do {
            try hookInstaller.installOrRepairHooks(for: hookProviders)
            let statuses = await inspectHookStatusesInBackground()
            await MainActor.run {
                hookStatuses = statuses
                hookStatusMessage = AgentLocalization.text("agents.settings.hook_install_success")
                isRepairingHooks = false
            }
        } catch {
            let statuses = await inspectHookStatusesInBackground()
            await MainActor.run {
                hookStatuses = statuses
                if statuses.contains(where: { $0.supportState == .permissionRequired }) {
                    hookStatusMessage = hookInstallMessage(
                        base: AgentLocalization.text("agents.settings.hook_install_permission_needed"),
                        statuses: statuses,
                        limit: 3
                    )
                } else {
                    hookStatusMessage = hookInstallMessage(
                        base: AgentLocalization.format(
                            "agents.settings.hook_install_failure",
                            error.localizedDescription
                        ),
                        statuses: statuses,
                        limit: 3
                    )
                }
                isRepairingHooks = false
            }
        }
    }

    private func inspectHookStatusesInBackground() async -> [AgentHookProviderStatus] {
        await Task(priority: .utility) {
            hookInstaller.inspectHookStatus(for: hookProviders)
        }.value
    }

    private func providersNeedingAuthorization(from statuses: [AgentHookProviderStatus]) -> [AgentProvider] {
        statuses
            .filter { $0.supportState == .permissionRequired }
            .map(\.provider)
            .filter { provider in
                switch provider {
                case .claude, .codex, .gemini:
                    return true
                case .cursor, .opencode, .droid, .openclaw:
                    return false
                }
            }
    }

    private func requestAuthorizationBookmark(for providers: [AgentProvider]) async -> Bool {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.showsHiddenFiles = true
            panel.directoryURL = providers.compactMap { AgentRuntimePaths.defaultAuthorizationRootURL(for: $0) }.first
                ?? AgentRuntimePaths.realHomeDirectoryURL
            panel.prompt = AgentLocalization.text("agents.settings.select")
            panel.title = AgentLocalization.text("agents.settings.grant_folder_title")

            guard panel.runModal() == .OK,
                  let selectedURL = panel.url,
                  let bookmarkData = try? selectedURL.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                  ) else {
                return false
            }

            for provider in providers {
                switch provider {
                case .claude:
                    claudeAgentRootBookmark = bookmarkData
                case .codex:
                    codexAgentRootBookmark = bookmarkData
                case .gemini:
                    geminiAgentRootBookmark = bookmarkData
                case .cursor:
                    cursorAgentRootBookmark = bookmarkData
                case .opencode:
                    openCodeAgentRootBookmark = bookmarkData
                case .droid:
                    droidAgentRootBookmark = bookmarkData
                case .openclaw:
                    openClawAgentRootBookmark = bookmarkData
                }
            }
            return true
        }
    }

    private func resolvedPath(from bookmarkData: Data?) -> String? {
        guard let bookmarkData, !bookmarkData.isEmpty else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return url.path
    }

    private func refreshSelectedProviderPaths() {
        var result: [AgentProvider: String] = [:]
        if let path = resolvedPath(from: claudeAgentRootBookmark) {
            result[.claude] = path
        }
        if let path = resolvedPath(from: codexAgentRootBookmark) {
            result[.codex] = path
        }
        if let path = resolvedPath(from: geminiAgentRootBookmark) {
            result[.gemini] = path
        }
        if let path = resolvedPath(from: cursorAgentRootBookmark) {
            result[.cursor] = path
        }
        if let path = resolvedPath(from: openCodeAgentRootBookmark) {
            result[.opencode] = path
        }
        if let path = resolvedPath(from: droidAgentRootBookmark) {
            result[.droid] = path
        }
        if let path = resolvedPath(from: openClawAgentRootBookmark) {
            result[.openclaw] = path
        }
        selectedProviderPaths = result
    }

    private func defaultScanPathsPreview(for provider: AgentProvider) -> String {
        AgentRuntimePaths.displayScanPaths(for: provider)
            .prefix(3)
            .joined(separator: "\n")
    }

    private func hookConfigPath(for provider: AgentProvider, status: AgentHookProviderStatus?) -> String {
        if let configPath = status?.configPath.trimmedNonEmpty {
            return "Config path: \(configPath)"
        }

        guard let defaultConfigURL = AgentRuntimePaths.defaultHookConfigURL(for: provider) else {
            return "Config path: unavailable"
        }
        return "Config path: \(defaultConfigURL.path)"
    }

    private func statusContextLabel(status: AgentHookProviderStatus?) -> String {
        let supportState = status?.supportState ?? .notInstalled
        return "Status: \(statusLabel(for: supportState))"
    }

    private func hookInstallMessage(base: String, statuses: [AgentHookProviderStatus], limit: Int) -> String {
        let diagnostics = statuses
            .filter { $0.supportState != .installed }
            .prefix(limit)
            .map(diagnosticSummary(for:))

        guard !diagnostics.isEmpty else {
            return base
        }

        return base + "\n" + diagnostics.joined(separator: "\n")
    }

    private func diagnosticSummary(for status: AgentHookProviderStatus) -> String {
        let configPath = status.configPath.trimmedNonEmpty ?? "unavailable"
        return "\(status.provider.displayName): \(statusLabel(for: status.supportState)) • \(configPath)"
    }

    private func copyDiagnosticsReport() async {
        await MainActor.run {
            isPreparingDiagnostics = true
            diagnosticsStatusMessage = nil
        }

        do {
            let payload = await buildDiagnosticsPayload()
            let data = try encodeDiagnosticsJSON(payload)
            guard let json = String(data: data, encoding: .utf8) else {
                throw NSError(
                    domain: "boringNotch.agents.diagnostics",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to encode diagnostics as UTF-8 text."]
                )
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let copied = pasteboard.setString(json, forType: .string)

            await MainActor.run {
                diagnosticsStatusMessage = copied
                    ? "Diagnostics copied to clipboard."
                    : "Failed to copy diagnostics to clipboard."
                isPreparingDiagnostics = false
            }
        } catch {
            await MainActor.run {
                diagnosticsStatusMessage = "Copy diagnostics failed: \(error.localizedDescription)"
                isPreparingDiagnostics = false
            }
        }
    }

    private func exportDiagnosticsReport() async {
        await MainActor.run {
            isPreparingDiagnostics = true
            diagnosticsStatusMessage = nil
        }

        do {
            let payload = await buildDiagnosticsPayload()
            let data = try encodeDiagnosticsJSON(payload)

            let targetURL = await MainActor.run { () -> URL? in
                let panel = NSSavePanel()
                panel.title = "Export Agent Diagnostics"
                panel.prompt = "Export"
                panel.nameFieldStringValue = defaultDiagnosticsFileName(payload.generatedAt)
                panel.allowedFileTypes = ["json"]
                panel.canCreateDirectories = true
                panel.isExtensionHidden = false
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                return panel.runModal() == .OK ? panel.url : nil
            }

            guard let targetURL else {
                await MainActor.run {
                    diagnosticsStatusMessage = "Diagnostics export canceled."
                    isPreparingDiagnostics = false
                }
                return
            }

            try data.write(to: targetURL, options: .atomic)
            await MainActor.run {
                diagnosticsStatusMessage = "Diagnostics exported to \(targetURL.lastPathComponent)."
                isPreparingDiagnostics = false
            }
        } catch {
            await MainActor.run {
                diagnosticsStatusMessage = "Export diagnostics failed: \(error.localizedDescription)"
                isPreparingDiagnostics = false
            }
        }
    }

    private func buildDiagnosticsPayload() async -> AgentDiagnosticsSnapshot {
        await agentHubManager.refresh(force: false, includeFilesystem: true)
        let statuses = await inspectHookStatusesInBackground()
        await MainActor.run {
            hookStatuses = statuses
        }

        let hookDiagnostics = statuses
            .sorted(by: { $0.provider.displayName.localizedCaseInsensitiveCompare($1.provider.displayName) == .orderedAscending })
            .map { status in
                AgentHookProviderDiagnosticItem(
                    provider: status.provider.rawValue,
                    supportState: status.supportState.rawValue,
                    cliAvailable: status.cliAvailable,
                    hookInstalled: status.hookInstalled,
                    configPath: status.configPath
                )
            }

        return await agentHubManager.diagnosticsSnapshot(hooks: hookDiagnostics)
    }

    private func encodeDiagnosticsJSON(_ payload: AgentDiagnosticsSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private func defaultDiagnosticsFileName(_ date: Date) -> String {
        "boring-notch-agent-diagnostics-\(Self.diagnosticsFileDateFormatter.string(from: date)).json"
    }

    private func shouldShowSelectedPath(provider: AgentProvider, selectedPath: String) -> Bool {
        guard provider == .claude || provider == .codex || provider == .gemini else {
            return true
        }
        let normalizedSelectedPath = URL(fileURLWithPath: selectedPath, isDirectory: true)
            .standardizedFileURL
            .path
        let normalizedHomePath = AgentRuntimePaths.realHomeDirectoryURL.standardizedFileURL.path
        return normalizedSelectedPath != normalizedHomePath
    }

    private static let diagnosticsFileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

}
