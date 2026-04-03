//
//  WeatherSettingsView.swift
//  boringNotch
//
//  Created by TheBoredTeam on 2026-03-03.
//

import Defaults
import Foundation
import SwiftUI

struct WeatherSettings: View {
    @ObservedObject private var weatherManager = WeatherManager.shared
    @Default(.showWeather) private var showWeather
    @Default(.weatherCity) private var weatherCity
    @Default(.weatherUnit) private var weatherUnit
    @Default(.weatherRefreshMinutes) private var weatherRefreshMinutes
    @Default(.weatherContentPreference) private var weatherContentPreference

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showWeather) {
                    Text("settings.weather.toggle.show_weather")
                }
                if showWeather {
                    TextField("settings.weather.field.city", text: $weatherCity)
                        .onSubmit {
                            weatherManager.refreshForEnteredCity()
                        }

                    if weatherManager.isLoadingCitySuggestions {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("settings.weather.state.searching_cities")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if !weatherManager.citySuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("settings.weather.section.city_suggestions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(Array(weatherManager.citySuggestions.prefix(8))) { suggestion in
                                Button {
                                    weatherManager.selectCitySuggestion(suggestion)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.displayName)
                                                .lineLimit(1)
                                            if !suggestion.subtitle.isEmpty {
                                                Text(suggestion.subtitle)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Picker("settings.weather.picker.temperature_unit", selection: $weatherUnit) {
                        ForEach(WeatherTemperatureUnit.allCases, id: \.self) { unit in
                            Text(weatherUnitLabel(for: unit)).tag(unit)
                        }
                    }

                    Picker("settings.weather.picker.weather_content", selection: $weatherContentPreference) {
                        Text("settings.weather.option.current_weather_only")
                            .tag(WeatherContentPreference.currentOnly)
                        Text("settings.weather.option.current_and_forecast")
                            .tag(WeatherContentPreference.currentAndForecast)
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $weatherRefreshMinutes, in: 5...120, step: 5) {
                        HStack {
                            Text("settings.weather.label.weather_refresh_interval")
                            Spacer()
                            Text(String(format: String(localized: "settings.weather.value.weather_refresh_minutes_format"), locale: .current, arguments: [weatherRefreshMinutes]))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("settings.weather.section.general")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("settings.sidebar.weather")
    }

    private func weatherUnitLabel(for unit: WeatherTemperatureUnit) -> LocalizedStringKey {
        switch unit {
        case .celsius:
            return "settings.weather.unit.celsius"
        case .fahrenheit:
            return "settings.weather.unit.fahrenheit"
        }
    }
}
