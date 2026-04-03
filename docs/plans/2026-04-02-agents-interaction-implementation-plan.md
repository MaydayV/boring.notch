# Multi-Agent Interaction Hub Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an in-notch multi-agent hub that supports cross-CLI session visibility and direct interactive actions (approve/deny/question/jump) for many code CLI tools.

**Architecture:** Add a provider-agnostic agent domain layer (`AgentHubManager`) that merges two data sources: local session scanners (Claude/Codex/Gemini/OpenCode/OpenClaw) and a local NDJSON bridge for runtime interaction events. Render this via a dedicated `Agents` notch tab and wire interactive responses back to a local responses stream.

**Tech Stack:** SwiftUI, Combine, Defaults, AppKit/AppleScript (Terminal jump), local filesystem (NDJSON append/read).

### Task 1: Add Agent Domain + Bridge Core

**Files:**
- Create: `boringNotch/managers/Agents/AgentModels.swift`
- Create: `boringNotch/managers/Agents/AgentBridgeClient.swift`
- Create: `boringNotch/managers/Agents/AgentProviderScanner.swift`
- Create: `boringNotch/managers/Agents/AgentJumpService.swift`
- Create: `boringNotch/managers/Agents/AgentHubManager.swift`

**Step 1: Write failing focused logic tests (debug harness in same files if no test target exists)**
- Add parser-level validation entry points for malformed NDJSON lines and missing fields.
- Add deterministic reducer-like merge helper assertions (event in, state out) in `#if DEBUG` blocks.

**Step 2: Run local compile/type-check command**
- Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -destination 'platform=macOS' build`
- Expected: compile failures before integration wiring is complete.

**Step 3: Implement minimal passing domain logic**
- Define unified models:
  - provider/session/state/usage/action request/response.
- Implement scanner adapters for 5 providers with robust best-effort parsing.
- Implement bridge reader/writer for events/responses NDJSON.
- Implement `AgentHubManager` APIs:
  - refresh sessions, compute summaries,
  - `approve`, `deny`, `answerChoice`, `answerText`, `jumpToSession`.

**Step 4: Re-run compile command and fix type issues**
- Expected: domain files compile.

### Task 2: Build Agents UI Components

**Files:**
- Create: `boringNotch/components/Agents/AgentsTabView.swift`
- Create: `boringNotch/components/Agents/AgentSessionCardView.swift`
- Optional: `boringNotch/components/Agents/AgentClosedSummaryView.swift`

**Step 1: Add UI states and failing compile references to domain objects**
- Build view skeleton using missing domain methods to force compile-time red.

**Step 2: Implement minimal UI to satisfy compile**
- Top summary row, filter chips, session list.
- Card actions:
  - Jump,
  - approve/deny,
  - choice buttons,
  - text answer submit.
- Empty/loading/error states.

**Step 3: Compile and visually inspect with previews if possible**
- Run same `xcodebuild` command.

### Task 3: Integrate Tab + Settings + App Flow

**Files:**
- Modify: `boringNotch/enums/generic.swift`
- Modify: `boringNotch/components/Tabs/TabSelectionView.swift`
- Modify: `boringNotch/components/Notch/BoringHeader.swift`
- Modify: `boringNotch/ContentView.swift`
- Modify: `boringNotch/components/Settings/SettingsView.swift`
- Create: `boringNotch/components/Settings/Views/AgentsSettingsView.swift`
- Modify: `boringNotch/models/Constants.swift`

**Step 1: Add feature flags/defaults (failing references first)**
- `showAgentsTab`, provider toggles, compact behavior toggle.

**Step 2: Wire new `NotchViews.agents` and settings entry**
- Add Agents tab visibility logic similar to weather/shelf patterns.

**Step 3: Connect Agents tab in open-notch switch**
- Add `case .agents` => `AgentsTabView()`.

**Step 4: Compile and resolve all integration errors**

### Task 4: Harden UX + Error Handling

**Files:**
- Modify: agent manager and agents UI files from prior tasks.

**Step 1: Add safe fallbacks**
- Missing files, malformed events, unknown providers, jump failures.

**Step 2: Add debounce/refresh cadence**
- avoid heavy rescans on every state tick.

**Step 3: Compile and quick manual QA checklist**
- open notch -> agents tab renders,
- manual event file injection updates UI,
- action buttons append responses file,
- jump action triggers terminal execution.

### Task 5: Verification + Documentation

**Files:**
- Modify: `docs/plans/2026-04-02-multi-agent-usage-interaction-design.md` (if implementation deviations)

**Step 1: Run final build verification**
- `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -destination 'platform=macOS' build`

**Step 2: Summarize implemented scope and known gaps**
- Note any provider-specific parsing assumptions.

**Step 3: Commit in logical chunks**
- domain,
- ui,
- integration/settings,
- hardening/docs.
