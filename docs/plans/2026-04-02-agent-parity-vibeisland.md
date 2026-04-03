# Agent Parity (Vibe Island) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the Agents experience to match the reference product interaction model: provider-focused switching, actionable session cards, compact island status, and first-launch setup entry.

**Architecture:** Keep existing bridge/event pipeline, but redesign presentation and interaction layers. Agent data ingestion stays in `AgentHubManager`/scanner, while UI is reorganized into three layers: setup (Onboarding + Settings), operation (Agents Tab), and ambient signal (closed-notch island summary). Provider root authorization remains sandbox-safe and mapped to provider-specific scan roots.

**Tech Stack:** SwiftUI + AppKit window hosting, Defaults, existing Agent managers (`AgentHubManager`, `AgentProviderScanner`, `AgentHookInstaller`).

### Task 1: Agents Tab parity UI (provider switch + operation-first interaction)

**Files:**
- Modify: `boringNotch/components/Agents/AgentsTabView.swift`
- Modify: `boringNotch/components/Agents/AgentSessionCardView.swift`
- Modify: `boringNotch/components/Agents/AgentClosedSummaryView.swift`

**Steps:**
1. Introduce explicit provider switch section (All + per-provider) with visual active state.
2. Reorder top area to emphasize operational status (running, waiting action, refresh, jump enabled).
3. Align session cards to operation model: status, usage, actionable controls, clearer pending-action affordance.
4. Preserve existing hooks (approve/deny/answer/jump), only change interaction hierarchy and visual structure.
5. Build and verify no regressions in action callbacks.

### Task 2: Compact island state for agent activity (closed notch)

**Files:**
- Modify: `boringNotch/ContentView.swift`
- (Optional helper) Create: `boringNotch/components/Agents/AgentCompactIslandView.swift`

**Steps:**
1. Add compact ambient state component shown when agent sessions are active and notch is closed.
2. Display provider badge + activity bars/token pulse style to mimic reference rhythm.
3. Respect existing state precedence (music/live activities should remain higher priority where applicable).
4. Ensure no hit-testing regressions when notch closed/open transitions happen.
5. Build and run visual sanity check.

### Task 3: First-launch onboarding parity for Agents setup

**Files:**
- Modify: `boringNotch/components/Onboarding/OnboardingView.swift`
- Modify: `boringNotch/components/Onboarding/OnboardingFinishView.swift`
- Modify: `boringNotch/boringNotchApp.swift`

**Steps:**
1. Redesign welcome/first-launch sequence to include an Agents setup entry (provider support + bridge concept).
2. Keep existing permissions flow functional, but place Agents setup narrative at the front.
3. Add direct path to Agents settings from onboarding completion.
4. Keep window lifecycle stable (single onboarding window controller).
5. Build and verify first-launch path opens and closes correctly.

### Task 4: Provider directory semantics and settings clarity

**Files:**
- Modify: `boringNotch/components/Settings/Views/AgentsSettingsView.swift`
- Modify: `boringNotch/managers/Agents/AgentProviderScanner.swift`
- Modify: `boringNotch/models/Constants.swift`

**Steps:**
1. Distinguish authorization root vs effective provider scan paths in UI.
2. Keep Home-root authorization behavior sandbox-safe, but present provider-specific effective targets.
3. Ensure Codex prefers `session_index.jsonl` before deep session tree parsing.
4. Keep scan budget/large-file safeguards enabled to prevent freeze.
5. Build and run quick smoke check on settings tab and agents tab.

### Task 5: Localization and copy normalization

**Files:**
- Modify: `boringNotch/Localizable.xcstrings`
- Modify: any touched UI files that still contain hardcoded strings

**Steps:**
1. Add/normalize all newly introduced strings via localization keys.
2. Ensure Chinese + English both complete for new Agents/onboarding copy.
3. Remove hardcoded UI text in touched modules.
4. Build and manually inspect Agents settings/tab and onboarding for untranslated text.

### Verification Checklist

1. Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
2. Open app and verify:
- Agents tab opens without freeze.
- Provider switch updates visible sessions correctly.
- Pending actions can approve/deny/answer.
- Closed-notch compact agent status appears when sessions are active.
- First-launch onboarding includes Agents setup entry and can open settings.
- Agents settings shows effective provider paths (not misleading root-only path).
