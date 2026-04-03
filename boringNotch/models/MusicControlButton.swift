//
//  MusicControlButton.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-16.
//

import Defaults
import SwiftUI

enum MusicControlButton: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
    case volume
    case favorite
    case goBackward
    case goForward
    case none

    var id: String { rawValue }

    static let defaultLayout: [MusicControlButton] = [
        .none,
        .previous,
        .playPause,
        .next,
        .none
    ]

    static let minSlotCount: Int = 3
    static let maxSlotCount: Int = 5

    static let pickerOptions: [MusicControlButton] = [
        .shuffle,
        .previous,
        .playPause,
        .next,
        .repeatMode,
        .favorite,
        .volume,
        .goBackward,
        .goForward
    ]

    var label: LocalizedStringKey {
        switch self {
        case .shuffle:
            return "settings.music_controls.option.shuffle"
        case .previous:
            return "settings.music_controls.option.previous"
        case .playPause:
            return "settings.music_controls.option.play_pause"
        case .next:
            return "settings.music_controls.option.next"
        case .repeatMode:
            return "settings.music_controls.option.repeat"
        case .volume:
            return "settings.music_controls.option.volume"
        case .favorite:
            return "settings.music_controls.option.favorite"
        case .goBackward:
            return "settings.music_controls.option.backward_15s"
        case .goForward:
            return "settings.music_controls.option.forward_15s"
        case .none:
            return "settings.music_controls.option.empty_slot"
        }
    }

    var iconName: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .previous:
            return "backward.fill"
        case .playPause:
            return "playpause"
        case .next:
            return "forward.fill"
        case .repeatMode:
            return "repeat"
        case .volume:
            return "speaker.wave.2.fill"
        case .favorite:
            return "heart"
        case .goBackward:
            return "gobackward.15"
        case .goForward:
            return "goforward.15"
        case .none:
            return ""
        }
    }

    var prefersLargeScale: Bool {
        self == .playPause
    }
}
