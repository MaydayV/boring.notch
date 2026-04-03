//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults
import Darwin

// MARK: - File System Paths
private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

enum AgentHookPaths {
    static let bridgeDirectoryURL = AgentPathResolver.sandboxHomeDirectoryURL
        .appendingPathComponent(".boring-notch/bin", isDirectory: true)
    static let bridgeCommandURL = bridgeDirectoryURL.appendingPathComponent("boring-notch-agent-bridge")
    static let supportDirectoryURL = AgentPathResolver.sandboxHomeDirectoryURL
        .appendingPathComponent("Library/Application Support/boring.notch/Agents", isDirectory: true)
    static let codexConfigURL = AgentPathResolver.realHomeDirectoryURL
        .appendingPathComponent(".codex/hooks.json", isDirectory: false)
    static let claudeSettingsURL = AgentPathResolver.realHomeDirectoryURL
        .appendingPathComponent(".claude/settings.json", isDirectory: false)
    static let geminiSettingsURL = AgentPathResolver.realHomeDirectoryURL
        .appendingPathComponent(".gemini/settings.json", isDirectory: false)
}

enum AgentPathResolver {
    static let sandboxHomeDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    static let realHomeDirectoryURL: URL = {
        guard let passwd = getpwuid(getuid()),
              let homeCString = passwd.pointee.pw_dir else {
            return sandboxHomeDirectoryURL
        }
        return URL(fileURLWithPath: String(cString: homeCString), isDirectory: true)
    }()

    static var sandboxHomePath: String {
        sandboxHomeDirectoryURL.standardizedFileURL.path
    }

    static var realHomePath: String {
        realHomeDirectoryURL.standardizedFileURL.path
    }

    static var requiresRealHomeSecurityScope: Bool {
        sandboxHomePath != realHomePath
    }

    static func providerConfigFileName(for provider: AgentProvider) -> String? {
        switch provider {
        case .claude:
            return "settings.json"
        case .codex:
            return "hooks.json"
        case .gemini:
            return "settings.json"
        case .cursor, .opencode, .droid, .openclaw:
            return nil
        }
    }

    static func providerHiddenDirectoryName(for provider: AgentProvider) -> String? {
        switch provider {
        case .claude:
            return ".claude"
        case .codex:
            return ".codex"
        case .gemini:
            return ".gemini"
        case .cursor:
            return ".cursor"
        case .opencode:
            return ".opencode"
        case .droid:
            return ".droid"
        case .openclaw:
            return ".openclaw"
        }
    }

    static func defaultHookConfigURL(for provider: AgentProvider) -> URL? {
        guard let configFileName = providerConfigFileName(for: provider),
              let hiddenDirectoryName = providerHiddenDirectoryName(for: provider) else {
            return nil
        }

        return realHomeDirectoryURL
            .appendingPathComponent(hiddenDirectoryName, isDirectory: true)
            .appendingPathComponent(configFileName, isDirectory: false)
    }

    static func defaultAuthorizationRootURL(for provider: AgentProvider) -> URL? {
        guard let hiddenDirectoryName = providerHiddenDirectoryName(for: provider) else {
            return nil
        }

        return realHomeDirectoryURL.appendingPathComponent(hiddenDirectoryName, isDirectory: true)
    }

    static func displayScanPaths(for provider: AgentProvider) -> [String] {
        provider.scanRootPaths.map {
            realHomeDirectoryURL
                .appendingPathComponent($0, isDirectory: false)
                .path
        }
    }

    static func resolvedHookConfigURL(for provider: AgentProvider, bookmarkRoot: URL) -> URL? {
        guard let configFileName = providerConfigFileName(for: provider),
              let hiddenDirectoryName = providerHiddenDirectoryName(for: provider) else {
            return nil
        }

        let standardizedRoot = bookmarkRoot.standardizedFileURL
        let components = standardizedRoot.pathComponents
        if let hiddenIndex = components.lastIndex(where: { $0.lowercased() == hiddenDirectoryName }) {
            let hiddenPath = NSString.path(withComponents: Array(components.prefix(hiddenIndex + 1)))
            let hiddenURL = URL(fileURLWithPath: hiddenPath, isDirectory: true)
            return hiddenURL.appendingPathComponent(configFileName, isDirectory: false)
        }

        let directConfigURL = standardizedRoot.appendingPathComponent(configFileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: directConfigURL.path) {
            return directConfigURL
        }

        return standardizedRoot
            .appendingPathComponent(hiddenDirectoryName, isDirectory: true)
            .appendingPathComponent(configFileName, isDirectory: false)
    }
}

