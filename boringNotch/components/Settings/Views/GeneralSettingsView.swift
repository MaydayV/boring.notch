//
//  GeneralSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import Foundation
import LaunchAtLogin
import SwiftUI

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Default(.mirrorShape) var mirrorShape
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.enableOpeningAnimation) var enableOpeningAnimation
    @Default(.animationSpeedMultiplier) var animationSpeedMultiplier

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("settings.general.toggle.show_menu_bar_icon")
                }
                .tint(.effectiveAccent)
                LaunchAtLogin.Toggle() {
                    Text("settings.general.toggle.launch_at_login")
                }
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("settings.general.toggle.show_on_all_displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("settings.general.picker.preferred_display", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap { screen in
                        guard let uuid = screen.displayUUID else { return nil }
                        return (uuid, screen.localizedName)
                    }
                }
                .disabled(showOnAllDisplays)
                
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("settings.general.toggle.automatically_switch_displays")
                }
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(
                            name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                    }
                    .disabled(showOnAllDisplays)
            } header: {
                Text("settings.general.section.system_features")
            }

            Section {
                Picker(
                    selection: $notchHeightMode,
                    label:
                        Text("settings.general.label.notch_height_on_notch_displays")
                ) {
                    Text("settings.general.option.match_real_notch_height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("settings.general.option.match_menu_bar_height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("settings.general.option.custom_height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize:
                        // Get the actual notch height from the built-in display
                        notchHeight = getRealNotchHeight()
                    case .matchMenuBar:
                        notchHeight = 43
                    case .custom:
                        notchHeight = 38
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text(
                            String(format: String(localized: "settings.general.label.custom_notch_size_format"), locale: .current, arguments: [Int(notchHeight)])
                        )
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("settings.general.label.notch_height_on_non_notch_displays", selection: $nonNotchHeightMode) {
                    Text("settings.general.option.match_menubar_height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("settings.general.option.custom_height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 23
                    case .matchRealNotchSize, .custom:
                        nonNotchHeight = 23
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    // Custom binding to skip values 1-14 (jump from 0 to 10)
                    let sliderValue = Binding<Double>(
                        get: { 
                            nonNotchHeight == 0 ? 0 : nonNotchHeight - 14
                        },
                        set: { newValue in
                            let oldValue = nonNotchHeight
                            nonNotchHeight = newValue == 0 ? 0 : newValue + 14
                            if oldValue != nonNotchHeight {
                                NotificationCenter.default.post(
                                    name: Notification.Name.notchHeightChanged, object: nil)
                            }
                        }
                    )
                    
                    Slider(value: sliderValue, in: 0...26, step: 1) {
                        Text(
                            String(format: String(localized: "settings.general.label.custom_notch_size_format"), locale: .current, arguments: [Int(nonNotchHeight)])
                        )
                    }
                }
            } header: {
                Text("settings.general.section.notch_sizing")
            }

            NotchBehaviour()

            gestureControls()
        }
        .toolbar {
            Button("settings.general.button.quit_app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("settings.sidebar.general")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("settings.general.toggle.enable_gestures")
            }
                .disabled(!openNotchOnHover)
            if enableGestures {
                Toggle("settings.general.toggle.change_media_with_horizontal_gestures", isOn: .constant(false))
                    .disabled(true)
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("settings.general.toggle.close_gesture")
                }
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("settings.general.label.gesture_sensitivity")
                        Spacer()
                        Text(
                            Defaults[.gestureSensitivity] == 100
                                ? "settings.general.value.high" : Defaults[.gestureSensitivity] == 200 ? "settings.general.value.medium" : "settings.general.value.low"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("settings.general.section.gesture_control")
                customBadge(text: "settings.common.beta")
            }
        } footer: {
            Text(
                "settings.general.footer.gesture_controls"
            )
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("settings.general.toggle.open_notch_on_hover")
            }
            Defaults.Toggle(key: .enableHaptics) {
                    Text("settings.general.toggle.enable_haptic_feedback")
            }
            Toggle("settings.general.toggle.remember_last_tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("settings.general.label.hover_delay")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            Toggle("settings.general.toggle.notch_animation", isOn: $enableOpeningAnimation)
            if enableOpeningAnimation {
                Slider(value: $animationSpeedMultiplier, in: 0.1...2.01, step: 0.1) {
                    HStack {
                        Text("settings.general.label.animation_speed")
                        Spacer()
                        Text("\(animationSpeedMultiplier, specifier: "%.1f")x")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("settings.general.section.notch_behavior")
        }
    }
}
