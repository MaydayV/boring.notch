# Weather Integration Design (Roadmap)

## Goal
Add a minimal, reliable weather feature to `dev` that fits current notch UX and does not require API keys or server-side components.

## Options Considered
1. Native WeatherKit + CoreLocation  
Pros: native ecosystem, rich data.  
Cons: entitlement and auth overhead, slower contributor onboarding.

2. Third-party paid weather API  
Pros: richer forecast datasets.  
Cons: key management, rate limits, contributor friction.

3. Open-Meteo (chosen)  
Pros: no API key, public geocoding + weather endpoints, easy OSS contribution.  
Cons: simpler dataset, network availability dependent.

## Chosen Scope (MVP)
- Add `WeatherManager` singleton for:
  - City geocoding by name.
  - Current weather fetch.
  - Auto refresh timer.
  - Error/loading state publishing.
- Add settings:
  - Enable Weather.
  - City (string, default fallback).
  - Temperature unit (C/F).
  - Refresh interval (minutes).
- Add open-notch weather card in `NotchHomeView` (Home tab only):
  - City
  - Current temperature
  - Weather symbol + condition text
  - Loading/error fallback text

## Data Flow
1. User enables weather and sets city in Settings.
2. `WeatherManager` observes relevant Defaults keys.
3. Manager resolves city -> lat/lon via Open-Meteo geocoding.
4. Manager fetches current weather (`current_weather=true`) using selected unit.
5. Published state updates `WeatherSummaryCard`.
6. Auto-refresh repeats on configured interval while weather is enabled.

## API Contracts
- Geocoding:
  - `https://geocoding-api.open-meteo.com/v1/search?name={city}&count=1&language=en&format=json`
- Weather:
  - `https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current_weather=true&temperature_unit={celsius|fahrenheit}&wind_speed_unit=kmh&timezone=auto`

## Failure Handling
- Empty city -> fallback to `Cupertino`.
- Geocoding no match -> show `Location not found`.
- Request failure/decoding failure -> show `Weather unavailable`.
- Keep last successful weather snapshot when refresh fails.

## Non-Goals (MVP)
- Hourly/daily forecast panels.
- Location permission and GPS-based auto-location.
- Precipitation charts, severe alerts, radar.

## Phase 2 Extension
- Include today summary extras in weather card:
  - `temperature_2m_max`
  - `temperature_2m_min`
  - `precipitation_probability_max`
- Keep scope read-only (no alerting, no charts), with same fallback/error policy.

## Phase 3 Extension
- Improve request efficiency and data-state clarity:
  - Debounce city input updates before triggering refresh.
  - Cache geocoding results by normalized city key.
  - Add `updatedAt` to snapshot and render "Updated HH:mm" in weather card.
  - If refresh fails but previous snapshot exists, show a stale-data hint while keeping last successful data.

## Phase 4 Extension
- City-input UX for pinyin and localized suggestions:
  - Keep free-text city input, and support lowercase pinyin search.
  - Query geocoding suggestions with `language=zh` while typing.
  - Show selectable city suggestions in Settings.
  - For `country_code == CN`, prefer Chinese candidate display names.
  - Selecting a candidate updates city setting and triggers immediate weather refresh.

## Phase 5 Extension
- Home/calendar decoupling and dedicated weather tab:
  - Remove weather overlay badge from Calendar in Home.
  - Add top-level weather tab (`.weather`) alongside Home/Shelf.
  - Show tab bar when weather is enabled, even if shelf tab is currently hidden.
  - If a tab becomes unavailable (e.g. weather disabled), auto-fallback to Home.
- Dedicated weather tab content:
  - Header: weather title + manual refresh action.
  - Hero row: large condition symbol + large current temperature + condition text.
  - Metadata chips: city, high/low, precipitation.
  - Footer status: updated timestamp + stale-data hint when request fails after a successful fetch.
  - Empty states:
    - Weather disabled prompt.
    - Loading state.
    - Error state with current city context.
    - No-data fallback.
- UX objective:
  - Keep Home focused on music/calendar/camera.
  - Avoid visual overlap and preserve clear ownership per tab.

## Validation Plan
- Build: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -destination 'platform=macOS' build`
- Manual checks:
  - Toggle weather on/off.
  - Change city and unit.
  - Confirm card updates and handles invalid city/network failure gracefully.
  - Verify city typing does not trigger request on every keystroke.
  - Verify stale-data hint appears when network fails after at least one successful fetch.
  - Verify lowercase pinyin input (e.g. `beijing`, `shanghai`) shows candidates.
  - Verify selected CN candidate is displayed in Chinese where available.
