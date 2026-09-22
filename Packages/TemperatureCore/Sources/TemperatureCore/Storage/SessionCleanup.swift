import Darwin
import Foundation

public struct SessionMarker: Codable, Sendable, Equatable {
    public static let fileName = "session.marker.json"

    public let bundleID: String
    public let sessionID: String
    public let schemaVersion: Int

    public init(bundleID: String, sessionID: String, schemaVersion: Int) {
        self.bundleID = bundleID
        self.sessionID = sessionID
        self.schemaVersion = schemaVersion
    }
}

public struct SessionPaths: Sendable, Equatable {
    public static let databaseFileName = "monitor.sqlite"
    public static let lockFileName = "instance.lock"
    public static let sessionsDirectoryName = "Sessions"

    public let bundleID: String
    public let appSupportRoot: URL
    public let lockURL: URL
    public let sessionsRoot: URL

    public init(bundleID: String, baseDirectory: URL) {
        self.bundleID = bundleID
        appSupportRoot = baseDirectory.appendingPathComponent(bundleID, isDirectory: true)
        lockURL = appSupportRoot.appendingPathComponent(Self.lockFileName)
        sessionsRoot = appSupportRoot.appendingPathComponent(Self.sessionsDirectoryName, isDirectory: true)
    }

    public func sessionDirectory(sessionID: SessionID) -> URL {
        sessionsRoot.appendingPathComponent(sessionID.rawValue, isDirectory: true)
    }

    public func databaseURL(sessionID: SessionID) -> URL {
        sessionDirectory(sessionID: sessionID).appendingPathComponent(Self.databaseFileName)
    }
}

public enum SessionCleanupError: Error, Sendable, Equatable {
    case lockNotHeld
    case pathOutsideSessionsRoot
    case symlinkComponent
    case invalidMarker
    case markerMismatch
    case unreadableMarker
    case databaseCorrupt(String)
    case databaseSchemaMismatch(String)
    case deleteFailed(String)
}

public struct SessionCleanup: Sendable {
    public static let expectedSchemaVersion = SQLiteStore.expectedUserVersion

    public let bundleID: String
    public let schemaVersion: Int

    public init(bundleID: String, schemaVersion: Int = SessionCleanup.expectedSchemaVersion) {
        self.bundleID = bundleID
        self.schemaVersion = schemaVersion
    }

    public func writeMarker(for sessionID: SessionID, in sessionDirectory: URL) throws {
        let marker = SessionMarker(
            bundleID: bundleID,
            sessionID: sessionID.rawValue,
            schemaVersion: schemaVersion
        )
        let url = sessionDirectory.appendingPathComponent(SessionMarker.fileName)
        let data = try JSONEncoder().encode(marker)
        try data.write(to: url, options: .atomic)
    }

    public func cleanupOrphanedSessions(
        paths: SessionPaths,
        excludingSessionID: SessionID?
    ) throws -> [URL] {
        try verifyLockHeld(at: paths.lockURL)
        try ensureDirectoryExists(paths.sessionsRoot)

        let entries = try FileManager.default.contentsOfDirectory(
            at: paths.sessionsRoot,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var removed: [URL] = []
        for entry in entries {
            if entryHasSymlinkComponent(entry, stoppingAt: paths.sessionsRoot) {
                continue
            }
            guard let sessionID = try validatedSessionID(forDirectory: entry) else {
                continue
            }
            if sessionID == excludingSessionID?.rawValue {
                continue
            }
            guard try isRemovableMarkedSession(
                at: entry,
                expectedSessionID: sessionID,
                sessionsRoot: paths.sessionsRoot
            ) else {
                continue
            }
            try deleteDirectoryIfInsideSessionsRoot(entry, sessionsRoot: paths.sessionsRoot)
            removed.append(entry)
        }
        return removed
    }

    public func deleteSessionDirectory(
        at directoryURL: URL,
        sessionID: SessionID,
        paths: SessionPaths
    ) throws {
        try verifyLockHeld(at: paths.lockURL)
        try ensureInsideSessionsRoot(directoryURL, sessionsRoot: paths.sessionsRoot)
        guard try isRemovableMarkedSession(
            at: directoryURL,
            expectedSessionID: sessionID.rawValue,
            sessionsRoot: paths.sessionsRoot
        ) else {
            throw SessionCleanupError.invalidMarker
        }
        try deleteDirectoryIfInsideSessionsRoot(directoryURL, sessionsRoot: paths.sessionsRoot)
    }

    public func validateSessionDatabase(at databaseURL: URL) throws {
        do {
            let store = try SQLiteStore(databaseURL: databaseURL)
            defer { store.close() }
            try store.quickCheck()
            let version = try store.userVersion()
            guard version == schemaVersion else {
                throw SessionCleanupError.databaseSchemaMismatch(
                    "expected schema version \(schemaVersion), got \(version)"
                )
            }
        } catch let error as SessionCleanupError {
            throw error
        } catch let error as SQLiteStoreError {
            throw mapStoreError(error)
        } catch {
            throw SessionCleanupError.databaseCorrupt(String(describing: error))
        }
    }

    private func isRemovableMarkedSession(
        at directoryURL: URL,
        expectedSessionID: String,
        sessionsRoot: URL? = nil
    ) throws -> Bool {
        if entryHasSymlinkComponent(directoryURL, stoppingAt: sessionsRoot) {
            return false
        }

        let markerURL = directoryURL.appendingPathComponent(SessionMarker.fileName)
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return false
        }
        if entryHasSymlinkComponent(markerURL, stoppingAt: sessionsRoot) {
            return false
        }

        let data: Data
        do {
            data = try Data(contentsOf: markerURL)
        } catch {
            throw SessionCleanupError.unreadableMarker
        }

        let marker: SessionMarker
        do {
            marker = try JSONDecoder().decode(SessionMarker.self, from: data)
        } catch {
            return false
        }

        guard marker.bundleID == bundleID else {
            return false
        }
        guard marker.schemaVersion == schemaVersion else {
            return false
        }
        guard marker.sessionID == expectedSessionID else {
            throw SessionCleanupError.markerMismatch
        }
        return true
    }

