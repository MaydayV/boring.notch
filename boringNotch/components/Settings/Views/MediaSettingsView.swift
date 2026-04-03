//
//  MediaSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import Foundation
import SwiftUI

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics

    var body: some View {
        Form {
            Section {
                Picker("settings.media.picker.music_source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(mediaControllerLabel(for: controller)).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("settings.media.section.media_source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("settings.media.footer.youtube_music_requires_app")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)  // Ensures it's visibly a link
                    }
                } else {
                    Text("settings.media.footer.now_playing_legacy")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            
            Section {
                Toggle(
                    "settings.media.toggle.show_music_live_activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("settings.media.toggle.show_sneak_peek_on_playback_changes", isOn: $enableSneakPeek)
                Picker("settings.media.picker.sneak_peek_style", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.localizedString).tag(style)
                    }
                }
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("settings.media.label.media_inactivity_timeout")
                            Spacer()
                            Text(String(format: String(localized: "settings.media.value.media_inactivity_timeout_format"), locale: .current, arguments: [Int(waitInterval)]))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker(
                    selection: $hideNotchOption,
                    label:
                        HStack {
                            Text("settings.media.label.full_screen_behavior")
                            customBadge(text: "settings.common.beta")
                        }
                ) {
                    Text("settings.media.option.hide_for_all_apps").tag(HideNotchOption.always)
                    Text("settings.media.option.hide_for_media_app_only").tag(
                        HideNotchOption.nowPlayingOnly)
                    Text("settings.media.option.never_hide").tag(HideNotchOption.never)
                }
            } header: {
                Text("settings.media.section.media_playback_live_activity")
            }
            
            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text("settings.media.toggle.show_lyrics_below_artist_name")
                        customBadge(text: "settings.common.beta")
                    }
                }
            } header: {
                Text("settings.media.section.media_controls")
            }  footer: {
                Text("settings.media.footer.customize_controls")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("settings.sidebar.media")
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }

    private func mediaControllerLabel(for controller: MediaControllerType) -> LocalizedStringKey {
        switch controller {
        case .nowPlaying:
            return "settings.media.option.now_playing"
        case .appleMusic:
            return "settings.media.option.apple_music"
        case .spotify:
            return "settings.media.option.spotify"
        case .youtubeMusic:
            return "settings.media.option.youtube_music"
        }
    }
}
