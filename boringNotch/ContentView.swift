//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var agentHubManager = AgentHubManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.showNotHumanFace) var showNotHumanFace

    // Use standardized animations from StandardAnimations enum
    private let animationSpring = StandardAnimations.interactive

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    // MARK: - Corner Radius Scaling
    private var cornerRadiusScaleFactor: CGFloat? {
        guard Defaults[.cornerRadiusScaling] else { return nil }
        let effectiveHeight = displayClosedNotchHeight
        guard effectiveHeight > 0 else { return nil }
        return effectiveHeight / 38.0
    }
    
    private var topCornerRadius: CGFloat {
        // If the notch is open, return the opened radius.
        if vm.notchState == .open {
            return cornerRadiusInsets.opened.top
        }

        // For the closed notch, scale if enabled
        let baseClosedTop = cornerRadiusInsets.closed.top
        guard let scaleFactor = cornerRadiusScaleFactor else {
            return displayClosedNotchHeight > 0 ? baseClosedTop : 0
        }
        return max(0, baseClosedTop * scaleFactor)
    }

    private var currentNotchShape: NotchShape {
        // Scale bottom corner radius for closed notch shape when scaling is enabled.
        let baseClosedBottom = cornerRadiusInsets.closed.bottom
        let bottomCorner: CGFloat

        if vm.notchState == .open {
            bottomCorner = cornerRadiusInsets.opened.bottom
        } else if let scaleFactor = cornerRadiusScaleFactor {
            bottomCorner = max(0, baseClosedBottom * scaleFactor)
        } else {
            bottomCorner = displayClosedNotchHeight > 0 ? baseClosedBottom : 0
        }

        return NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCorner
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, displayClosedNotchHeight - 12) + 20)
        } else if !coordinator.expandingView.show
            && vm.notchState == .closed
            && compactAgentSnapshot != nil
            && !vm.hideOnClosed
        {
            chinWidth += 180
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, displayClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    // If the closed notch height is 0 (any display/setting), display a 10pt nearly-invisible notch
    // instead of fully hiding it. This preserves layout while avoiding visual artifacts.
    private var isNotchHeightZero: Bool { vm.effectiveClosedNotchHeight == 0 }

    private var displayClosedNotchHeight: CGFloat { isNotchHeightZero ? 10 : vm.effectiveClosedNotchHeight }

    private struct CompactAgentScopeSnapshot {
        let provider: AgentProvider
        let sourceAlias: String?
        let scopeLabel: String
        let activeCount: Int
        let pendingCount: Int
    }

    private var compactAgentSnapshot: CompactAgentScopeSnapshot? {
        let activeSessions = agentHubManager.sessions.filter { isAgentStateActive($0.state) }
        let pendingActions = agentHubManager.pendingActions

        guard !activeSessions.isEmpty || !pendingActions.isEmpty else {
            return nil
        }

        let preferredPendingAction = pendingActions
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first
        let preferredActiveSession = activeSessions
                .sorted(by: { $0.lastActiveAt > $1.lastActiveAt })
                .first

        let preferredProvider = preferredPendingAction?.provider
            ?? preferredActiveSession?.provider
            ?? .codex
        let preferredSourceAlias = preferredPendingAction?.sourceAlias?.trimmedNonEmpty
            ?? preferredActiveSession?.sourceAlias?.trimmedNonEmpty

        let providerActiveCount = activeSessions.filter { session in
            matchesCompactScope(
                provider: session.provider,
                sourceAlias: session.sourceAlias,
                scopeProvider: preferredProvider,
                scopeSourceAlias: preferredSourceAlias
            )
        }.count
        let providerPendingCount = pendingActions.filter { action in
            matchesCompactScope(
                provider: action.provider,
                sourceAlias: action.sourceAlias,
                scopeProvider: preferredProvider,
                scopeSourceAlias: preferredSourceAlias
            )
        }.count

        return CompactAgentScopeSnapshot(
            provider: preferredProvider,
            sourceAlias: preferredSourceAlias,
            scopeLabel: preferredSourceAlias ?? preferredProvider.displayName,
            activeCount: providerActiveCount,
            pendingCount: providerPendingCount
        )
    }

    private func normalizedSourceAlias(_ sourceAlias: String?) -> String? {
        sourceAlias?.trimmedNonEmpty?.lowercased()
    }

    private func matchesCompactScope(
        provider: AgentProvider,
        sourceAlias: String?,
        scopeProvider: AgentProvider,
        scopeSourceAlias: String?
    ) -> Bool {
        guard provider == scopeProvider else { return false }
        guard let scopeSourceAlias else { return true }
        return normalizedSourceAlias(sourceAlias) == normalizedSourceAlias(scopeSourceAlias)
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                          .overlay(alignment: .top) {
                              displayClosedNotchHeight.isZero && vm.notchState == .closed ? nil
                        : Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: 6
                    )
                    // Removed conditional bottom padding when using custom 0 notch to keep layout stable
                    .opacity((isNotchHeightZero && vm.notchState == .closed) ? 0.01 : 1)
                
                mainLayout
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                    .conditionalModifier(true) { view in
                        return view
                            .animation(vm.notchState == .open ? StandardAnimations.open : StandardAnimations.close, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .conditionalModifier(vm.notchState != .open) { view in
                        view.onTapGesture {
                            doOpen()
                        }
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("settings.common.settings") {
                            SettingsWindowController.shared.showWindow()
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .ignoresSafeArea(.all)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                BoringBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: displayClosedNotchHeight, alignment: .center)
                      } else if coordinator.shouldShowSneakPeek(on: vm.screenUUID) && Defaults[.inlineOSD] && (coordinator.sneakPeekState(for: vm.screenUUID).type != .music) && (coordinator.sneakPeekState(for: vm.screenUUID).type != .battery) && vm.notchState == .closed {
                          InlineOSD(
                              type: coordinator.binding(for: vm.screenUUID).type,
                              value: coordinator.binding(for: vm.screenUUID).value,
                              icon: coordinator.binding(for: vm.screenUUID).icon,
                              accent: coordinator.binding(for: vm.screenUUID).accent,
                              hoverAnimation: $isHovering,
                              gestureProgress: $gestureProgress
                          )
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && !vm.hideOnClosed, let compactAgentSnapshot {
                          CompactAgentIslandView(
                            provider: compactAgentSnapshot.provider,
                            scopeLabel: compactAgentSnapshot.scopeLabel,
                            activeSessionCount: compactAgentSnapshot.activeCount,
                            pendingActionCount: compactAgentSnapshot.pendingCount
                          )
                          .transition(
                              .modifier(
                                  active: CompactAgentIslandTransitionModifier(progress: 0),
                                  identity: CompactAgentIslandTransitionModifier(progress: 1)
                              )
                          )
                          .frame(height: displayClosedNotchHeight, alignment: Alignment.center)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, displayClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       }
                        // New case to enable compact notch on external displays
                        else if !vm.hasNotch {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: 11) // idle notch height is halved on non notch display
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: displayClosedNotchHeight)
                       }

                      if coordinator.shouldShowSneakPeek(on: vm.screenUUID) {
                          if (coordinator.sneakPeekState(for: vm.screenUUID).type != .music) && (coordinator.sneakPeekState(for: vm.screenUUID).type != .battery) && !Defaults[.inlineOSD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: coordinator.binding(for: vm.screenUUID).type,
                                  value: coordinator.binding(for: vm.screenUUID).value,
                                  icon: coordinator.binding(for: vm.screenUUID).icon,
                                  accent: coordinator.binding(for: vm.screenUUID).accent,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeekState(for: vm.screenUUID).type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeekState(for: vm.screenUUID).type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(musicManager.songTitle + " - " + musicManager.artistName,  color: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, delayDuration: 1.0, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.shouldShowSneakPeek(on: vm.screenUUID) && (coordinator.sneakPeekState(for: vm.screenUUID).type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.shouldShowSneakPeek(on: vm.screenUUID) && (coordinator.sneakPeekState(for: vm.screenUUID).type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(1)
            if vm.notchState == .open {
                VStack(alignment: .leading, spacing: 0) {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .shelf:
                        ShelfView()
                    case .weather:
                        WeatherTabView()
                    case .agents:
                        AgentsTabView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(
                    .modifier(
                        active: OpenAgentPanelTransitionModifier(progress: 0),
                        identity: OpenAgentPanelTransitionModifier(progress: 1)
                    )
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 20)
            let faceScale = min(1.0, displayClosedNotchHeight / 30.0)
            MinimalFaceFeatures(height: 24.0 * faceScale, width: 30.0 * faceScale)
        }.frame(
            height: displayClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack(spacing: 0) {
            // Closed-mode album art: scale padding and corner radius according to cornerRadiusScaleFactor
            let baseArtSize = displayClosedNotchHeight - 12
            let scaledArtSize: CGFloat = {
                if let scale = cornerRadiusScaleFactor {
                    return displayClosedNotchHeight - 12 * scale
                }
                return baseArtSize
            }()

            let closedCornerRadius: CGFloat = {
                let base = MusicPlayerImageSizes.cornerRadiusInset.closed
                if let scale = cornerRadiusScaleFactor {
                    return max(0, base * scale)
                }
                return base
            }()

            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: closedCornerRadius)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: scaledArtSize,
                    height: scaledArtSize
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                musicManager.songTitle,
                                color: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                delayDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                AudioSpectrumView(
                    isPlaying: musicManager.isPlaying,
                    tintColor: Defaults[.coloredSpectrogram]
                    ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.5)
                    : Color.gray
                )
                .frame(width: 16, height: 12)
            }
            .frame(
                width: max(
                    0,
                    displayClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    displayClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: displayClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    private func isAgentStateActive(_ state: AgentSessionState) -> Bool {
        switch state {
        case .running, .waitingApproval, .waitingQuestion:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    private struct CompactAgentIslandView: View {
        let provider: AgentProvider
        let scopeLabel: String
        let activeSessionCount: Int
        let pendingActionCount: Int

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var pendingBurstStartedAt = Date.distantPast
        @State private var lastObservedPendingCount = Int.min
        @State private var measuredIslandWidth: CGFloat = 0

        private enum ActivityMode {
            case waiting
            case running
            case settled
        }

        var body: some View {
            TimelineView(.animation(minimumInterval: animationInterval)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                let burst = burstEnvelope(now: context.date)
                let jitter = pendingJitterOffset(phase: phase, burst: burst)
                let islandWidth = max(measuredIslandWidth, fallbackIslandWidth)

                VStack(alignment: .leading, spacing: 4) {
                    if pendingActionCount > 0 {
                        pendingWarningRibbon(phase: phase, burst: burst, width: islandWidth)
                            .frame(width: islandWidth, height: 4, alignment: .leading)
                            .transition(.opacity)
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: providerSymbolName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(stateAccent.opacity(0.92))
                            Text(scopeLabel.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.96))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.08),
                                            stateAccent.opacity(activityMode == .waiting ? 0.13 : 0.08)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .clipShape(Capsule())

                        pixelActivityMeter(phase: phase, burst: burst)
                            .frame(height: 14)

                        if pendingActionCount > 0 {
                            Text("\(pendingActionCount)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .scaleEffect(1.0 + (burst * 0.07))
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(pendingBadgeColor(phase: phase, burst: burst))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.black.opacity(0.22), lineWidth: 1)
                                )
                        }

                        if activeSessionCount > 1 {
                            Text("\(activeSessionCount)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.028),
                                        Color.white.opacity(0.016)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: stateAccent.opacity(0.08 + burst * 0.08), radius: 5 + burst * 2, x: 0, y: 1)
                    .offset(x: jitter.width, y: jitter.height)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: CompactAgentIslandWidthPreferenceKey.self,
                                value: proxy.size.width
                            )
                        }
                    }
                }
            }
            .compositingGroup()
            .onAppear {
                lastObservedPendingCount = pendingActionCount
                pendingBurstStartedAt = Date()
            }
            .onChange(of: pendingActionCount) { newValue in
                guard newValue != lastObservedPendingCount else { return }
                lastObservedPendingCount = newValue
                pendingBurstStartedAt = Date()
            }
            .onPreferenceChange(CompactAgentIslandWidthPreferenceKey.self) { newWidth in
                let roundedWidth = max(0, newWidth.rounded(.up))
                guard abs(roundedWidth - measuredIslandWidth) > 0.5 else { return }
                measuredIslandWidth = roundedWidth
            }
        }

        private var fallbackIslandWidth: CGFloat {
            let normalizedLength = CGFloat(scopeLabel.trimmingCharacters(in: .whitespacesAndNewlines).count)
            let textContribution = min(26, normalizedLength) * 5.2
            let pendingContribution: CGFloat = pendingActionCount > 0 ? 24 : 0
            let activeContribution: CGFloat = activeSessionCount > 1 ? 16 : 0
            let estimate = 124 + textContribution + pendingContribution + activeContribution
            return min(320, max(164, estimate))
        }

        private var animationInterval: TimeInterval {
            if reduceMotion {
                return 0.22
            }

            switch activityMode {
            case .waiting:
                return pendingActionCount > 0 ? 0.065 : 0.08
            case .running:
                return 0.085
            case .settled:
                return 0.1
            }
        }

        @ViewBuilder
        private func pixelActivityMeter(phase: TimeInterval, burst: Double) -> some View {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(stateAccent.opacity(burst * 0.08))
                        .blur(radius: reduceMotion ? 1.4 : 2.2)
                        .frame(width: width, height: height)

                    HStack(spacing: 2) {
                        ForEach(0..<12, id: \.self) { column in
                            VStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { row in
                                    RoundedRectangle(cornerRadius: 0.7, style: .continuous)
                                        .fill(pixelColor(column: column, row: row, phase: phase, burst: burst))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 0.7, style: .continuous)
                                                .stroke(Color.white.opacity(pixelEdgeOpacity(column: column, row: row, phase: phase, burst: burst)), lineWidth: 0.35)
                                        )
                                        .frame(width: 3, height: 3)
                                        .scaleEffect(pixelScale(column: column, row: row, phase: phase, burst: burst))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 1)

                    scanSweep(width: width, phase: phase, burst: burst)
                    statePulseLayer(width: width, phase: phase, burst: burst)
                    pendingBurstLayer(width: width, height: height, burst: burst)
                }
            }
            .frame(width: 52, height: 14, alignment: .leading)
        }

        private var providerSymbolName: String {
            switch provider {
            case .claude:
                return "brain.head.profile"
            case .codex:
                return "terminal"
            case .gemini:
                return "sparkles"
            case .cursor:
                return "cursorarrow"
            case .opencode:
                return "chevron.left.forwardslash.chevron.right"
            case .droid:
                return "dot.radiowaves.left.and.right"
            case .openclaw:
                return "pawprint"
            }
        }

        private func pixelColor(column: Int, row: Int, phase: TimeInterval, burst: Double) -> Color {
            let baseOpacity = baselineOpacity(column: column, row: row)
            let sweepBoost = scanBoost(column: column, row: row, phase: phase, burst: burst)
            let pulseBoost = statePulse(phase: phase) * (reduceMotion ? 0.11 : 0.17)
            let burstBoost = burst * (pendingActionCount > 0 ? 0.24 : 0.14)
            let opacity = min(0.94, baseOpacity + sweepBoost + pulseBoost + burstBoost)
            return stateAccent.opacity(opacity)
        }

        private func pixelEdgeOpacity(column: Int, row: Int, phase: TimeInterval, burst: Double) -> Double {
            let lift = scanBoost(column: column, row: row, phase: phase, burst: burst)
            return min(0.28, 0.06 + lift * 0.18 + burst * 0.12)
        }

        private func pixelScale(column: Int, row: Int, phase: TimeInterval, burst: Double) -> CGFloat {
            let lift = scanBoost(column: column, row: row, phase: phase, burst: burst)
            let pulse = statePulse(phase: phase)
            let base: CGFloat = reduceMotion ? 1.0 : 0.92
            let scale = base + CGFloat(lift * 0.12 + pulse * 0.05 + burst * 0.06)
            return min(1.14, scale)
        }

        private func baselineOpacity(column: Int, row: Int) -> Double {
            let providerSeed = provider.rawValue.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            let seed = providerSeed + (activeSessionCount * 17) + (pendingActionCount * 31) + (column * 23) + (row * 19)
            let mixed = seed &* 1103515245 &+ 12345
            let value = abs(mixed) % 100
            return 0.08 + Double(value) / 100.0 * 0.09
        }

        private func scanBoost(column: Int, row: Int, phase: TimeInterval, burst: Double) -> Double {
            let center = scanCenter(phase: phase, burst: burst)
            let normalizedColumn = (Double(column) + 0.5) / 12.0
            let distance = abs(center - normalizedColumn)
            let width = reduceMotion ? 2.55 : (pendingActionCount > 0 ? 2.25 : 2.0)
            let sweep = max(0, 1 - distance * width)
            let rowBias = row == 1 ? 0.08 : (row == 0 ? 0.03 : 0.05)
            return sweep * (pendingActionCount > 0 ? 0.28 : 0.21) + rowBias * burst
        }

        private func scanCenter(phase: TimeInterval, burst: Double) -> Double {
            let tempo: Double
            switch activityMode {
            case .waiting:
                tempo = pendingActionCount > 0 ? 1.6 : 1.15
            case .running:
                tempo = 0.95
            case .settled:
                tempo = 0.72
            }

            let sweepPeriod = max(0.72, 1.38 - burst * 0.42)
            let normalized = phase.truncatingRemainder(dividingBy: sweepPeriod * tempo) / (sweepPeriod * tempo)
            return normalized
        }

        private func statePulse(phase: TimeInterval) -> Double {
            let frequency: Double
            let phaseOffset: Double

            switch activityMode {
            case .waiting:
                frequency = pendingActionCount > 0 ? 2.7 : 2.0
                phaseOffset = 0.15
            case .running:
                frequency = 1.45
                phaseOffset = 1.2
            case .settled:
                frequency = 0.95
                phaseOffset = 2.1
            }

            let wave = (sin(phase * .pi * 2 * frequency + phaseOffset) + 1) / 2
            let floor = activityMode == .waiting ? 0.30 : 0.18
            return floor + wave * (activityMode == .waiting ? 0.70 : 0.58)
        }

        private func burstEnvelope(now: Date) -> Double {
            guard pendingBurstStartedAt != .distantPast else {
                return pendingActionCount > 0 ? 0.72 : 0
            }

            let elapsed = max(0, now.timeIntervalSince(pendingBurstStartedAt))
            let halfLife = pendingActionCount > 0 ? 0.32 : 0.48
            let decay = exp(-elapsed / halfLife)
            return min(1, max(0, decay))
        }

        @ViewBuilder
        private func scanSweep(width: CGFloat, phase: TimeInterval, burst: Double) -> some View {
            let sweep = max(10, width * (pendingActionCount > 0 ? 0.28 : 0.22))
            let offset = scanOffset(phase: phase, width: width, burst: burst)
            let glow = stateAccent.opacity((pendingActionCount > 0 ? 0.34 : 0.24) + burst * 0.18)

            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                glow,
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: sweep)
                    .offset(x: offset)
                    .blendMode(.screen)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.12 + burst * 0.18),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(4, sweep * 0.28))
                    .offset(x: offset + sweep * 0.18)
                    .blendMode(.plusLighter)
            }
        }

        @ViewBuilder
        private func statePulseLayer(width: CGFloat, phase: TimeInterval, burst: Double) -> some View {
            let pulse = statePulse(phase: phase)
            let opacity = reduceMotion ? 0.14 : min(0.24, 0.08 + pulse * 0.08 + burst * 0.06)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            stateAccent.opacity(opacity),
                            stateAccent.opacity(opacity * 0.55),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: 14)
                .blur(radius: reduceMotion ? 0.8 : 2.0)
                .blendMode(.screen)
        }

        @ViewBuilder
        private func pendingBurstLayer(width: CGFloat, height: CGFloat, burst: Double) -> some View {
            if burst > 0.02 {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(stateAccent.opacity(0.08 + burst * 0.16), lineWidth: 1)
                    .frame(width: width, height: height)
                    .blur(radius: reduceMotion ? 0.25 : 0.8)
                    .scaleEffect(1 + burst * 0.05)
                    .blendMode(.screen)
            }
        }

        private func scanOffset(phase: TimeInterval, width: CGFloat, burst: Double) -> CGFloat {
            let tempo: Double
            switch activityMode {
            case .waiting:
                tempo = pendingActionCount > 0 ? 1.0 : 1.32
            case .running:
                tempo = 1.55
            case .settled:
                tempo = 1.82
            }

            let cycle = phase.truncatingRemainder(dividingBy: tempo) / tempo
            let travelWidth = width + max(12, width * 0.22)
            let sweep = CGFloat(cycle) * travelWidth - max(10, width * 0.08)
            return sweep + CGFloat((burst - 0.5) * width * 0.08)
        }

        private func pendingBadgeColor(phase: TimeInterval, burst: Double) -> Color {
            let pulse = (sin(phase * .pi * 2.8) + 1) / 2
            let intensity = 0.84 + pulse * 0.12 + burst * 0.06
            return Color.white.opacity(min(1, intensity))
        }

        private func pendingJitterOffset(phase: TimeInterval, burst: Double) -> CGSize {
            guard pendingActionCount > 0 else { return .zero }

            let xFrequency: Double = reduceMotion ? 1.8 : 3.2
            let yFrequency: Double = reduceMotion ? 1.2 : 2.4
            let xAmplitude: Double = reduceMotion ? 0.06 : 0.22
            let yAmplitude: Double = reduceMotion ? 0.04 : 0.16
            let x = sin(phase * .pi * xFrequency + burst * 4.1) * xAmplitude * burst
            let y = cos(phase * .pi * yFrequency + burst * 2.6) * yAmplitude * burst
            return CGSize(width: x, height: y)
        }

        @ViewBuilder
        private func pendingWarningRibbon(phase: TimeInterval, burst: Double, width: CGFloat) -> some View {
            let clampedWidth = max(width, 1)
            let scan = pendingScanOffset(phase: phase, width: clampedWidth, burst: burst)
            let rowCount = 8

            return ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.34, green: 0.09, blue: 0.08).opacity(0.92),
                                Color(red: 0.94, green: 0.57, blue: 0.15).opacity(0.82),
                                Color(red: 0.99, green: 0.82, blue: 0.34).opacity(0.78)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .stroke(Color.white.opacity(0.08 + burst * 0.10), lineWidth: 0.6)
                    )

                HStack(spacing: 1.5) {
                    ForEach(0..<rowCount, id: \.self) { column in
                        VStack(spacing: 0.7) {
                            RoundedRectangle(cornerRadius: 0.4, style: .continuous)
                                .fill(warningPixelColor(column: column, phase: phase, burst: burst))
                                .frame(width: 2.2, height: 1.5)

                            RoundedRectangle(cornerRadius: 0.4, style: .continuous)
                                .fill(warningPixelColor(column: column + 1, phase: phase + 0.08, burst: burst * 0.95))
                                .frame(width: 2.2, height: 1.1)
                        }
                        .offset(y: column.isMultiple(of: 2) ? -0.12 : 0.12)
                    }
                }
                .padding(.horizontal, 1)
                .offset(x: reduceMotion ? 0 : sin((phase * .pi * 1.8) + burst * 2.3) * 0.12)
                .blendMode(.screen)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.18 + burst * 0.12),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(8, clampedWidth * 0.22))
                    .offset(x: scan)
                    .blendMode(.plusLighter)

                Rectangle()
                    .fill(Color.white.opacity(0.22 + burst * 0.12))
                    .frame(height: 1)
                    .offset(y: -0.2)
            }
            .compositingGroup()
        }

        private func warningPixelColor(column: Int, phase: TimeInterval, burst: Double) -> Color {
            let pulse = (sin(phase * .pi * 3.5 + Double(column) * 0.35) + 1) / 2
            let amber = 0.72 + pulse * 0.18 + burst * 0.06
            return Color(red: 1.0, green: 0.74, blue: 0.22).opacity(min(1, amber))
        }

        private func pendingScanOffset(phase: TimeInterval, width: CGFloat, burst: Double) -> CGFloat {
            let tempo = reduceMotion ? 1.05 : (pendingActionCount > 0 ? 0.82 : 1.15)
            let cycle = phase.truncatingRemainder(dividingBy: tempo) / tempo
            let travelWidth = width + max(10, width * 0.18)
            return CGFloat(cycle) * travelWidth - max(8, width * 0.08) + CGFloat((burst - 0.5) * width * 0.05)
        }

        private struct CompactAgentIslandWidthPreferenceKey: PreferenceKey {
            static var defaultValue: CGFloat = 0

            static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
                value = max(value, nextValue())
            }
        }

        private var activityMode: ActivityMode {
            if pendingActionCount > 0 {
                return .waiting
            }
            if activeSessionCount > 1 {
                return .running
            }
            return .settled
        }

        private var stateAccent: Color {
            switch activityMode {
            case .waiting:
                return Color(red: 1.0, green: 0.84, blue: 0.45)
            case .running:
                return Color(red: 0.68, green: 0.90, blue: 1.0)
            case .settled:
                return Color(red: 0.68, green: 0.95, blue: 0.78)
            }
        }
    }

    private struct CompactAgentIslandTransitionModifier: ViewModifier {
        let progress: CGFloat

        func body(content: Content) -> some View {
            content
                .opacity(progress)
                .scaleEffect(0.92 + (progress * 0.08), anchor: .top)
                .overlay {
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        let bandWidth = max(12, width * 0.34)
                        let bandOffset = (width + bandWidth) * (1 - progress)

                        RoundedRectangle(cornerRadius: bandWidth / 2, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Color.white.opacity(0.08 + Double(progress) * 0.22),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: bandWidth)
                            .offset(x: bandOffset - bandWidth * 0.54)
                            .blendMode(.screen)
                    }
                    .allowsHitTesting(false)
                }
        }
    }

    private struct OpenAgentPanelTransitionModifier: ViewModifier {
        let progress: CGFloat

        func body(content: Content) -> some View {
            content
                .opacity(progress)
                .scaleEffect(0.965 + (progress * 0.035), anchor: .top)
                .overlay {
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        let height = max(proxy.size.height, 1)
                        let transitionResidue = max(0, min(1, 1 - progress))
                        let rows = max(8, Int(ceil(height / 24)))
                        let rowHeight = height / CGFloat(rows)
                        let revealLead = max(0, min(1, progress * 1.18))
                        let bandHeight = max(12, height * 0.14)
                        let bandOffset = (1 - progress) * (height + bandHeight) - bandHeight * 0.24

                        ZStack(alignment: .topLeading) {
                            VStack(spacing: max(1, rowHeight * 0.18)) {
                                ForEach(0..<rows, id: \.self) { row in
                                    HStack(spacing: 2) {
                                        ForEach(0..<10, id: \.self) { column in
                                            RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                                                .fill(
                                                    Color.white.opacity(
                                                        pixelRevealOpacity(
                                                            row: row,
                                                            column: column,
                                                            progress: progress,
                                                            revealLead: revealLead
                                                        )
                                                    )
                                                )
                                                .frame(width: max(2, width / 28), height: max(1.6, rowHeight * 0.28))
                                        }
                                    }
                                    .offset(x: row.isMultiple(of: 2) ? -0.25 : 0.25)
                                    .blendMode(.screen)
                                }
                            }
                            .frame(width: width, height: height, alignment: .topLeading)
                            .clipped()

                            RoundedRectangle(cornerRadius: bandHeight / 2, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            Color.white.opacity(0.06 + Double(progress) * 0.24),
                                            Color.white.opacity(0.18 + Double(progress) * 0.18),
                                            .clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: max(14, width * 0.34), height: bandHeight)
                                .offset(x: (width + max(14, width * 0.34)) * (1 - progress) - max(14, width * 0.17), y: bandOffset)
                                .blendMode(.screen)

                            RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                                .fill(Color(red: 0.95, green: 0.72, blue: 0.28).opacity(0.08 + Double(progress) * 0.12))
                                .frame(width: width, height: max(3, height * 0.05))
                                .offset(y: max(0, height * 0.08))
                                .blur(radius: 0.8)
                                .blendMode(.plusLighter)
                        }
                        .opacity(transitionResidue)
                        .allowsHitTesting(false)
                    }
                }
        }

        private func pixelRevealOpacity(
            row: Int,
            column: Int,
            progress: CGFloat,
            revealLead: CGFloat
        ) -> Double {
            let rowRatio = CGFloat(row) / 10
            let columnBias = CGFloat(column % 3) * 0.06
            let reveal = max(0, min(1, (revealLead * 1.12) - (rowRatio * 0.84) + columnBias))
            let base = 0.04 + Double(reveal) * 0.26
            return min(0.34, base + Double(progress) * 0.08)
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.shouldShowSneakPeek(on: vm.screenUUID),
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.shouldShowSneakPeek(on: self.vm.screenUUID) else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
