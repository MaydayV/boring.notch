//
//  OnboardingFinishView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

private func onboardingText(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct OnboardingFinishView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.effectiveAccent.opacity(0.18),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 18,
                endRadius: 340
            )
            .blendMode(.screen)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    Spacer(minLength: 0)

                    VStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.30),
                                            Color.effectiveAccent.opacity(0.16)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )

                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(Color.effectiveAccent)
                        }
                        .frame(width: 120, height: 120)

                        VStack(spacing: 6) {
                            Text(onboardingText("onboarding.finish.title"))
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)

                            Text(onboardingText("onboarding.finish.body"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(spacing: 12) {
                        Button(action: onOpenSettings) {
                            Label(
                                onboardingText("onboarding.finish.open_settings"),
                                systemImage: "gearshape"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button(action: onFinish) {
                            Text(onboardingText("onboarding.finish.complete"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 6)

                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 560)
            }
        }
    }
}

#Preview {
    OnboardingFinishView(onFinish: { }, onOpenSettings: { })
}