extension AgentProvider {
    var hookConfigURL: URL? {
        switch self {
        case .claude:
            return AgentHookPaths.claudeSettingsURL
        case .codex:
            return AgentHookPaths.codexConfigURL
        case .gemini:
            return AgentHookPaths.geminiSettingsURL
        case .cursor, .opencode, .droid, .openclaw:
            return nil
        }
    }
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

enum MusicPlayerVisibilityMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case always = "Always"
    case onlyWhenPlaying = "Only when music is playing"
    case never = "Never"

    var id: String { self.rawValue }
}

// Define notification names at file scope
extension Notification.Name {
    // MARK: - Media
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
    
    // MARK: - Display
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    
    // MARK: - Shelf
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
    
    // MARK: - System
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
    
    // MARK: - Sharing
    static let sharingDidFinish = Notification.Name("com.boringNotch.sharingDidFinish")
    
    // MARK: - UI
    static let accentColorChanged = Notification.Name("AccentColorChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying
    case appleMusic
    case spotify
    case youtubeMusic
    
    var id: String { self.rawValue }

    var localizedString: String {
        switch self {
        case .nowPlaying:
            return NSLocalizedString("Now Playing", comment: "")
        case .appleMusic:
            return "Apple Music"
        case .spotify:
            return "Spotify"
        case .youtubeMusic:
            return "YouTube Music"
        }
    }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard
    case inline
    
    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .standard:
            return NSLocalizedString("sneak_peek_standard", comment: "Sneak Peek style: Default")
        case .inline:
            return NSLocalizedString("sneak_peek_inline", comment: "Sneak Peek style: Inline")
        }
    }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings
    case showOSD
    case none

    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .openSettings:
            return NSLocalizedString("option_key_open_system_settings", comment: "Option (⌥) key behavior: Open System Settings")
        case .showOSD:
            return NSLocalizedString("option_key_show_osd", comment: "Option (⌥) key behavior: Show OSD")
        case .none:
            return NSLocalizedString("option_key_no_action", comment: "Option (⌥) key behavior: No action")
        }
    }
}

enum WeatherTemperatureUnit: String, CaseIterable, Identifiable, Defaults.Serializable {
    case celsius
    case fahrenheit

    var id: String { self.rawValue }

    var symbol: String {
        switch self {
        case .celsius:
            return "C"
        case .fahrenheit:
            return "F"
        }
    }

    var displayName: String {
        switch self {
        case .celsius:
            return "Celsius"
        case .fahrenheit:
            return "Fahrenheit"
        }
    }
}

enum WeatherContentPreference: String, CaseIterable, Identifiable, Defaults.Serializable {
    case currentOnly
    case currentAndForecast

    var id: String { self.rawValue }
}

// Source/provider for OSD control (user-facing: "Source")
enum OSDControlSource: String, CaseIterable, Identifiable, Defaults.Serializable {
    case builtin
    case betterDisplay = "BetterDisplay"
    case lunar = "Lunar"

    var id: String { self.rawValue }
    
    var localizedString: String {
        switch self {
        case .builtin:
            return NSLocalizedString("osd_sources_built_in", comment: "OSD Sources: Built-in")
        case .betterDisplay:
            return "BetterDisplay"
        case .lunar:
            return "Lunar"
        }
    }
}

enum UpdateChannel: String, CaseIterable, Identifiable, Defaults.Serializable {
    case stable
    case beta
    case dev

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            return NSLocalizedString("Stable", comment: "Update channel: stable")
        case .beta:
            return NSLocalizedString("Beta", comment: "Update channel: beta")
        case .dev:
            return NSLocalizedString("Dev (Nightly)", comment: "Update channel: dev nightly")
        }
    }

    var feedURLString: String {
        switch self {
        case .stable:
            return "https://TheBoredTeam.github.io/boring.notch/appcast.xml"
        case .beta:
            return "https://TheBoredTeam.github.io/boring.notch/appcast.xml"
        case .dev:
            return "https://raw.githubusercontent.com/TheBoredTeam/boring.notch/dev/updater/appcast-dev.xml"
        }
    }

    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable:
            return []
        case .beta:
            return ["beta"]
        case .dev:
            return ["dev"]
        }
    }
}