    private func validatedSessionID(forDirectory directoryURL: URL) throws -> String? {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let name = directoryURL.lastPathComponent
        do {
            let sessionID = try SessionID(validating: name)
            return sessionID.rawValue
        } catch {
            return nil
        }
    }

    private func verifyLockHeld(at lockURL: URL) throws {
        let parent = lockURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let path = lockURL.path
        let fd = path.withCString { cPath in
            open(cPath, O_RDWR, 0)
        }
        guard fd >= 0 else {
            throw SessionCleanupError.lockNotHeld
        }
        defer { close(fd) }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            _ = flock(fd, LOCK_UN)
            throw SessionCleanupError.lockNotHeld
        }
        guard errno == EWOULDBLOCK else {
            throw SessionCleanupError.lockNotHeld
        }
    }

    private func ensureInsideSessionsRoot(_ url: URL, sessionsRoot: URL) throws {
        let normalized = url.standardizedFileURL
        let root = sessionsRoot.standardizedFileURL
        guard normalized.path == root.path || normalized.path.hasPrefix(root.path + "/") else {
            throw SessionCleanupError.pathOutsideSessionsRoot
        }
        if entryHasSymlinkComponent(normalized, stoppingAt: sessionsRoot) {
            throw SessionCleanupError.symlinkComponent
        }
    }

    private func deleteDirectoryIfInsideSessionsRoot(_ url: URL, sessionsRoot: URL) throws {
        try ensureInsideSessionsRoot(url, sessionsRoot: sessionsRoot)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw SessionCleanupError.deleteFailed(error.localizedDescription)
        }
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func entryHasSymlinkComponent(_ url: URL, stoppingAt root: URL? = nil) -> Bool {
        var current = url.standardizedFileURL
        let stopPath = root?.standardizedFileURL.path
        while current.path != "/" {
            if let stopPath, current.path == stopPath {
                break
            }
            if isSymlink(current) {
                return true
            }
            current.deleteLastPathComponent()
        }
        return false
    }

    private func isSymlink(_ url: URL) -> Bool {
        let path = url.path
        var statInfo = stat()
        guard lstat(path, &statInfo) == 0 else {
            return false
        }
        return (statInfo.st_mode & S_IFMT) == S_IFLNK
    }

    private func mapStoreError(_ error: SQLiteStoreError) -> SessionCleanupError {
        switch error {
        case let .quickCheckFailed(result):
            .databaseCorrupt(result)
        case let .schemaMismatch(detail):
            .databaseSchemaMismatch(detail)
        case let .openFailed(_, message):
            .databaseCorrupt(message)
        case let .execFailed(_, message):
            .databaseCorrupt(message)
        case let .prepareFailed(_, message):
            .databaseCorrupt(message)
        case let .stepFailed(_, message):
            .databaseCorrupt(message)
        case .integrityConflict(let detail):
            .databaseCorrupt(detail)
        case .closed:
            .databaseCorrupt("database closed")
        }
    }
}
