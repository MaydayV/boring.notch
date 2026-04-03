//
//  BatterySettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import SwiftUI

struct Charge: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("settings.battery.toggle.show_battery_indicator")
                }
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("settings.battery.toggle.show_power_status_notifications")
                }
            } header: {
                Text("settings.battery.section.general")
            }
            Section {
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("settings.battery.toggle.show_battery_percentage")
                }
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("settings.battery.toggle.show_power_status_icons")
                }
            } header: {
                Text("settings.battery.section.battery_information")
            }
        }
        .onAppear {
            Task { @MainActor in
                await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("settings.sidebar.battery")
    }
}
