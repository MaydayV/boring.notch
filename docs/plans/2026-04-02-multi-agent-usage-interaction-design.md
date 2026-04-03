# Multi-Agent Usage + Interaction Design

## Goal
Add a new notch experience that can monitor and control many local AI coding agents (not just Claude/Codex), with:
- local usage visibility (sessions, tokens, runtime, optional cost),
- actionable interactions (approve/deny, answer questions, jump back to terminal/app),
- low overhead and no cloud dependency.

## Product Scope (MVP)
- New open-notch tab: `Agents`.
- Closed-notch compact summary:
  - active agent count,
  - top-priority pending action indicator,
  - short usage summary for the current day.
- Per-session cards:
  - provider + session title + status + elapsed time,
  - usage stats if available (tokens in/out, total, optional USD cost),
  - interaction actions when available (Approve, Deny, Answer, Jump).

## MVP Priority (Interaction First)
The first shippable version must include:
- actionable interaction flow (approve/deny/question-answer) end-to-end,
- multi-provider session monitoring in one panel,
- graceful degradation when usage/cost fields are missing.

Read-only monitoring without interaction is not considered complete for MVP.

## Non-Goals (MVP)
- Cross-machine sync.
- Cloud-side persistence/analytics.
- Perfect parser coverage for every community tool on day one.
- Running arbitrary untrusted shell snippets from incoming events.

## Approaches Considered
1. Direct per-tool log parsing in app (Claude/Codex/Gemini/Cursor each hardcoded)
- Pros: fastest initial demo.
- Cons: fragile, hard to scale to many tools, high maintenance.

2. Unified adapter protocol + local bridge event stream (chosen)
- Pros: scales to many providers, keeps app architecture clean, supports both usage and interaction.
- Cons: requires a small bridge layer + adapter installation UX.

3. Full plugin runtime with dynamic code loading
- Pros: maximum extensibility.
- Cons: security/review complexity too high for first release.

## Recommended Architecture

### 1) Core Module Layout
- [NotchViews enum](/Users/colin/Dev/GitHub/boring.notch/boringNotch/enums/generic.swift): add `.agents`.
- [ContentView](/Users/colin/Dev/GitHub/boring.notch/boringNotch/ContentView.swift): add agents branch in open-notch switch.
- [TabSelectionView](/Users/colin/Dev/GitHub/boring.notch/boringNotch/components/Tabs/TabSelectionView.swift): add `Agents` tab behind setting toggle.
- [BoringHeader](/Users/colin/Dev/GitHub/boring.notch/boringNotch/components/Notch/BoringHeader.swift): show tab when agents enabled.
- New managers folder: `boringNotch/managers/Agents/`.
  - `AgentHubManager.swift` (single source of truth for sessions/actions/usage aggregates).
  - `AgentBridgeClient.swift` (reads local event stream, writes responses).
  - `AgentProviderRegistry.swift` (built-in providers + custom provider configs).
  - `AgentJumpService.swift` (jump to terminal/editor target).

### 2) Data Model
- `AgentProviderID`: `claude`, `codex`, `gemini`, `cursor`, `opencode`, `droid`, `aider`, `custom(...)`.
- `AgentSessionState`: `idle`, `running`, `waitingApproval`, `waitingQuestion`, `completed`, `failed`.
- `AgentUsageSnapshot`:
  - `inputTokens`, `outputTokens`, `totalTokens`, `estimatedCostUSD`, `turnCount`, `updatedAt`.
  - All numeric fields optional (some providers cannot expose all values).
- `AgentActionRequest`:
  - `requestId`, `sessionId`, `kind` (`approve`, `question`, `planReview`),
  - payload (diff summary/options/markdown),
  - `deadline`, `priority`.
- `AgentJumpTarget`:
  - app bundle id + window/tab hints + optional terminal command context.

### 3) Event Contract (Local-Only)
Use NDJSON events over a local bridge endpoint (unix socket preferred, file fallback):
- `session.started`
- `session.updated`
- `usage.updated`
- `action.requested`
- `action.resolved`
- `session.completed`
- `session.failed`

All events include:
- `schemaVersion`, `provider`, `sessionId`, `timestamp`, `machineLocalOnly=true`.

For actions:
- app sends `action.responded` with `requestId` + answer.
- bridge returns `action.acked` (or timeout/error).

This keeps integration generic: any tool can become supported by emitting this schema.

### 4) Multi-Tool Support Strategy
Support is split into tiers so the feature can scale beyond a couple of tools:

- Tier A (first-class, built-in adapters):
  - Claude Code
  - OpenAI Codex CLI / Codex Desktop session bridge
  - Gemini CLI
  - Cursor Agent
  - OpenCode
  - Droid

- Tier B (community adapters, enabled via config templates):
  - Aider
  - Goose
  - Continue CLI-like wrappers
  - custom shell-based agent runners

- Tier C (generic fallback):
  - any tool that can emit the normalized NDJSON schema to local socket/stdout/file.

Design rule: providers differ only at adapter edge. Core notch UI/state machine must stay provider-agnostic.

## Interaction Design

### Closed Notch
- Compact label: `Agents 3`.
- If pending approval/question exists, show an accent dot + top pending provider icon.
- Tap opens `Agents` tab directly.

### Open Notch: Agents Tab
- Header:
  - Today usage summary (total tokens, running sessions, pending actions).
  - filter chips: `All`, `Needs Action`, `Running`, `Done`.
- Session list (sorted):
  1. waiting action,
  2. running,
  3. recently completed.
- Card actions:
  - `Approve` / `Deny`
  - quick option buttons for multiple-choice question
  - free-text answer sheet for text questions
  - `Jump` to source terminal/editor
  - optional `Details` popover for full markdown plan/tool log

### Settings
Add an `Agents` settings page in [SettingsView](/Users/colin/Dev/GitHub/boring.notch/boringNotch/components/Settings/SettingsView.swift):
- enable/disable agents feature.
- provider toggles.
- auto-install/repair adapters.
- compact notch policy (`always`, `pending-only`, `off`).
- data retention policy (e.g., keep 1/7/30 days).

## Security and Reliability
- Never execute arbitrary command from event payload.
- Only allow response paths tied to active `requestId` from trusted local bridge.
- Apply provider-level rate limiting/debounce on event floods.
- Persist recent state in app support directory for fast restart recovery.
- Mark stale sessions if heartbeat missing beyond threshold.

## Phased Delivery
1. Foundation
- Add `Agents` tab, manager skeleton, event model, read-only session list.

2. Interaction Core (required for MVP)
- approve/deny/question answering + ack/retry/error states.
- pending-action prioritization in closed and open notch.

3. Usage
- usage aggregation pipeline + today summary + compact closed-notch indicator.

4. Jump + Extensibility
- terminal/editor jump.
- custom provider registration via JSON config.

MVP release gate: phases 1 + 2 + Tier A multi-tool coverage.

## Validation Plan
- Unit tests:
  - event parsing/version compatibility,
  - reducer state transitions,
  - usage aggregation correctness.
- Integration tests:
  - replay fixture NDJSON logs for multiple providers.
- Manual QA:
  - mixed providers in parallel,
  - offline/restart recovery,
  - action timeout and retry UX,
  - CPU and memory impact during long-running sessions.
