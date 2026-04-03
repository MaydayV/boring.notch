//
//  ShortcutsSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import KeyboardShortcuts
import Foundation
import SwiftUI

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder(
                    String(localized: "settings.shortcuts.recorder.toggle_sneak_peek"),
                    name: .toggleSneakPeek
                )
            } header: {
                Text("settings.shortcuts.section.media")
            } footer: {
                Text(
                    "settings.shortcuts.footer.sneak_peek"
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder(
                    String(localized: "settings.shortcuts.recorder.toggle_notch_open"),
                    name: .toggleNotchOpen
                )
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("settings.sidebar.shortcuts")
    }
}
