import Foundation
import Defaults
#if canImport(SQLite3)
import SQLite3
#endif

struct AgentProviderScanner: @unchecked Sendable {
    private let fileManager: FileManager
    
    private struct ScanRoot {
        let url: URL
        let securityScopeURL: URL?

        var requiresSecurityScope: Bool {
            securityScopeURL != nil
        }
    }

    private struct ScanBudget {
        var filesRemaining: Int
        var bytesRemaining: Int64

        var isExhausted: Bool {
            filesRemaining <= 0 || bytesRemaining <= 0
        }
    }

    private static let maxBytesPerFileRead = 512 * 1024
    private static let maxJSONLLinesPerFile = 400
    private static let maxChargedBytesPerFile: Int64 = 3 * 1024 * 1024
    private static let maxFilesPerProvider = 240
    private static let maxBytesPerProvider: Int64 = 72 * 1024 * 1024

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scanAllSessions() -> [AgentSessionMeta] {
        scanAllSessionsReport().sessions
    }

    func scanAllSessionsReport() -> AgentScanReport {
        let home = AgentRuntimePaths.realHomeDirectoryURL
        var sessionsByKey: [String: AgentSessionMeta] = [:]
        var deniedRoots: [AgentScanDeniedRoot] = []

        for provider in AgentProvider.allCases {
            let report = scan(provider: provider, homeDirectory: home)
            for session in report.sessions {
                let key = session.id
                if let current = sessionsByKey[key] {
                    sessionsByKey[key] = merge(current, with: session)
                } else {
                    sessionsByKey[key] = session
                }
            }
            deniedRoots.append(contentsOf: report.deniedRoots)
        }

        return AgentScanReport(
            sessions: sessionsByKey.values.sorted(by: sortSessions(_:_:)),
            deniedRoots: dedupeDeniedRoots(deniedRoots)
        )
    }

    func scan(provider: AgentProvider, homeDirectory: URL) -> AgentScanReport {
        let roots = roots(for: provider, homeDirectory: homeDirectory)
        switch provider {
        case .opencode:
            return scanOpenCodeSessions(roots: roots)
        case .cursor, .droid, .openclaw:
            return scanJSONSessions(provider: provider, roots: roots)
        case .codex:
            return scanCodexSessions(homeDirectory: homeDirectory, roots: roots)
        case .claude, .gemini:
            return scanJSONSessions(provider: provider, roots: roots)
        }
    }

    private func scanCodexSessions(homeDirectory: URL, roots: [ScanRoot]) -> AgentScanReport {
        let indexRoots = roots.filter { $0.url.lastPathComponent.lowercased() == "session_index.jsonl" }
        let indexReport = indexRoots.isEmpty ? AgentScanReport(sessions: [], deniedRoots: []) : scanJSONSessions(provider: .codex, roots: indexRoots)
        let sqliteReport = scanCodexStateSessions(homeDirectory: homeDirectory, roots: roots)
        let fallbackReport = scanJSONSessions(provider: .codex, roots: roots)

        var sessionsByKey: [String: AgentSessionMeta] = [:]
        for session in indexReport.sessions + sqliteReport.sessions + fallbackReport.sessions {
            if let current = sessionsByKey[session.id] {
                sessionsByKey[session.id] = merge(current, with: session)
            } else {
                sessionsByKey[session.id] = session
            }
        }

        return AgentScanReport(
            sessions: sessionsByKey.values.sorted(by: sortSessions(_:_:)),
            deniedRoots: dedupeDeniedRoots(indexReport.deniedRoots + sqliteReport.deniedRoots + fallbackReport.deniedRoots)
        )
    }

