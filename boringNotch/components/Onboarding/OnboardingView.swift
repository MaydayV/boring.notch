//
//  OnboardingView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

enum OnboardingStep {
    case identifyCLI
    case installHooks
    case finished
}

private func onboardingText(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let titleKey: String
    let messageKey: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.effectiveAccent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(onboardingText(titleKey))
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(onboardingText(messageKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingChecklistRow: View {
    let icon: String
    let titleKey: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 24, height: 24)
                .padding(.top, 1)

            Text(onboardingText(titleKey))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingPageShell<Content: View>: View {
    let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                content()
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 560)
        }
    }
}

private struct OnboardingIdentifyCLIView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingPageShell {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.36),
                                    Color.effectiveAccent.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    VStack(spacing: 14) {
                        Image("logo2")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 84, height: 84)

                        VStack(spacing: 6) {
                            Text(onboardingText("onboarding.welcome.title"))
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)

                            Text(onboardingText("onboarding.welcome.subtitle"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(24)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(onboardingText("onboarding.welcome.agents.section_title"))
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(onboardingText("onboarding.welcome.agents.section_body"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 14) {
                    OnboardingFeatureRow(
                        icon: "terminal.fill",
                        titleKey: "onboarding.welcome.agents.multi_provider.title",
                        messageKey: "onboarding.welcome.agents.multi_provider.body"
                    )

                    OnboardingFeatureRow(
                        icon: "doc.text.magnifyingglass",
                        titleKey: "onboarding.welcome.agents.session_reading.title",
                        messageKey: "onboarding.welcome.agents.session_reading.body"
                    )

                    OnboardingFeatureRow(
                        icon: "message.and.waveform.fill",
                        titleKey: "onboarding.welcome.agents.interactions.title",
                        messageKey: "onboarding.welcome.agents.interactions.body"
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )

                Button(action: onContinue) {
                    Text(onboardingText("onboarding.welcome.cta"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}

private struct OnboardingInstallHooksView: View {
    let isInstallingHooks: Bool
    let installErrorMessage: String?
    let onInstallHooks: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        OnboardingPageShell {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Color.effectiveAccent)

                    VStack(spacing: 6) {
                        Text(onboardingText("onboarding.agents_setup.title"))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        Text(onboardingText("onboarding.agents_setup.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    OnboardingChecklistRow(
                        icon: "1.circle.fill",
                        titleKey: "onboarding.agents_setup.checklist.folder_access"
                    )

                    OnboardingChecklistRow(
                        icon: "2.circle.fill",
                        titleKey: "onboarding.agents_setup.checklist.install_hooks"
                    )

                    OnboardingChecklistRow(
                        icon: "3.circle.fill",
                        titleKey: "onboarding.agents_setup.checklist.return_here"
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )

                VStack(spacing: 12) {
                    Button(action: onInstallHooks) {
                        HStack(spacing: 10) {
                            if isInstallingHooks {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Text(onboardingText("onboarding.agents_setup.continue"))
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isInstallingHooks)

                    Button(action: onOpenSettings) {
                        Label(
                            onboardingText("onboarding.agents_setup.open_settings"),
                            systemImage: "gearshape"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if let installErrorMessage {
                    Text(installErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(onboardingText("onboarding.agents_setup.footer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OnboardingView: View {
    @State var step: OnboardingStep = .identifyCLI
    @State private var isInstallingHooks = false
    @State private var installErrorMessage: String?

    let onFinish: () -> Void
    let onOpenSettings: () -> Void
    private let hookInstaller = AgentHookInstaller()

    var body: some View {
        ZStack {
            onboardingBackground

            switch step {
            case .identifyCLI:
                OnboardingIdentifyCLIView {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        step = .installHooks
                    }
                }
                .transition(.opacity)

            case .installHooks:
                OnboardingInstallHooksView(
                    isInstallingHooks: isInstallingHooks,
                    installErrorMessage: installErrorMessage,
                    onInstallHooks: installHooks,
                    onOpenSettings: onOpenSettings
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: step)
        .frame(width: 400, height: 600)
    }

    private var onboardingBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.effectiveAccent.opacity(0.20),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 360
            )
            .blendMode(.screen)
            .ignoresSafeArea()
        }
    }

    private func installHooks() {
        guard !isInstallingHooks else { return }

        isInstallingHooks = true
        installErrorMessage = nil

        let providers = AgentProvider.allCases

        DispatchQueue.global(qos: .userInitiated).async { [hookInstaller] in
            do {
                try hookInstaller.installOrRepairHooks(for: providers)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        isInstallingHooks = false
                        installErrorMessage = nil
                        step = .finished
                    }
                }
            } catch {
                let localizedError = error.localizedDescription
                let permissionRequired = localizedError.localizedCaseInsensitiveContains("Permission required")
                let message = permissionRequired
                    ? onboardingText("agents.settings.hook_install_permission_needed")
                    : AgentLocalization.format("agents.settings.hook_install_failure", localizedError)

                DispatchQueue.main.async {
                    isInstallingHooks = false
                    installErrorMessage = message
                    if permissionRequired {
                        onOpenSettings()
                    }
                }
            }
        }
    }
}

#Preview {
    OnboardingView(onFinish: { }, onOpenSettings: { })
}