extension Defaults.Keys {
    // MARK: General
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Flying Rabbit 🐇🪽")
    static let updateChannel = Key<UpdateChannel>("updateChannel", default: .stable)
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableOpeningAnimation = Key<Bool>("enableOpeningAnimation", default: true)
    static let animationSpeedMultiplier = Key<Double>("animationSpeedMultiplier", default: 1.0)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    
    // MARK: Appearance
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let isMirrored = Key<Bool>("isMirrored", default: true)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let showWeather = Key<Bool>("showWeather", default: false)
    static let showAgentsTab = Key<Bool>("showAgentsTab", default: true)
    static let enableAgentJumpAction = Key<Bool>("enableAgentJumpAction", default: true)
    static let showClaudeAgentProvider = Key<Bool>("showClaudeAgentProvider", default: true)
    static let showCodexAgentProvider = Key<Bool>("showCodexAgentProvider", default: true)
    static let showGeminiAgentProvider = Key<Bool>("showGeminiAgentProvider", default: true)
    static let showCursorAgentProvider = Key<Bool>("showCursorAgentProvider", default: true)
    static let showOpenCodeAgentProvider = Key<Bool>("showOpenCodeAgentProvider", default: true)
    static let showDroidAgentProvider = Key<Bool>("showDroidAgentProvider", default: true)
    static let showOpenClawAgentProvider = Key<Bool>("showOpenClawAgentProvider", default: true)
    static let agentPanelStyle = Key<AgentPanelStyle>("agentPanelStyle", default: .compact)
    static let claudeAgentRootBookmark = Key<Data?>("claudeAgentRootBookmark", default: nil)
    static let codexAgentRootBookmark = Key<Data?>("codexAgentRootBookmark", default: nil)
    static let geminiAgentRootBookmark = Key<Data?>("geminiAgentRootBookmark", default: nil)
    static let cursorAgentRootBookmark = Key<Data?>("cursorAgentRootBookmark", default: nil)
    static let openCodeAgentRootBookmark = Key<Data?>("openCodeAgentRootBookmark", default: nil)
    static let droidAgentRootBookmark = Key<Data?>("droidAgentRootBookmark", default: nil)
    static let openClawAgentRootBookmark = Key<Data?>("openClawAgentRootBookmark", default: nil)
    static let weatherCity = Key<String>("weatherCity", default: "Cupertino")
    static let weatherUnit = Key<WeatherTemperatureUnit>("weatherUnit", default: .celsius)
    static let weatherRefreshMinutes = Key<Int>("weatherRefreshMinutes", default: 30)
    static let weatherContentPreference = Key<WeatherContentPreference>("weatherContentPreference", default: .currentAndForecast)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    
    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let musicPlayerVisibilityMode = Key<MusicPlayerVisibilityMode>(
        "musicPlayerVisibilityMode",
        default: .always
    )
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    
    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
    // MARK: OSD
    static let osdReplacement = Key<Bool>("osdReplacement", default: false)
    static let inlineOSD = Key<Bool>("inlineOSD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchOSD = Key<Bool>("showOpenNotchOSD", default: true)
    static let showOpenNotchOSDPercentage = Key<Bool>("showOpenNotchOSDPercentage", default: true)
    static let showClosedNotchOSDPercentage = Key<Bool>("showClosedNotchOSDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    // Brightness/volume/keyboard source selection
    static let osdBrightnessSource = Key<OSDControlSource>("osdBrightnessSource", default: .builtin)
    static let osdVolumeSource = Key<OSDControlSource>("osdVolumeSource", default: .builtin)
    
    // MARK: Shelf
    static let boringShelf = Key<Bool>("boringShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    
    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    static let hideNonNotchedFromMissionControl = Key<Bool>("hideNonNotchedFromMissionControl", default: true)
    // Normalize scroll/gesture direction so when macOS "Natural scrolling" is disabled, it doesn't invert gestures
    static let normalizeGestureDirection = Key<Bool>("normalizeGestureDirection", default: true)
    
    // Helper to determine the default media controller based on NowPlaying deprecation status
    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}
