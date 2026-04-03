import Foundation
import Defaults

enum AgentHookSupportState: String, Codable, CaseIterable {
    case installed
    case notInstalled
    case permissionRequired
    case cliNotFound
    case unsupported
}

struct AgentHookProviderStatus: Identifiable, Equatable {
    var id: String { provider.rawValue }

    let provider: AgentProvider
    let cliAvailable: Bool
    let hookInstalled: Bool
    let configPath: String
    let supportState: AgentHookSupportState
}

final class AgentHookInstaller {
    private enum HookFormat {
        case codex
        case claude
        case gemini
    }

    private struct HookSpec {
        let configURL: URL
        let format: HookFormat
        let eventNames: [String]
        let scopedRootURL: URL?
    }

    private let fileManager: FileManager
    private let sandboxHomePath: String
    private let isSandboxedEnvironment: Bool

    private enum InstallError: LocalizedError {
        case permissionRequired(provider: String, path: String)
        case bridgeCommandFailed(path: String, underlying: Error)
        case installFailed(provider: String, path: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .permissionRequired(let provider, let path):
                return "Permission required for \(provider) at \(path)"
            case .bridgeCommandFailed(let path, let underlying):
                return "Failed to install bridge command at \(path): \(underlying.localizedDescription)"
            case .installFailed(let provider, let path, let underlying):
                return "Failed to install hooks for \(provider) at \(path): \(underlying.localizedDescription)"
            }
        }
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.sandboxHomePath = AgentRuntimePaths.sandboxHomeDirectoryURL.standardizedFileURL.path
        let environment = ProcessInfo.processInfo.environment
        self.isSandboxedEnvironment =
            environment["APP_SANDBOX_CONTAINER_ID"] != nil ||
            sandboxHomePath.contains("/Library/Containers/")
    }

    func ensureBridgeCommandInstalled() throws -> URL {
        let commandURL = AgentRuntimePaths.bridgeCommandURL
        try fileManager.createDirectory(
            at: commandURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Self.bridgeScript.write(to: commandURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: commandURL.path)
        return commandURL
    }

    func installOrRepairHooks(for providers: [AgentProvider]) throws {
        do {
            _ = try ensureBridgeCommandInstalled()
        } catch {
            throw InstallError.bridgeCommandFailed(
                path: AgentRuntimePaths.bridgeCommandURL.path,
                underlying: error
            )
        }

        for provider in providers {
            guard let spec = hookSpec(for: provider) else {
                continue
            }
            if requiresAuthorization(for: spec) {
                throw InstallError.permissionRequired(
                    provider: provider.displayName,
                    path: spec.configURL.path
                )
            }
            do {
                try withSecurityScopedAccess(spec.scopedRootURL) {
                    try installHook(for: provider, spec: spec)
                }
            } catch {
                throw InstallError.installFailed(
                    provider: provider.displayName,
                    path: spec.configURL.path,
                    underlying: error
                )
            }
        }
    }

    func inspectHookStatus(for providers: [AgentProvider]) -> [AgentHookProviderStatus] {
        let bridgeExists = fileManager.fileExists(atPath: AgentRuntimePaths.bridgeCommandURL.path)

        return providers.map { provider in
            guard let spec = hookSpec(for: provider) else {
                return AgentHookProviderStatus(
                    provider: provider,
                    cliAvailable: isCommandAvailable(provider.commandName),
                    hookInstalled: false,
                    configPath: "—",
                    supportState: .unsupported
                )
            }

            let cliAvailable = isCommandAvailable(provider.commandName)
            if requiresAuthorization(for: spec) {
                return AgentHookProviderStatus(
                    provider: provider,
                    cliAvailable: cliAvailable,
                    hookInstalled: false,
                    configPath: spec.configURL.path,
                    supportState: .permissionRequired
                )
            }

            let hookInstalled = withSecurityScopedAccess(spec.scopedRootURL) {
                bridgeExists && isHookInstalled(for: provider, spec: spec)
            }
            let supportState: AgentHookSupportState
            if !cliAvailable {
                supportState = .cliNotFound
            } else if hookInstalled {
                supportState = .installed
            } else {
                supportState = .notInstalled
            }

            return AgentHookProviderStatus(
                provider: provider,
                cliAvailable: cliAvailable,
                hookInstalled: hookInstalled,
                configPath: spec.configURL.path,
                supportState: supportState
            )
        }
    }

    private func hookSpec(for provider: AgentProvider) -> HookSpec? {
        guard let target = resolveHookTarget(for: provider) else {
            return nil
        }
        switch provider {
        case .codex:
            return HookSpec(
                configURL: target.configURL,
                format: .codex,
                eventNames: ["SessionStart", "Stop", "SubagentStop", "UserPromptSubmit", "PermissionRequest", "PreToolUse", "PostToolUse"],
                scopedRootURL: target.scopedRootURL
            )
        case .claude:
            return HookSpec(
                configURL: target.configURL,
                format: .claude,
                eventNames: ["SessionStart", "SessionEnd", "Stop", "SubagentStop", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest"],
                scopedRootURL: target.scopedRootURL
            )
        case .gemini:
            return HookSpec(
                configURL: target.configURL,
                format: .gemini,
                eventNames: ["SessionStart", "SessionEnd", "SubagentStop", "BeforeAgent", "AfterAgent", "BeforeTool", "AfterTool"],
                scopedRootURL: target.scopedRootURL
            )
        case .cursor, .opencode, .droid, .openclaw:
            return nil
        }
    }

    private struct HookTarget {
        let configURL: URL
        let scopedRootURL: URL?
    }

    private func resolveHookTarget(for provider: AgentProvider) -> HookTarget? {
        guard let defaultConfigURL = AgentRuntimePaths.defaultHookConfigURL(for: provider) else {
            return nil
        }

        guard let bookmarkRoot = resolveBookmarkRoot(for: provider) else {
            return HookTarget(configURL: defaultConfigURL, scopedRootURL: nil)
        }

        let configURL = AgentRuntimePaths.resolvedHookConfigURL(for: provider, bookmarkRoot: bookmarkRoot) ?? defaultConfigURL
        return HookTarget(configURL: configURL, scopedRootURL: bookmarkRoot)
    }

    private func resolveBookmarkRoot(for provider: AgentProvider) -> URL? {
        let bookmarkData: Data?
        switch provider {
        case .claude:
            bookmarkData = Defaults[.claudeAgentRootBookmark]
        case .codex:
            bookmarkData = Defaults[.codexAgentRootBookmark]
        case .gemini:
            bookmarkData = Defaults[.geminiAgentRootBookmark]
        case .cursor:
            bookmarkData = Defaults[.cursorAgentRootBookmark]
        case .opencode:
            bookmarkData = Defaults[.openCodeAgentRootBookmark]
        case .droid:
            bookmarkData = Defaults[.droidAgentRootBookmark]
        case .openclaw:
            bookmarkData = Defaults[.openClawAgentRootBookmark]
        }

        guard let bookmarkData, !bookmarkData.isEmpty else {
            return nil
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale,
           let refreshed = try? resolvedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
           ) {
            switch provider {
            case .claude:
                Defaults[.claudeAgentRootBookmark] = refreshed
            case .codex:
                Defaults[.codexAgentRootBookmark] = refreshed
            case .gemini:
                Defaults[.geminiAgentRootBookmark] = refreshed
            case .cursor:
                Defaults[.cursorAgentRootBookmark] = refreshed
            case .opencode:
                Defaults[.openCodeAgentRootBookmark] = refreshed
            case .droid:
                Defaults[.droidAgentRootBookmark] = refreshed
            case .openclaw:
                Defaults[.openClawAgentRootBookmark] = refreshed
            }
        }

        return resolvedURL
    }

    private func requiresAuthorization(for spec: HookSpec) -> Bool {
        guard isSandboxedEnvironment else {
            return false
        }
        if spec.scopedRootURL != nil {
            return false
        }
        let targetPath = spec.configURL.standardizedFileURL.path
        return !targetPath.hasPrefix(sandboxHomePath + "/")
    }

    private func withSecurityScopedAccess<T>(_ rootURL: URL?, _ block: () throws -> T) rethrows -> T {
        guard let rootURL else {
            return try block()
        }
        let didStart = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }
        return try block()
    }

    private func installHook(for provider: AgentProvider, spec: HookSpec) throws {
        switch spec.format {
        case .codex:
            try installJSONHook(provider: provider, spec: spec)
        case .claude, .gemini:
            try installJSONHook(provider: provider, spec: spec)
        }
    }

    private func installJSONHook(provider: AgentProvider, spec: HookSpec) throws {
        var root = try loadJSONObject(at: spec.configURL)

        if provider == .gemini {
            var tools = root["tools"] as? [String: Any] ?? [:]
            tools["enableHooks"] = true
            root["tools"] = tools
        }

        var hooksRoot = root["hooks"] as? [String: Any] ?? [:]
        let bridgeCommand = bridgeHookCommand(for: provider)

        for eventName in spec.eventNames {
            var eventEntries = hooksRoot[eventName] as? [[String: Any]] ?? []
            eventEntries = eventEntries.map {
                rewriteBridgeHookCommands(
                    in: $0,
                    commandPath: AgentRuntimePaths.bridgeCommandURL.path,
                    source: provider.rawValue,
                    replacementCommand: bridgeCommand
                )
            }

            if !containsHookCommand(entries: eventEntries, expectedCommand: bridgeCommand) {
                var commandConfig: [String: Any] = [
                    "type": "command",
                    "command": bridgeCommand
                ]
                if provider == .codex {
                    commandConfig["timeout"] = 5
                } else if provider == .gemini {
                    commandConfig["timeout"] = 5000
                } else if provider == .claude, eventName == "PermissionRequest" {
                    commandConfig["timeout"] = 86400
                }

                var hookEntry: [String: Any] = [
                    "hooks": [commandConfig]
                ]
                if provider != .codex {
                    hookEntry["matcher"] = "*"
                }
                eventEntries.append(hookEntry)
            }
            hooksRoot[eventName] = eventEntries
        }

        root["hooks"] = hooksRoot
        try writeJSONObject(root, to: spec.configURL)
    }

    private func isHookInstalled(for provider: AgentProvider, spec: HookSpec) -> Bool {
        if quickTextProbe(provider: provider, configURL: spec.configURL) {
            return true
        }
        switch spec.format {
        case .codex:
            guard let root = try? loadJSONObject(at: spec.configURL),
                  let hooksRoot = root["hooks"] as? [String: Any] else {
                return false
            }

            let expectedCommand = bridgeHookCommand(for: provider)
            for eventName in spec.eventNames {
                guard let entries = hooksRoot[eventName] as? [[String: Any]] else {
                    continue
                }
                if containsHookCommand(entries: entries, expectedCommand: expectedCommand) {
                    return true
                }
            }
            return false
        case .claude, .gemini:
            guard let root = try? loadJSONObject(at: spec.configURL),
                  let hooksRoot = root["hooks"] as? [String: Any] else {
                return false
            }

            let expectedCommand = bridgeHookCommand(for: provider)
            for eventName in spec.eventNames {
                guard let entries = hooksRoot[eventName] as? [[String: Any]] else {
                    continue
                }
                if containsHookCommand(entries: entries, expectedCommand: expectedCommand) {
                    return true
                }
            }
            return false
        }
    }

    private func quickTextProbe(provider: AgentProvider, configURL: URL) -> Bool {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8), !text.isEmpty else {
            return false
        }
        let command = bridgeHookCommand(for: provider)
        return text.contains(command)
    }

    private func containsHookCommand(entries: [[String: Any]], expectedCommand: String) -> Bool {
        return entries.contains { entry in
            containsHookCommand(in: entry, expected: expectedCommand)
        }
    }

    private func containsHookCommand(in object: [String: Any], expected: String) -> Bool {
        for value in object.values {
            if let command = value as? String, command == expected {
                return true
            }
            if let nested = value as? [String: Any],
               containsHookCommand(in: nested, expected: expected) {
                return true
            }
            if let array = value as? [Any] {
                for element in array {
                    if let command = element as? String, command == expected {
                        return true
                    }
                    if let nested = element as? [String: Any],
                       containsHookCommand(in: nested, expected: expected) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func rewriteBridgeHookCommands(
        in object: [String: Any],
        commandPath: String,
        source: String,
        replacementCommand: String
    ) -> [String: Any] {
        var rewritten: [String: Any] = [:]
        for (key, value) in object {
            rewritten[key] = rewriteBridgeHookCommands(
                value,
                commandPath: commandPath,
                source: source,
                replacementCommand: replacementCommand
            )
        }
        return rewritten
    }

    private func rewriteBridgeHookCommands(
        _ value: Any,
        commandPath: String,
        source: String,
        replacementCommand: String
    ) -> Any {
        if let command = value as? String {
            return shouldRewriteBridgeCommand(
                command,
                commandPath: commandPath,
                source: source
            ) ? replacementCommand : command
        }
        if let dictionary = value as? [String: Any] {
            return rewriteBridgeHookCommands(
                in: dictionary,
                commandPath: commandPath,
                source: source,
                replacementCommand: replacementCommand
            )
        }
        if let array = value as? [Any] {
            return array.map {
                rewriteBridgeHookCommands(
                    $0,
                    commandPath: commandPath,
                    source: source,
                    replacementCommand: replacementCommand
                )
            }
        }
        return value
    }

    private func shouldRewriteBridgeCommand(_ command: String, commandPath: String, source: String) -> Bool {
        guard command.contains(commandPath), command.contains("--source \(source)") else {
            return false
        }
        return !command.contains("/usr/bin/python3")
    }

    private func bridgeHookCommand(for provider: AgentProvider) -> String {
        "/usr/bin/python3 \(AgentRuntimePaths.bridgeCommandURL.path.shellQuoted) --source \(provider.rawValue)"
    }

    private func isCommandAvailable(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", "command -v \(command) >/dev/null 2>&1"]
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else {
            return [:]
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return [:]
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
    }

    private static var bridgeScript: String {
        let supportPath = AgentRuntimePaths.supportDirectoryURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return #"""
#!/usr/bin/python3
from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

APP_ROOT = Path("\#(supportPath)")
EVENTS_FILE = APP_ROOT / "events.ndjson"
RESPONSES_FILE = APP_ROOT / "responses.ndjson"
POLL_INTERVAL_SECONDS = 0.25
POLL_TIMEOUT_SECONDS = 30.0

PERMISSION_EVENT_NAMES = {
    "permission",
    "permission.requested",
    "permission.request",
    "pretooluse",
    "beforetool",
    "beforetooluse",
    "action.requested",
    "notification",
}


def get_source() -> str:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--source", required=True)
    parsed, _ = parser.parse_known_args()
    return parsed.source


def read_raw_payload() -> str:
    stdin_raw = sys.stdin.read()
    if stdin_raw.strip():
        return stdin_raw

    payload_parts = [arg for arg in sys.argv[1:] if not arg.startswith("--source")]
    if payload_parts:
        candidate = " ".join(payload_parts)
        if candidate.strip():
            return candidate

    return ""


def parse_payload(text: str) -> dict:
    if not text.strip():
        return {}
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
        return {"value": parsed}
    except Exception:
        return {"raw": text.strip()}


def normalized_event_name(data: dict) -> str:
    raw_event = str(data.get("event") or data.get("type") or data.get("kind") or "").strip()
    payload = data.get("payload")
    payload_dict = payload if isinstance(payload, dict) else data

    codex_event = payload_dict.get("codex_event_type")
    if isinstance(codex_event, str) and codex_event.strip():
        lowered = codex_event.strip().lower()
        if "session-start" in lowered:
            return "session.started"
        if "stop" in lowered or "session-end" in lowered or "session-finish" in lowered:
            return "session.completed"
        if "user-prompt" in lowered:
            return "session.updated"

    lowered = raw_event.lower().replace("_", "").replace("-", "").replace(".", "")
    if lowered in {"sessionstart", "hooksessionstart"}:
        return "session.started"
    if lowered in {"sessionend", "stop", "stopfailure", "sessioncomplete", "sessioncompleted", "subagentstop", "hooksessionend"}:
        return "session.completed"
    if lowered in {"permissionrequest", "hookpermissionrequest", "pretooluse", "hookpretooluse", "beforetool", "beforetooluse"}:
        return "action.requested"
    if lowered in {"posttooluse", "hookposttooluse", "aftertool", "aftertooluse", "afteragent", "notification", "userpromptsubmit", "hookuserpromptsubmit"}:
        return "session.updated"
    if lowered in {"usageupdated"}:
        return "usage.updated"
    if lowered in {"actionrequested"}:
        return "action.requested"
    if lowered in {"actionresolved", "actionresponded"}:
        return "action.resolved"

    blob = json.dumps(payload_dict, ensure_ascii=False).lower()
    if any(token in blob for token in ("permissionrequest", "needs_approval", "approvalrequired", "approval_required")):
        return "action.requested"
    if isinstance(payload_dict, dict):
        permission_keys = (
            "permission",
            "approval",
            "needsApproval",
            "needs_approval",
            "permissionRequest",
            "permission_request",
            "toolPermission",
            "tool_permission",
            "approvalRequired",
            "approval_required",
        )
        if any(key in payload_dict for key in permission_keys):
            return "action.requested"
    if any(token in blob for token in ("input_tokens", "output_tokens", "total_tokens", "rate_limits")):
        return "usage.updated"
    return "session.updated"


def session_id_for(data: dict) -> str:
    subagent = subagent_metadata(data)
    if subagent is not None:
        parent_thread_id = str(subagent.get("subagentParentThreadId") or "").strip()
        if parent_thread_id:
            return parent_thread_id

    for key in ("sessionId", "session_id", "sessionID", "sessionKey", "id"):
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value
    payload = data.get("payload")
    if isinstance(payload, dict):
        for key in ("sessionId", "session_id", "sessionID", "sessionKey", "id"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return value
    return str(uuid.uuid4())


def subagent_metadata(data: dict) -> dict | None:
    payload = payload_for_event(data)
    source = payload if isinstance(payload, dict) else data
    candidate_sources = []
    if isinstance(source, dict):
        candidate_sources.append(source)
        for key in ("subagent", "subagentInfo", "subagent_info", "childAgent", "child_agent", "agent"):
            nested = source.get(key)
            if isinstance(nested, dict):
                candidate_sources.append(nested)

    for candidate in candidate_sources:
        subagent_id = first_string(candidate, ("subagentId", "subagent_id", "subagentID", "id", "sessionId", "session_id"))
        parent_thread_id = first_string(candidate, ("subagentParentThreadId", "subagent_parent_thread_id", "parentThreadId", "parent_thread_id"))
        name = first_string(candidate, ("subagentName", "subagent_name", "subagentNickname", "subagent_nickname", "nickname", "name", "title"))
        role = first_string(candidate, ("subagentRole", "subagent_role", "role"))
        kind = first_string(candidate, ("subagentType", "subagent_type", "type"))
        if subagent_id or parent_thread_id or name or role:
            return {
                "subagentId": subagent_id or parent_thread_id or str(uuid.uuid4()),
                "subagentName": name,
                "subagentRole": role,
                "subagentType": kind,
                "subagentParentThreadId": parent_thread_id,
            }
    return None


def first_string(candidate: dict, keys: tuple[str, ...]) -> str | None:
    for key in keys:
        value = candidate.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def request_id_for(data: dict) -> str | None:
    for key in ("requestId", "request_id", "actionId", "id"):
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value
    payload = data.get("payload")
    if isinstance(payload, dict):
        for key in ("requestId", "request_id", "actionId", "id"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                return value
    event_name = normalized_event_name(data)
    if event_name.startswith("action."):
        return str(uuid.uuid4())
    return None


def payload_for_event(data: dict) -> dict:
    payload = data.get("payload")
    if isinstance(payload, dict):
        return payload
    return data


def append_event(record: dict) -> None:
    APP_ROOT.mkdir(parents=True, exist_ok=True)
    with EVENTS_FILE.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False))
        handle.write("\n")


def read_matching_response(request_id: str) -> dict | None:
    if not RESPONSES_FILE.exists():
        return None

    try:
        lines = RESPONSES_FILE.read_text(encoding="utf-8").splitlines()
    except Exception:
        return None

    for raw_line in reversed(lines):
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            candidate = json.loads(raw_line)
        except Exception:
            continue
        if str(candidate.get("requestId") or candidate.get("request_id") or "") == request_id:
            return candidate
    return None


def decision_from_response(response: dict) -> bool:
    if "continue" in response:
        value = response.get("continue")
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            return value.strip().lower() not in {"false", "0", "no", "off"}
        return bool(value)

    outcome = str(response.get("outcome") or "").lower()
    if outcome in {"denied", "deny", "rejected", "reject", "false"}:
        return False
    if outcome in {"approved", "allow", "allowed", "answered", "answer", "true"}:
        return True
    return True


def is_permission_event(event_name: str, data: dict) -> bool:
    lowered = event_name.lower()
    if lowered in PERMISSION_EVENT_NAMES:
        return True
    payload = payload_for_event(data)
    if isinstance(payload, dict):
        for key in ("permission", "approval", "needsApproval", "needs_approval", "toolPermission", "tool_permission"):
            if key in payload:
                return True
    return False


def wait_for_response(request_id: str) -> bool:
    deadline = time.time() + POLL_TIMEOUT_SECONDS
    while time.time() < deadline:
        response = read_matching_response(request_id)
        if response is not None:
            return decision_from_response(response)
        time.sleep(POLL_INTERVAL_SECONDS)
    return True


def main() -> int:
    source = get_source().strip().lower()
    raw_payload = read_raw_payload()
    data = parse_payload(raw_payload)
    event_name = normalized_event_name(data)
    session_id = session_id_for(data)
    request_id = request_id_for(data)
    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    payload = payload_for_event(data)
    subagent = subagent_metadata(data)

    record = {
        "schemaVersion": 1,
        "provider": source,
        "source": source,
        "event": event_name,
        "sessionId": session_id,
        "timestamp": timestamp,
        "payload": payload,
    }
    if request_id is not None:
        record["requestId"] = request_id
    if raw_payload and isinstance(payload, dict) and "rawInput" not in payload:
        record["payload"]["rawInput"] = raw_payload
    if isinstance(subagent, dict):
        record["payload"]["subagent"] = subagent
        for key in ("subagentId", "subagentName", "subagentRole", "subagentType", "subagentParentThreadId"):
            if key in subagent and subagent[key] is not None:
                record[key] = subagent[key]

    try:
        append_event(record)
    except Exception:
        print(json.dumps({"continue": not is_permission_event(event_name, data)}))
        return 0

    if request_id and is_permission_event(event_name, data):
        print(json.dumps({"continue": wait_for_response(request_id)}))
    else:
        print(json.dumps({"continue": True}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
"""#
    }
}