    private func scanCodexStateSessions(homeDirectory: URL, roots: [ScanRoot]) -> AgentScanReport {
        let codexDirectory = homeDirectory.appendingPathComponent(".codex", isDirectory: true).standardizedFileURL
        let securityScope = roots.first(where: { $0.url.path.contains("/.codex/") })?.securityScopeURL
        let codexRoot = ScanRoot(url: codexDirectory, securityScopeURL: securityScope)
        let deniedRoot = AgentScanDeniedRoot(provider: .codex, rootPath: codexDirectory.path, requiresSecurityScope: securityScope != nil)

        return withRootAccess(codexRoot) { rootURL, accessDenied in
            guard fileManager.fileExists(atPath: rootURL.path) else {
                return AgentScanReport(sessions: [], deniedRoots: accessDenied ? [deniedRoot] : [])
            }

            guard let entries = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return AgentScanReport(sessions: [], deniedRoots: accessDenied ? [deniedRoot] : [])
            }

            let sqliteFiles = entries.filter { url in
                let name = url.lastPathComponent.lowercased()
                guard name.hasPrefix("state_"), name.hasSuffix(".sqlite") else {
                    return false
                }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }

            var sessionsByKey: [String: AgentSessionMeta] = [:]
            for fileURL in sqliteFiles {
                guard let sessions = scanCodexThreadSQLite(fileURL) else { continue }
                for session in sessions {
                    if let current = sessionsByKey[session.id] {
                        sessionsByKey[session.id] = merge(current, with: session)
                    } else {
                        sessionsByKey[session.id] = session
                    }
                }
            }

            return AgentScanReport(
                sessions: sessionsByKey.values.sorted(by: sortSessions(_:_:)),
                deniedRoots: sessionsByKey.isEmpty && accessDenied ? [deniedRoot] : []
            )
        }
    }

    private func scanJSONSessions(provider: AgentProvider, roots: [ScanRoot]) -> AgentScanReport {
        var budget = initialBudget(for: provider)
        var sessions: [AgentSessionMeta] = []
        var deniedRoots: [AgentScanDeniedRoot] = []
        for root in roots {
            guard !budget.isExhausted else {
                break
            }
            let report = scanJSONSessions(in: root, provider: provider, budget: &budget)
            sessions.append(contentsOf: report.sessions)
            deniedRoots.append(contentsOf: report.deniedRoots)
        }
        return AgentScanReport(sessions: sessions, deniedRoots: deniedRoots)
    }

    private func scanJSONSessions(in root: ScanRoot, provider: AgentProvider, budget: inout ScanBudget) -> AgentScanReport {
        let rootDenied = AgentScanDeniedRoot(
            provider: provider,
            rootPath: root.url.path,
            requiresSecurityScope: root.requiresSecurityScope
        )
        return withRootAccess(root) { rootURL, accessDenied in
            var report = AgentScanReport(sessions: [], deniedRoots: [])
            guard fileManager.fileExists(atPath: rootURL.path) else {
                if accessDenied {
                    report.deniedRoots.append(rootDenied)
                }
                return report
            }
            
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
                if accessDenied {
                    report.deniedRoots.append(rootDenied)
                }
                return report
            }
            
            if !isDirectory.boolValue {
                guard provider.allowedExtensions.contains(rootURL.pathExtension.lowercased()) else {
                    if accessDenied {
                        report.deniedRoots.append(rootDenied)
                    }
                    return report
                }
                if let session = scanSessionFile(rootURL, provider: provider, budget: &budget) {
                    report.sessions = [session]
                } else if accessDenied || !fileManager.isReadableFile(atPath: rootURL.path) {
                    report.deniedRoots.append(rootDenied)
                }
                return report
            }
            
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants]
            ) else {
                if accessDenied || !fileManager.isReadableFile(atPath: rootURL.path) {
                    report.deniedRoots.append(rootDenied)
                }
                return report
            }
            
            for case let fileURL as URL in enumerator {
                guard !budget.isExhausted else {
                    break
                }
                guard provider.allowedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                    continue
                }
                guard let session = scanSessionFile(fileURL, provider: provider, budget: &budget) else {
                    if !fileManager.isReadableFile(atPath: fileURL.path) {
                        report.deniedRoots.append(
                            AgentScanDeniedRoot(
                                provider: provider,
                                rootPath: fileURL.path,
                                requiresSecurityScope: root.requiresSecurityScope
                            )
                        )
                    }
                    continue
                }
                report.sessions.append(session)
            }
            
            return report
        }
    }

    private func scanSessionFile(_ fileURL: URL, provider: AgentProvider, budget: inout ScanBudget) -> AgentSessionMeta? {
        guard !budget.isExhausted else {
            return nil
        }

        budget.filesRemaining -= 1
        let fileSize = fileSizeInBytes(for: fileURL)
        budget.bytesRemaining -= min(fileSize, Self.maxChargedBytesPerFile)

        let sessionIdFallback = fileURL.deletingPathExtension().lastPathComponent.trimmedNonEmpty ?? UUID().uuidString
        let fileDate = fileModificationDate(for: fileURL) ?? Date()
        let reader = SessionFileReader(
            fileURL: fileURL,
            provider: provider,
            fallbackSessionId: sessionIdFallback,
            fallbackDate: fileDate,
            maxReadBytes: maxReadBytes(for: provider),
            maxJSONLLines: maxJSONLLines(for: provider)
        )
        return reader.read()
    }

    private func scanSessionFile(_ fileURL: URL, provider: AgentProvider) -> AgentSessionMeta? {
        var budget = ScanBudget(filesRemaining: 1, bytesRemaining: Self.maxChargedBytesPerFile)
        return scanSessionFile(fileURL, provider: provider, budget: &budget)
    }

    private func scanOpenCodeSessions(roots: [ScanRoot]) -> AgentScanReport {
        var sessionsByKey: [String: AgentSessionMeta] = [:]
        var deniedRoots: [AgentScanDeniedRoot] = []

        for root in roots {
            let rootDenied = AgentScanDeniedRoot(
                provider: .opencode,
                rootPath: root.url.path,
                requiresSecurityScope: root.requiresSecurityScope
            )
            let rootReport: AgentScanReport = withRootAccess(root) { rootURL, accessDenied in
                guard fileManager.fileExists(atPath: rootURL.path) else {
                    return AgentScanReport(sessions: [], deniedRoots: accessDenied ? [rootDenied] : [])
                }
                
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
                    return AgentScanReport(sessions: [], deniedRoots: accessDenied ? [rootDenied] : [])
                }
                
                if !isDirectory.boolValue {
                    return scanOpenCodeFile(rootURL, rootDenied: rootDenied)
                }

                guard let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsPackageDescendants]
                ) else {
                    if !fileManager.isReadableFile(atPath: rootURL.path) {
                        return AgentScanReport(sessions: [], deniedRoots: [rootDenied])
                    }
                    return AgentScanReport(sessions: [], deniedRoots: [])
                }

                return scanOpenCodeDirectory(
                    rootURL: rootURL,
                    enumerator: enumerator,
                    rootDenied: rootDenied,
                    rootRequiresSecurityScope: root.requiresSecurityScope
                )
            }
            
            deniedRoots.append(contentsOf: rootReport.deniedRoots)
            for session in rootReport.sessions {
                sessionsByKey[session.id] = sessionsByKey[session.id].map { merge($0, with: session) } ?? session
            }
        }

        return AgentScanReport(
            sessions: sessionsByKey.values.sorted(by: sortSessions(_:_:)),
            deniedRoots: dedupeDeniedRoots(deniedRoots)
        )
    }

    private func scanOpenCodeFile(_ fileURL: URL, rootDenied: AgentScanDeniedRoot) -> AgentScanReport {
        let extensionName = fileURL.pathExtension.lowercased()
        var report = AgentScanReport(sessions: [], deniedRoots: [])

        if extensionName == "json" || extensionName == "jsonl" || extensionName == "ndjson" {
            if let session = scanSessionFile(fileURL, provider: .opencode) {
                report.sessions.append(session)
            } else if !fileManager.isReadableFile(atPath: fileURL.path) {
                report.deniedRoots.append(rootDenied)
            }
        } else if isSQLiteDatabase(at: fileURL), let sqliteSessions = scanSQLiteSessionFile(fileURL, provider: .opencode) {
            report.sessions.append(contentsOf: sqliteSessions)
        }

        return report
    }

    private func scanOpenCodeDirectory(
        rootURL: URL,
        enumerator: FileManager.DirectoryEnumerator,
        rootDenied: AgentScanDeniedRoot,
        rootRequiresSecurityScope: Bool
    ) -> AgentScanReport {
        var report = AgentScanReport(sessions: [], deniedRoots: [])
        let rootDepth = rootURL.standardizedFileURL.pathComponents.count
        let maxDepth = rootRequiresSecurityScope ? 3 : 2

        for case let fileURL as URL in enumerator {
            let depth = fileURL.standardizedFileURL.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if resourceValues?.isDirectory == true {
                if shouldSkipOpenCodeDirectory(fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard resourceValues?.isRegularFile == true else {
                continue
            }

            let candidateReport = scanOpenCodeFile(fileURL, rootDenied: AgentScanDeniedRoot(
                provider: .opencode,
                rootPath: fileURL.path,
                requiresSecurityScope: rootRequiresSecurityScope
            ))
            report.sessions.append(contentsOf: candidateReport.sessions)
            report.deniedRoots.append(contentsOf: candidateReport.deniedRoots)
        }

        if report.sessions.isEmpty, !fileManager.isReadableFile(atPath: rootURL.path) {
            report.deniedRoots.append(rootDenied)
        }

        return report
    }

    private func shouldSkipOpenCodeDirectory(_ url: URL) -> Bool {
        switch url.lastPathComponent.lowercased() {
        case ".git", "build", "cache", "dist", "logs", "log", "node_modules", "temp", "tmp":
            return true
        default:
            return false
        }
    }

    private func roots(for provider: AgentProvider, homeDirectory: URL) -> [ScanRoot] {
        let requiresSecurityScopeForDefaultRoots = homeDirectory.standardizedFileURL.path != AgentRuntimePaths.sandboxHomeDirectoryURL.standardizedFileURL.path
        let customRootURL = customRootURL(for: provider)?.standardizedFileURL
        let roots = provider.scanRootPaths.map { relativePath in
            let rootURL = homeDirectory.appendingPathComponent(relativePath).standardizedFileURL
            return ScanRoot(
                url: rootURL,
                securityScopeURL: requiresSecurityScopeForDefaultRoots ? rootURL : nil
            )
        }

        var result = roots
        if let customRootURL {
            let customRoots = customScanRoots(for: provider, customRootURL: customRootURL)
            result = customRoots + result
        }
        
        var deduped: [ScanRoot] = []
        var seen = Set<String>()
        for root in result {
            let key = root.url.standardizedFileURL.path
            if seen.contains(key) { continue }
            seen.insert(key)
            deduped.append(root)
        }
        return deduped
    }

    private func customScanRoots(for provider: AgentProvider, customRootURL: URL) -> [ScanRoot] {
        let standardizedRoot = customRootURL.standardizedFileURL

        guard let hiddenDirectory = AgentRuntimePaths.providerHiddenDirectoryName(for: provider)?.lowercased() else {
            return [ScanRoot(url: standardizedRoot, securityScopeURL: standardizedRoot)]
        }

        let rootComponents = standardizedRoot.pathComponents.map { $0.lowercased() }
        if let hiddenIndex = rootComponents.lastIndex(of: hiddenDirectory) {
            let hiddenURL = URL(fileURLWithPath: NSString.path(withComponents: Array(standardizedRoot.pathComponents.prefix(hiddenIndex + 1))), isDirectory: true)
            let selectedWithinProviderDirectory = hiddenIndex < (rootComponents.count - 1)

            if selectedWithinProviderDirectory {
                return [ScanRoot(url: standardizedRoot, securityScopeURL: standardizedRoot)]
            }

            let providerRoots = provider.scanRootPaths.compactMap { relativePath -> ScanRoot? in
                let components = relativePath
                    .split(separator: "/")
                    .map(String.init)
                guard components.first?.lowercased() == hiddenDirectory else {
                    return nil
                }
                let suffixComponents = components.dropFirst()
                let candidateURL = suffixComponents.reduce(hiddenURL) { partial, component in
                    partial.appendingPathComponent(component, isDirectory: false)
                }
                return ScanRoot(url: candidateURL.standardizedFileURL, securityScopeURL: standardizedRoot)
            }
            return providerRoots.isEmpty ? [ScanRoot(url: standardizedRoot, securityScopeURL: standardizedRoot)] : providerRoots
        }

        let providerRoots = provider.scanRootPaths.map { relativePath -> ScanRoot in
            let candidateURL = standardizedRoot.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
            return ScanRoot(url: candidateURL, securityScopeURL: standardizedRoot)
        }
        return providerRoots
    }

    private func customRootURL(for provider: AgentProvider) -> URL? {
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
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        
        if isStale,
           let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
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
        
        return url
    }

    private func withRootAccess<T>(_ root: ScanRoot, _ block: (URL, Bool) -> T) -> T {
        guard let securityScopeURL = root.securityScopeURL else {
            return block(root.url, false)
        }
        let didStart = securityScopeURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                securityScopeURL.stopAccessingSecurityScopedResource()
            }
        }
        return block(root.url, !didStart)
    }

    private func scanSQLiteSessionFile(_ fileURL: URL, provider: AgentProvider) -> [AgentSessionMeta]? {
        #if canImport(SQLite3)
        var db: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        let tableName: String
        if sqliteTableExists("sessions", in: db) {
            tableName = "sessions"
        } else if sqliteTableExists("session", in: db) {
            tableName = "session"
        } else {
            return nil
        }

        let sql = "SELECT * FROM \(tableName)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var sessions: [AgentSessionMeta] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let columnCount = sqlite3_column_count(statement)
            var row: [String: Any] = [:]
            for index in 0..<columnCount {
                guard let rawName = sqlite3_column_name(statement, index) else {
                    continue
                }
                let name = String(cString: rawName)
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT:
                    if let cString = sqlite3_column_text(statement, index) {
                        row[name] = String(cString: UnsafeRawPointer(cString).assumingMemoryBound(to: CChar.self))
                    }
                default:
                    break
                }
            }

            let fallbackDate = fileModificationDate(for: fileURL) ?? Date()
            let draft = SessionDraft(provider: provider, fallbackSessionId: row.stringValue(for: ["id", "session_id"]) ?? fileURL.deletingPathExtension().lastPathComponent, fallbackDate: fallbackDate, sourcePath: fileURL.path)
            if let session = draft.materialize(from: [row]) {
                sessions.append(session)
            }
        }

        return sessions
        #else
        return nil
        #endif
    }

    private func scanCodexThreadSQLite(_ fileURL: URL) -> [AgentSessionMeta]? {
        #if canImport(SQLite3)
        var db: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        guard sqliteTableExists("threads", in: db) else {
            return nil
        }

        let sql = """
        SELECT id, title, cwd, created_at, updated_at, archived
        FROM threads
        WHERE archived = 0
        ORDER BY updated_at DESC
        LIMIT 400
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var sessions: [AgentSessionMeta] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let sessionId = sqliteStringColumn(statement, index: 0)?.trimmedNonEmpty else {
                continue
            }
            let title = sqliteStringColumn(statement, index: 1)?.trimmedNonEmpty ?? "Codex \(sessionId.prefix(8))"
            let projectDir = sqliteStringColumn(statement, index: 2)?.trimmedNonEmpty
            let createdAt = dateFromSQLiteEpoch(sqliteInt64Column(statement, index: 3))
            let updatedAt = dateFromSQLiteEpoch(sqliteInt64Column(statement, index: 4))
            let fallbackDate = fileModificationDate(for: fileURL) ?? Date()
            let resolvedCreatedAt = createdAt ?? updatedAt ?? fallbackDate
            let resolvedUpdatedAt = updatedAt ?? resolvedCreatedAt
            sessions.append(
                AgentSessionMeta(
                    provider: .codex,
                    sessionId: sessionId,
                    title: title,
                    summary: nil,
                    projectDir: projectDir,
                    createdAt: resolvedCreatedAt,
                    lastActiveAt: resolvedUpdatedAt,
                    resumeCommand: AgentProvider.codex.resumeCommand(for: sessionId),
                    sourcePath: fileURL.path,
                    // SQLite threads are persisted history snapshots; do not infer
                    // live execution state from recency alone. Real-time running
                    // state should come from bridge events.
                    state: .idle,
                    usage: nil,
                    pendingActionCount: 0,
                    subagent: nil,
                    childSubagents: []
                )
            )
        }

        return sessions
        #else
        return nil
        #endif
    }

    private func sqliteTableExists(_ tableName: String, in db: OpaquePointer) -> Bool {
        let escapedName = tableName.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(escapedName)' LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func sortSessions(_ lhs: AgentSessionMeta, _ rhs: AgentSessionMeta) -> Bool {
        if lhs.lastActiveAt == rhs.lastActiveAt {
            if lhs.createdAt == rhs.createdAt {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.lastActiveAt > rhs.lastActiveAt
    }

    private func dedupeDeniedRoots(_ deniedRoots: [AgentScanDeniedRoot]) -> [AgentScanDeniedRoot] {
        var seen = Set<String>()
        var result: [AgentScanDeniedRoot] = []
        for root in deniedRoots {
            if seen.insert(root.id).inserted {
                result.append(root)
            }
        }
        return result
    }

    private func merge(_ lhs: AgentSessionMeta, with rhs: AgentSessionMeta) -> AgentSessionMeta {
        var merged = lhs
        merged.title = rhs.title.trimmedNonEmpty ?? merged.title
        if let summary = rhs.summary?.trimmedNonEmpty {
            merged.summary = summary
        }
        if let projectDir = rhs.projectDir?.trimmedNonEmpty {
            merged.projectDir = projectDir
        }
        merged.createdAt = min(lhs.createdAt, rhs.createdAt)
        merged.lastActiveAt = max(lhs.lastActiveAt, rhs.lastActiveAt)
        if rhs.sourcePath.count >= lhs.sourcePath.count {
            merged.sourcePath = rhs.sourcePath
        }
        if rhs.usage != nil {
            merged.usage = rhs.usage
        }
        merged.pendingActionCount = max(lhs.pendingActionCount, rhs.pendingActionCount)
        merged.state = mergeState(
            lhs.state,
            lhsLastActiveAt: lhs.lastActiveAt,
            rhs.state,
            rhsLastActiveAt: rhs.lastActiveAt
        )
        merged.resumeCommand = rhs.resumeCommand.trimmedNonEmpty ?? merged.resumeCommand
        merged.subagent = mergeSubagent(lhs.subagent, with: rhs.subagent)
        merged.childSubagents = mergeSubagentList(lhs.childSubagents, with: rhs.childSubagents)
        return merged
    }

    private func mergeState(
        _ lhs: AgentSessionState,
        lhsLastActiveAt: Date,
        _ rhs: AgentSessionState,
        rhsLastActiveAt: Date
    ) -> AgentSessionState {
        if lhs == rhs {
            return lhs
        }

        let lhsRank = stateRank(lhs)
        let rhsRank = stateRank(rhs)
        if lhsRank != rhsRank {
            if lhsRank >= 2 || rhsRank >= 2 {
                return lhsRank >= rhsRank ? lhs : rhs
            }
            return lhsLastActiveAt >= rhsLastActiveAt ? lhs : rhs
        }

        return lhsLastActiveAt >= rhsLastActiveAt ? lhs : rhs
    }

    private func stateRank(_ state: AgentSessionState) -> Int {
        switch state {
        case .failed: return 5
        case .completed: return 4
        case .waitingQuestion: return 3
        case .waitingApproval: return 2
        case .running: return 1
        case .idle: return 0
        }
    }

    private func mergeSubagentList(_ lhs: [AgentSubagentMeta], with rhs: [AgentSubagentMeta]) -> [AgentSubagentMeta] {
        var merged: [AgentSubagentMeta] = []
        var seen = Set<String>()

        for candidate in lhs + rhs {
            let key = candidate.parentThreadId?.trimmedNonEmpty ?? candidate.id.trimmedNonEmpty ?? candidate.displayName
            if seen.insert(key).inserted {
                merged.append(candidate)
            }
        }

        return merged
    }

    private func mergeSubagent(_ lhs: AgentSubagentMeta?, with rhs: AgentSubagentMeta?) -> AgentSubagentMeta? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (let value?, nil), (nil, let value?):
            return value
        case (let lhs?, let rhs?):
            return AgentSubagentMeta(
                id: rhs.id.trimmedNonEmpty ?? lhs.id,
                name: rhs.name?.trimmedNonEmpty ?? lhs.name,
                role: rhs.role?.trimmedNonEmpty ?? lhs.role,
                type: rhs.type?.trimmedNonEmpty ?? lhs.type,
                parentThreadId: rhs.parentThreadId?.trimmedNonEmpty ?? lhs.parentThreadId
            )
        }
    }

    private func fileModificationDate(for fileURL: URL) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return modificationDate
    }

    private func fileSizeInBytes(for fileURL: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return 0
        }
        return fileSize.int64Value
    }

    private func sqliteStringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: UnsafeRawPointer(value).assumingMemoryBound(to: CChar.self))
    }

    private func sqliteInt64Column(_ statement: OpaquePointer, index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(statement, index)
    }

    private func dateFromSQLiteEpoch(_ rawValue: Int64?) -> Date? {
        guard let rawValue, rawValue > 0 else {
            return nil
        }
        if rawValue >= 1_000_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(rawValue) / 1_000)
        }
        if rawValue >= 1_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(rawValue))
        }
        return nil
    }

    private func activeSessionWindowThreshold() -> TimeInterval {
        if let raw = ProcessInfo.processInfo.environment["BORING_NOTCH_AGENT_ACTIVE_WINDOW_SECONDS"],
           let value = Double(raw),
           value > 0 {
            return value
        }
        return 120
    }

    private func initialBudget(for provider: AgentProvider) -> ScanBudget {
        switch provider {
        case .codex:
            return ScanBudget(filesRemaining: 300, bytesRemaining: 96 * 1024 * 1024)
        case .claude, .gemini, .cursor, .droid, .openclaw:
            return ScanBudget(filesRemaining: 180, bytesRemaining: 48 * 1024 * 1024)
        case .opencode:
            return ScanBudget(filesRemaining: Self.maxFilesPerProvider, bytesRemaining: Self.maxBytesPerProvider)
        }
    }

    private func maxReadBytes(for provider: AgentProvider) -> Int {
        switch provider {
        case .codex:
            return 768 * 1024
        case .claude, .gemini, .cursor, .droid, .openclaw:
            return 384 * 1024
        case .opencode:
            return Self.maxBytesPerFileRead
        }
    }

    private func maxJSONLLines(for provider: AgentProvider) -> Int {
        switch provider {
        case .codex:
            return 600
        case .claude, .gemini, .cursor, .droid, .openclaw:
            return 300
        case .opencode:
            return Self.maxJSONLLinesPerFile
        }
    }

    private func isSQLiteDatabase(at fileURL: URL) -> Bool {
        guard fileURL.isFileURL else { return false }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16) else { return false }
        guard data.count >= 15 else { return false }
        let signature = Data(data.prefix(15))
        return String(data: signature, encoding: .utf8) == "SQLite format 3"
    }
}

private struct SessionFileReader {
    let fileURL: URL
    let provider: AgentProvider
    let fallbackSessionId: String
    let fallbackDate: Date
    let maxReadBytes: Int
    let maxJSONLLines: Int

    func read() -> AgentSessionMeta? {
        guard let data = readBoundedData(), !data.isEmpty else {
            return nil
        }

        let drafts = parseDrafts(from: data)
        guard !drafts.isEmpty else {
            return nil
        }

        if drafts.count == 1, let single = drafts.values.first?.materialize() {
            return single
        }

        let sessions = drafts.values.compactMap { $0.materialize() }
        return sessions.sorted { $0.lastActiveAt > $1.lastActiveAt }.first
    }

    private func parseDrafts(from data: Data) -> [String: SessionDraft] {
        let extensionName = fileURL.pathExtension.lowercased()
        switch extensionName {
        case "jsonl", "ndjson":
            return parseJSONL(from: data)
        case "json":
            return parseJSON(from: data)
        default:
            if let text = String(data: data, encoding: .utf8), text.contains("\n") {
                return parseJSONL(from: data)
            }
            return parseJSON(from: data)
        }
    }

    private func parseJSONL(from data: Data) -> [String: SessionDraft] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var drafts: [String: SessionDraft] = [:]
        let lines = text.split(whereSeparator: \.isNewline)
        for rawLine in lines.suffix(maxJSONLLines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let object = Self.decodeJSONObject(from: trimmed) else {
                continue
            }
            merge(object: object, into: &drafts, depth: 0)
        }
        return drafts
    }

    private func parseJSON(from data: Data) -> [String: SessionDraft] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        var drafts: [String: SessionDraft] = [:]
        if let dictionary = object as? [String: Any] {
            merge(object: dictionary, into: &drafts, depth: 0)
        } else if let array = object as? [Any] {
            for element in array {
                guard let dictionary = element as? [String: Any] else { continue }
                merge(object: dictionary, into: &drafts, depth: 0)
            }
        }
        return drafts
    }

    private func merge(object: [String: Any], into drafts: inout [String: SessionDraft], depth: Int) {
        guard depth < 4 else {
            return
        }
        let nestedObjects = object.nestedDictionaries(for: ["payload", "data", "session", "body", "content"])
        for nested in nestedObjects {
            merge(object: nested, into: &drafts, depth: depth + 1)
        }

        let explicitSessionId = object.strictStringValue(for: ["sessionId", "session_id", "sessionID", "sessionKey", "conversationId", "conversation_id", "threadId", "thread_id", "chatId", "chat_id"])
        let eventType = object.strictStringValue(for: ["event", "type", "kind"])
        let hasSubagentMarkers = object.stringValue(for: [
            "subagentId", "subagent_id", "subagentID",
            "subagentParentThreadId", "subagent_parent_thread_id",
            "subagentName", "subagentNickname", "subagentRole"
        ]) != nil
        let shouldSkipLooseFallbackId = !nestedObjects.isEmpty || eventType != nil || hasSubagentMarkers
        if explicitSessionId == nil, shouldSkipLooseFallbackId {
            return
        }

        let sessionId = explicitSessionId
            ?? object.strictStringValue(for: ["id"])
            ?? fallbackSessionId
        var draft = drafts[sessionId] ?? SessionDraft(
            provider: provider,
            fallbackSessionId: sessionId,
            fallbackDate: fallbackDate,
            sourcePath: fileURL.path
        )
        draft.merge(object: object)
        drafts[sessionId] = draft
    }

    private func readBoundedData() -> Data? {
        let fileExtension = fileURL.pathExtension.lowercased()
        let supportsTailRead = fileExtension == "jsonl" || fileExtension == "ndjson"
        let boundedBytes = max(maxReadBytes, 64 * 1024)

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSizeNumber = attributes[.size] as? NSNumber else {
            return try? Data(contentsOf: fileURL)
        }

        let fileSize = max(0, fileSizeNumber.intValue)
        if fileSize <= boundedBytes {
            return try? Data(contentsOf: fileURL)
        }

        guard supportsTailRead,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        let offset = UInt64(max(0, fileSize - boundedBytes))
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd(), !data.isEmpty else {
            return nil
        }

        if offset > 0,
           let newlineIndex = data.firstIndex(of: 0x0A) {
            let start = data.index(after: newlineIndex)
            data = Data(data[start...])
        }
        return data
    }

    private static func decodeJSONObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }
}

private struct SessionDraft {
    let provider: AgentProvider
    let fallbackSessionId: String
    let fallbackDate: Date
    let sourcePath: String

    private(set) var sessionId: String
    private(set) var title: String?
    private(set) var summary: String?
    private(set) var projectDir: String?
    private(set) var createdAt: Date?
    private(set) var lastActiveAt: Date?
    private(set) var state: AgentSessionState = .idle
    private(set) var usage: AgentUsageSnapshot?
    private(set) var pendingActionCount: Int = 0
    private(set) var pendingRequestIds: Set<String> = []
    private(set) var pendingRequestKindsById: [String: AgentActionKind] = [:]
    private(set) var resolvedRequestIds: Set<String> = []
    private(set) var suppressRunning: Bool = false
    private(set) var resumeCommand: String
    private(set) var subagentId: String?
    private(set) var subagentName: String?
    private(set) var subagentRole: String?
    private(set) var subagentType: String?
    private(set) var subagentParentThreadId: String?
    private(set) var childSubagents: [AgentSubagentMeta] = []

    init(provider: AgentProvider, fallbackSessionId: String, fallbackDate: Date, sourcePath: String) {
        self.provider = provider
        self.fallbackSessionId = fallbackSessionId
        self.fallbackDate = fallbackDate
        self.sourcePath = sourcePath
        sessionId = fallbackSessionId
        resumeCommand = provider.resumeCommand(for: fallbackSessionId)
    }

    mutating func merge(object: [String: Any]) {
        sessionId = object.stringValue(for: [
            "sessionId", "session_id", "sessionID", "id", "sessionKey",
            "conversationId", "conversation_id", "threadId", "thread_id"
        ]) ?? sessionId
        resumeCommand = provider.resumeCommand(for: sessionId)

        if let title = object.stringValue(for: ["title", "sessionTitle", "name", "conversationTitle", "displayName", "thread_name", "threadName", "slug"]) {
            self.title = title
        }
        if let summary = object.stringValue(for: ["summary", "description", "notes", "subtitle", "summaryText", "summary_text"]) {
            self.summary = summary
        }
        if let projectDir = object.stringValue(for: [
            "projectDir", "project_dir", "cwd", "workingDirectory",
            "workspacePath", "rootPath", "path", "directory"
        ]) {
            self.projectDir = projectDir
        }

        if let date = object.dateValue(for: [
            "createdAt", "created_at", "timeCreated", "time_created",
            "startTime", "startedAt", "started_at", "timestamp", "time"
        ]) {
            if let current = createdAt {
                createdAt = min(current, date)
            } else {
                createdAt = date
            }
            if lastActiveAt == nil {
                lastActiveAt = date
            }
        }

        if let date = object.dateValue(for: [
            "updatedAt", "updated_at", "timeUpdated", "time_updated",
            "lastActiveAt", "last_active_at", "timestamp", "time"
        ]) {
            if let current = lastActiveAt {
                lastActiveAt = max(current, date)
            } else {
                lastActiveAt = date
            }
            if createdAt == nil {
                createdAt = date
            }
        }

        if let state = AgentSessionState.from(rawString: object.stringValue(for: ["state", "status", "sessionState", "session_state"])) {
            self.state = prioritize(state, over: self.state)
        }

        if let subagent = makeSubagent(from: object) {
            subagentId = subagent.id
            subagentName = subagent.name
            subagentRole = subagent.role
            subagentType = subagent.type
            subagentParentThreadId = subagent.parentThreadId
        }
        childSubagents = mergeSubagentList(childSubagents, with: extractChildSubagents(from: object))

        let eventTypeRaw = object.stringValue(for: ["event", "type", "kind"])
        if let eventType = eventTypeRaw.flatMap({ AgentBridgeEventType(rawValue: $0) }) {
            switch eventType {
            case .sessionStarted:
                if !suppressRunning {
                    state = prioritize(.running, over: state)
                }
            case .sessionUpdated:
                if !suppressRunning {
                    state = prioritize(.running, over: state)
                }
            case .usageUpdated:
                if !suppressRunning {
                    state = prioritize(.running, over: state)
                }
            case .actionRequested:
                let kind = AgentActionKind.from(rawString: object.stringValue(for: ["actionKind", "action_kind", "requestKind", "kind"]))
                let requestId = stableRequestId(from: object, eventType: eventTypeRaw)
                if !resolvedRequestIds.contains(requestId) {
                    pendingRequestIds.insert(requestId)
                    pendingRequestKindsById[requestId] = kind ?? pendingRequestKindsById[requestId] ?? .approve
                    pendingActionCount = pendingRequestIds.count
                }
                switch kind {
                case .question:
                    state = prioritize(.waitingQuestion, over: state)
                case .approve, .deny:
                    state = prioritize(.waitingApproval, over: state)
                case .none:
                    break
                }
            case .actionResolved:
                let requestId = stableRequestId(from: object, eventType: eventTypeRaw)
                resolvedRequestIds.insert(requestId)
                pendingRequestIds.remove(requestId)
                pendingRequestKindsById.removeValue(forKey: requestId)
                pendingActionCount = pendingRequestIds.count
                if pendingActionCount == 0, state == .waitingApproval || state == .waitingQuestion {
                    state = .idle
                }
                suppressRunning = true
            case .sessionCompleted:
                state = .completed
                suppressRunning = true
            case .sessionFailed:
                state = .failed
                suppressRunning = true
            case .actionResponded:
                let requestId = stableRequestId(from: object, eventType: eventTypeRaw)
                resolvedRequestIds.insert(requestId)
                pendingRequestIds.remove(requestId)
                pendingRequestKindsById.removeValue(forKey: requestId)
                pendingActionCount = pendingRequestIds.count
                if pendingActionCount == 0, state == .waitingApproval || state == .waitingQuestion {
                    state = .idle
                }
            }
        } else if let rawType = object.stringValue(for: ["type", "event", "kind"])?.lowercased(),
                  [
                    "sessionmeta", "session_meta", "eventmsg", "event_msg",
                    "responseitem", "response_item", "assistant", "user",
                    "turncontext", "turn_context"
                  ].contains(rawType),
                  !suppressRunning {
            state = prioritize(.running, over: state)
        }

        let inputTokens = object.intValue(for: ["inputTokens", "input_tokens", "prompt_tokens", "input"])
        let outputTokens = object.intValue(for: ["outputTokens", "output_tokens", "completion_tokens", "output"])
        let totalTokens = object.intValue(for: ["totalTokens", "total_tokens", "total"]) ?? {
            if let inputTokens, let outputTokens {
                return inputTokens + outputTokens
            }
            return inputTokens ?? outputTokens
        }()
        let cost = object.doubleValue(for: ["estimatedCostUSD", "estimated_cost_usd", "cost", "usdCost", "usd_cost"])
        let turnCount = object.intValue(for: ["turnCount", "turn_count", "message_count", "messages", "request_count"])
        if inputTokens != nil || outputTokens != nil || totalTokens != nil || cost != nil || turnCount != nil {
            let updatedAt = object.dateValue(for: ["updatedAt", "updated_at", "timestamp", "time"]) ?? lastActiveAt ?? fallbackDate
            usage = AgentUsageSnapshot(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                totalTokens: totalTokens,
                estimatedCostUSD: cost,
                turnCount: turnCount,
                updatedAt: updatedAt
            )
        }

        let eventType = object.stringValue(for: ["event", "type", "kind"])?.lowercased()
        let canUseMessageAsSummary = eventType == nil || [
            "session.started", "session.updated", "usage.updated",
            "sessionmeta", "session_meta", "eventmsg", "event_msg",
            "responseitem", "response_item"
        ].contains(eventType ?? "")
        if let message = object.stringValue(for: ["prompt", "text", "message", "content"]),
           canUseMessageAsSummary {
            if title == nil,
               eventType == nil || ["session.started", "session.updated", "usage.updated"].contains(eventType ?? "") {
                title = String(message.prefix(80))
            }
            if summary == nil {
                summary = agentShortSummary(from: message, fallback: nil)
            }
        }
    }

    func materialize() -> AgentSessionMeta {
        let resolvedSessionId = sessionId.trimmedNonEmpty ?? fallbackSessionId
        let createdAt = createdAt ?? lastActiveAt ?? fallbackDate
        let lastActiveAt = lastActiveAt ?? createdAt
        let resolvedTitle = title?.trimmedNonEmpty ?? summary?.trimmedNonEmpty ?? "\(provider.displayName) \(resolvedSessionId.prefix(8))"
        let hasPendingActions = pendingActionCount > 0
        let finalState: AgentSessionState
        if state == .completed || state == .failed {
            finalState = state
        } else if hasPendingActions {
            finalState = pendingRequestKindsById.values.contains(.question) ? .waitingQuestion : .waitingApproval
        } else if suppressRunning, state == .running || state == .waitingApproval || state == .waitingQuestion {
            finalState = .idle
        } else if state == .running {
            let isFresh = Date().timeIntervalSince(lastActiveAt) <= activeSessionWindowThreshold()
            finalState = isFresh ? .running : .idle
        } else {
            finalState = state
        }
        return AgentSessionMeta(
            provider: provider,
            sessionId: resolvedSessionId,
            title: resolvedTitle,
            summary: summary?.trimmedNonEmpty,
            projectDir: projectDir?.trimmedNonEmpty,
            createdAt: createdAt,
            lastActiveAt: lastActiveAt,
            resumeCommand: resumeCommand,
            sourcePath: sourcePath,
            state: finalState,
            usage: usage,
            pendingActionCount: pendingActionCount,
            subagent: makeSubagent(from: nil),
            childSubagents: childSubagents
        )
    }

    func materialize(from rows: [[String: Any]]) -> AgentSessionMeta? {
        var merged = self
        for row in rows {
            merged.merge(object: row)
        }
        return merged.materialize()
    }

    private func prioritize(_ lhs: AgentSessionState, over rhs: AgentSessionState) -> AgentSessionState {
        rank(lhs) >= rank(rhs) ? lhs : rhs
    }

    private func rank(_ state: AgentSessionState) -> Int {
        switch state {
        case .failed: return 5
        case .completed: return 4
        case .waitingQuestion: return 3
        case .waitingApproval: return 2
        case .running: return 1
        case .idle: return 0
        }
    }

    private func stableRequestId(from object: [String: Any], eventType: String?) -> String {
        if let explicit = object.strictStringValue(for: [
            "requestId", "request_id", "requestID",
            "actionId", "action_id", "actionID"
        ]) ?? object.stringValue(for: ["id"])?.trimmedNonEmpty {
            return explicit
        }

        guard let eventType,
              let event = AgentBridgeEventType(rawValue: eventType),
              event == .actionRequested || event == .actionResolved || event == .actionResponded else {
            return UUID().uuidString
        }

        let signature = stableRequestSignature(from: object, eventType: eventType)
        return "auto-\(fnv1a64(signature))"
    }

    private func stableRequestSignature(from object: [String: Any], eventType: String) -> String {
        let kind = actionKindSignature(from: object, eventType: eventType)
        let title = object.stringValue(for: ["title", "label", "headline"]) ?? ""
        let message = object.stringValue(for: ["message", "prompt", "content", "text"]) ?? ""
        let details = object.stringValue(for: ["details", "detail", "description", "summary"]) ?? ""
        let options = stableStringArray(from: object, keys: ["options", "choices", "responses", "buttons"])
        let projectDir = object.stringValue(for: ["projectDir", "project_dir", "cwd", "workingDirectory", "workspacePath", "rootPath", "path"]) ?? ""
        let sourcePath = object.stringValue(for: ["sourcePath", "source_path", "logPath", "log_path"]) ?? ""
        let subagentId = object.stringValue(for: ["subagentId", "subagent_id", "subagentID", "id"]) ?? ""
        let parentThreadId = object.stringValue(for: ["subagentParentThreadId", "subagent_parent_thread_id", "parentThreadId", "parent_thread_id"]) ?? ""
        return [
            provider.rawValue,
            sessionId,
            kind,
            title,
            message,
            details,
            options,
            projectDir,
            sourcePath,
            subagentId,
            parentThreadId
        ].joined(separator: "|")
    }

    private func actionKindSignature(from payload: [String: Any], eventType: String) -> String {
        if let explicitKind = AgentActionKind.from(rawString: payload.stringValue(for: ["actionKind", "action_kind", "requestKind", "kind"])) {
            return explicitKind.rawValue
        }

        let normalizedEventType = eventType
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
        if normalizedEventType == "actionrequested" {
            return "action"
        }

        let outcome = payload.stringValue(for: ["outcome", "result", "decision"])?.lowercased()
        switch outcome {
        case "approved", "allow", "allowed", "true":
            return AgentActionKind.approve.rawValue
        case "denied", "deny", "rejected", "reject", "false":
            return AgentActionKind.deny.rawValue
        case "answered", "answer":
            return AgentActionKind.question.rawValue
        default:
            return "action"
        }
    }

    private func stableStringArray(from dictionary: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let strings = dictionary[key] as? [String] {
                let trimmed = strings.compactMap { $0.trimmedNonEmpty }
                if !trimmed.isEmpty {
                    return trimmed.sorted().joined(separator: ",")
                }
            }
            if let strings = dictionary[key] as? [Any] {
                let trimmed = strings.compactMap { element in
                    if let string = element as? String {
                        return string.trimmedNonEmpty
                    }
                    if let value = element as? CustomStringConvertible {
                        return value.description.trimmedNonEmpty
                    }
                    return nil
                }
                if !trimmed.isEmpty {
                    return trimmed.sorted().joined(separator: ",")
                }
            }
            if let string = dictionary[key] as? String {
                let trimmed = string
                    .split(whereSeparator: { $0 == "\n" || $0 == "," })
                    .map { String($0).trimmedNonEmpty }
                    .compactMap { $0 }
                if !trimmed.isEmpty {
                    return trimmed.sorted().joined(separator: ",")
                }
            }
        }
        return ""
    }

    private func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return String(format: "%016llx", hash)
    }

    private func activeSessionWindowThreshold() -> TimeInterval {
        if let raw = ProcessInfo.processInfo.environment["BORING_NOTCH_AGENT_ACTIVE_WINDOW_SECONDS"],
           let value = Double(raw),
           value > 0 {
            return value
        }
        return 120
    }

    private func makeSubagent(from object: [String: Any]?) -> AgentSubagentMeta? {
        let candidateSources: [[String: Any]]
        if let object {
            let nestedSources = object.nestedDictionaries(for: ["subagent", "subagentInfo", "subagent_info", "childAgent", "child_agent", "agent"])
            let explicitSignals = object.strictStringValue(for: [
                "subagentId", "subagent_id", "subagentID",
                "subagentParentThreadId", "subagent_parent_thread_id",
                "subagentName", "subagentNickname", "subagentRole", "subagentType"
            ])
            guard !nestedSources.isEmpty || explicitSignals != nil else {
                return nil
            }
            candidateSources = !nestedSources.isEmpty ? nestedSources : [object]
        } else {
            guard subagentId != nil || subagentName != nil || subagentRole != nil || subagentParentThreadId != nil else {
                return nil
            }
            return AgentSubagentMeta(
                id: subagentId ?? subagentParentThreadId ?? fallbackSessionId,
                name: subagentName,
                role: subagentRole,
                type: subagentType,
                parentThreadId: subagentParentThreadId
            )
        }

        for source in candidateSources {
            let id = source.strictStringValue(for: ["subagentId", "subagent_id", "subagentID", "id"])
            let name = source.strictStringValue(for: ["subagentName", "subagent_name", "subagentNickname", "subagent_nickname", "nickname", "name", "title"])
            let role = source.strictStringValue(for: ["subagentRole", "subagent_role", "role"])
            let type = source.strictStringValue(for: ["subagentType", "subagent_type", "type"])
            let parentThreadId = source.strictStringValue(for: ["subagentParentThreadId", "subagent_parent_thread_id", "parentThreadId", "parent_thread_id"])

            guard id != nil || name != nil || role != nil || parentThreadId != nil else {
                continue
            }

            return AgentSubagentMeta(
                id: id ?? parentThreadId ?? fallbackSessionId,
                name: name,
                role: role,
                type: type,
                parentThreadId: parentThreadId
            )
        }

        return nil
    }

    private func extractChildSubagents(from object: [String: Any]?) -> [AgentSubagentMeta] {
        guard let object else { return [] }
        let sources = object.nestedDictionaries(for: [
            "subagentSessions", "subagent_sessions",
            "childSubagents", "child_subagents",
            "subagents"
        ])
        return sources.compactMap { source in
            let id = source.strictStringValue(for: ["subagentId", "subagent_id", "subagentID", "id"])
            let name = source.strictStringValue(for: ["subagentName", "subagent_name", "subagentNickname", "subagent_nickname", "nickname", "name", "title"])
            let role = source.strictStringValue(for: ["subagentRole", "subagent_role", "role"])
            let type = source.strictStringValue(for: ["subagentType", "subagent_type", "type"])
            let parentThreadId = source.strictStringValue(for: ["subagentParentThreadId", "subagent_parent_thread_id", "parentThreadId", "parent_thread_id"])
            guard id != nil || name != nil || role != nil || parentThreadId != nil else {
                return nil
            }
            return AgentSubagentMeta(
                id: id ?? parentThreadId ?? fallbackSessionId,
                name: name,
                role: role,
                type: type,
                parentThreadId: parentThreadId
            )
        }
    }

    private func mergeSubagentList(_ lhs: [AgentSubagentMeta], with rhs: [AgentSubagentMeta]) -> [AgentSubagentMeta] {
        var merged: [AgentSubagentMeta] = []
        var seen = Set<String>()

        for candidate in lhs + rhs {
            let key = candidate.parentThreadId?.trimmedNonEmpty ?? candidate.id.trimmedNonEmpty ?? candidate.displayName
            if seen.insert(key).inserted {
                merged.append(candidate)
            }
        }

        return merged
    }
}

private extension AgentSessionState {
    static func from(rawString: String?) -> AgentSessionState? {
        guard let rawString = rawString?.trimmedNonEmpty else { return nil }
        let normalized = rawString
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
        switch normalized {
        case "running", "active", "inprogress":
            return .running
        case "waitingapproval", "needsapproval", "approvalpending", "blocked", "paused":
            return .waitingApproval
        case "waitingquestion", "questionpending", "needsinput":
            return .waitingQuestion
        case "completed", "done", "finished", "success":
            return .completed
        case "failed", "error":
            return .failed
        case "idle":
            return .idle
        default:
            return nil
        }
    }
}

extension AgentActionKind {
    static func from(rawString: String?) -> AgentActionKind? {
        guard let rawString = rawString?.trimmedNonEmpty else { return nil }
        let normalized = rawString.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "").lowercased()
        switch normalized {
        case "approve", "approval":
            return .approve
        case "deny", "decline", "reject":
            return .deny
        case "question", "ask", "answer", "text":
            return .question
        default:
            return nil
        }
    }
}
