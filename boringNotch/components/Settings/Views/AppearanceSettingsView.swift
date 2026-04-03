//
//  AppearanceSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import SwiftUI

struct Appearance: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor

    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"
    var body: some View {
        Form {
            Section {
                Toggle("settings.appearance.toggle.always_show_tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("settings.appearance.toggle.show_settings_icon_in_notch")
                }

            } header: {
                Text("settings.appearance.section.general")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("settings.appearance.toggle.colored_spectrogram")
                }
                Defaults.Toggle(key: .playerColorTinting) {
                    Text("settings.appearance.toggle.player_tinting")
                }
                Defaults.Toggle(key: .lightingEffect) {
                    Text("settings.appearance.toggle.enable_blur_effect_behind_album_art")
                }
                Picker("settings.appearance.picker.slider_color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.localizedString)
                    }
                }
            } header: {
                Text("settings.appearance.section.media")
            }



            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("settings.appearance.toggle.enable_boring_mirror")
                }
                    .disabled(!checkVideoInput())
                Picker("settings.appearance.picker.mirror_shape", selection: $mirrorShape) {
                    Text("settings.appearance.option.circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("settings.appearance.option.square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("settings.appearance.toggle.show_cool_face_animation_while_inactive")
                }
            } header: {
                HStack {
                    Text("settings.appearance.section.additional_features")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("settings.sidebar.appearance")
    }

    func checkVideoInput() -> Bool {
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }

        return false
    }
}
