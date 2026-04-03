//
//  OSDSettingsView.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-07.
//

import SwiftUI
import Defaults
import CoreGraphics

struct OSDSettings: View {
    // Defaults-backed storage
    @Default(.osdReplacement) private var osdReplacementDefault
    @Default(.showOpenNotchOSD) private var showOpenNotchOSDDefault
    @Default(.optionKeyAction) private var optionKeyActionDefault
    @Default(.osdBrightnessSource) private var osdBrightnessSourceDefault
    @Default(.osdVolumeSource) private var osdVolumeSourceDefault
    @State private var isAccessibilityAuthorized = true
    @State private var menuBarBrightnessSupported = true

    var body: some View {
        Form {
            Section(header: Text("settings.osd.section.general")) {
                Defaults.Toggle(key: .osdReplacement) {
                    Text("settings.osd.toggle.replace_system_osd")
                }
                if osdReplacementDefault {
                    Defaults.Toggle(key: .inlineOSD) {
                        Text("settings.osd.toggle.use_inline_style")
                    }
                }
            }

            if osdReplacementDefault {
                Section(header: Text("settings.osd.section.control_sources"), footer: Text("settings.osd.footer.control_sources")) {
                    HStack {
                        Text("settings.osd.label.brightness_source")
                        Spacer()
                        Picker("", selection: $osdBrightnessSourceDefault) {
                            ForEach(OSDControlSource.allCases) { source in
                                Text(osdSourceLabel(for: source)).tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if osdBrightnessSourceDefault == .builtin {
                        HelpText("settings.osd.help.only_apple_displays")
                    }
                    if osdBrightnessSourceDefault == .betterDisplay && !BetterDisplayManager.shared.isBetterDisplayAvailable {
                        HelpText("settings.osd.help.betterdisplay_unavailable")
                    }
                    if osdBrightnessSourceDefault == .lunar && !LunarManager.shared.isLunarAvailable {
                        HelpText("settings.osd.help.lunar_unavailable")
                    }

                    HStack {
                        Text("settings.osd.label.volume_source")
                        Spacer()
                        Picker("", selection: $osdVolumeSourceDefault) {
                            // Lunar does not support volume control so hide it from the picker
                            ForEach(OSDControlSource.allCases.filter { $0 != .lunar }) { source in
                                Text(osdSourceLabel(for: source)).tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if osdVolumeSourceDefault == .betterDisplay && !BetterDisplayManager.shared.isBetterDisplayAvailable {
                        HelpText("settings.osd.help.betterdisplay_unavailable")
                    }

                    HStack {
                        Text("settings.osd.label.keyboard_source")
                        Spacer()
                        Text("settings.osd.source.builtin")
                    }
                    HelpText("settings.osd.help.keyboard_brightness_builtin_only")
                    if !isAccessibilityAuthorized {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "accessibility")
                                .font(.title)
                                .foregroundStyle(Color.effectiveAccent)
                                
                            VStack(alignment: .leading, spacing: 2) {
                                Text("settings.osd.label.accessibility_access_required")
                                    .font(.headline)
                                Text("settings.osd.help.grant_accessibility")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("settings.osd.button.grant_access") {
                                Task {
                                    let granted = await MediaKeyInterceptor.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                                    await MainActor.run {
                                        isAccessibilityAuthorized = granted
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("settings.osd.section.appearance")) {
                    Defaults.Toggle(key: .enableGradient) {
                        Text("settings.osd.toggle.enable_gradient")
                    }
                    Defaults.Toggle(key: .systemEventIndicatorShadow) {
                        Text("settings.osd.toggle.show_shadow")
                    }
                    Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                        Text("settings.osd.toggle.use_accent_color")
                    }
                }

                Section(header: Text("settings.osd.section.visibility")) {
                    Defaults.Toggle(key: .showOpenNotchOSD) {
                        Text("settings.osd.toggle.show_osd_in_open_notch")
                    }
                    if showOpenNotchOSDDefault {
                        Defaults.Toggle(key: .showOpenNotchOSDPercentage) {
                            Text("settings.osd.toggle.show_percentage_open_notch")
                        }
                    }
                    Defaults.Toggle(key: .showClosedNotchOSDPercentage) {
                        Text("settings.osd.toggle.show_percentage_closed_notch")
                    }
                }

                Section(header: Text("settings.osd.section.interaction")) {
                    HStack {
                        Text("settings.osd.label.option_key_behavior")
                        Spacer()
                        Picker("", selection: $optionKeyActionDefault) {
                            ForEach(OptionKeyAction.allCases) { action in
                                Text(action.localizedString).tag(action)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    HelpText("settings.osd.help.define_option_key_behavior")
                }
            }

        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .task(id: osdReplacementDefault) {
            guard osdReplacementDefault else { return }
            isAccessibilityAuthorized = await MediaKeyInterceptor.shared.ensureAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notif in
            if let granted = notif.userInfo?["granted"] as? Bool {
                isAccessibilityAuthorized = granted
            }
        }
        .task(id: osdBrightnessSourceDefault) {
            if osdBrightnessSourceDefault == .builtin {
                if let displayID = await XPCHelperClient.shared.displayIDForBrightness() {
                    let menuID = NSScreen.main?.cgDisplayID ?? CGMainDisplayID()
                    menuBarBrightnessSupported = (displayID == menuID)
                } else {
                    menuBarBrightnessSupported = false
                }
            } else {
                menuBarBrightnessSupported = true
            }
        }

    }

    private func osdSourceLabel(for source: OSDControlSource) -> LocalizedStringKey {
        switch source {
        case .builtin:
            return "settings.osd.source.builtin"
        case .betterDisplay:
            return "settings.osd.source.betterdisplay"
        case .lunar:
            return "settings.osd.source.lunar"
        }
    }
}

#Preview {
    OSDSettings()
        .frame(width: 500, height: 600)
}
