//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    NavigationLink(value: tab) {
                        Label {
                            Text(tab.titleKey)
                        } icon: {
                            Image(systemName: tab.systemImage)
                        }
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            settingsDetail(for: selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    @ViewBuilder
    private func settingsDetail(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettings()
        case .appearance:
            Appearance()
        case .media:
            Media()
        case .calendar:
            CalendarSettings()
        case .weather:
            WeatherSettings()
        case .osd:
            OSDSettings()
        case .battery:
            Charge()
        case .shelf:
            Shelf()
        case .agents:
            AgentsSettingsView()
        case .shortcuts:
            Shortcuts()
        case .advanced:
            Advanced()
        case .about:
            if let controller = updaterController {
                About(updaterController: controller)
            } else {
                // Fallback with a default controller
                About(
                    updaterController: SPUStandardUpdaterController(
                        startingUpdater: false, updaterDelegate: nil,
                        userDriverDelegate: nil))
            }
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case media
    case calendar
    case weather
    case osd
    case battery
    case shelf
    case agents
    case shortcuts
    case advanced
    case about

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .general:
            "settings.sidebar.general"
        case .appearance:
            "settings.sidebar.appearance"
        case .media:
            "settings.sidebar.media"
        case .calendar:
            "settings.sidebar.calendar"
        case .weather:
            "settings.sidebar.weather"
        case .osd:
            "settings.sidebar.osd"
        case .battery:
            "settings.sidebar.battery"
        case .shelf:
            "settings.sidebar.shelf"
        case .agents:
            "settings.sidebar.agents"
        case .shortcuts:
            "settings.sidebar.shortcuts"
        case .advanced:
            "settings.sidebar.advanced"
        case .about:
            "settings.sidebar.about"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gear"
        case .appearance:
            "eye"
        case .media:
            "play.laptopcomputer"
        case .calendar:
            "calendar"
        case .weather:
            "cloud.sun"
        case .osd:
            "dial.medium.fill"
        case .battery:
            "battery.100.bolt"
        case .shelf:
            "books.vertical"
        case .agents:
            "terminal"
        case .shortcuts:
            "keyboard"
        case .advanced:
            "gearshape.2"
        case .about:
            "info.circle"
        }
    }
}
