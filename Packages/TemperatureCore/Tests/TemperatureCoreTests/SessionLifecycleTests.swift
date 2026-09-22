import Foundation
import Testing
@testable import TemperatureCore

@Suite struct SessionLifecycleTests {
    @Test func secondLockHolderFailsWhileFirstHeld() throws {
        let root = try makeLifecycleRoot()
        let paths = SessionPaths(bundleID: testBundleID, baseDirectory: root)
        let first = try SessionLock.acquire(at: paths.lockURL)
        defer { first.release() }

        do {
            _ = try SessionLock.acquire(at: paths.lockURL)
            Issue.record("expected second lock acquisition to fail")
        } catch SessionLockError.alreadyHeld {
            #expect(Bool(true))
        }
    }

    @Test func lockReleaseAllowsNewHolder() throws {
        let root = try makeLifecycleRoot()
        let paths = SessionPaths(bundleID: testBundleID, baseDirectory: root)
        let first = try SessionLock.acquire(at: paths.lockURL)
        first.release()

        let second = try SessionLock.acquire(at: paths.lockURL)
        defer { second.release() }
        #expect(second.isHeld)
    }

    @Test func cleanupRequiresHeldLock() throws {
        let root = try makeLifecycleRoot()
        let paths = SessionPaths(bundleID: testBundleID, baseDirectory: root)
        let cleanup = try makeCleanup()
        let sessionID = try SessionID(validating: "00000000-0000-4000-8000-000000000601")
        try writeMarkedSession(paths: paths, sessionID: sessionID)

        do {
            _ = try cleanup.cleanupOrphanedSessions(
                paths: paths,
                excludingSessionID: nil
            )
            Issue.record("expected cleanup without lock to fail")
        } catch SessionCleanupError.lockNotHeld {
            #expect(Bool(true))
        }

        #expect(FileManager.default.fileExists(atPath: paths.sessionDirectory(sessionID: sessionID).path))
    }

    @Test func cleanupRemovesOrphanedMarkedSession() throws {
        let root = try makeLifecycleRoot()
        let paths = SessionPaths(bundleID: testBundleID, baseDirectory: root)
        let cleanup = try makeCleanup()
        let sessionID = try SessionID(validating: "00000000-0000-4000-8000-000000000602")
        try writeMarkedSession(paths: paths, sessionID: sessionID)

        let lock = try SessionLock.acquire(at: paths.lockURL)
        defer { lock.release() }

        let sessionDirectory = paths.sessionDirectory(sessionID: sessionID)
        let removed = try cleanup.cleanupOrphanedSessions(
            paths: paths,
            excludingSessionID: nil
        )
        #expect(removed.map(\.lastPathComponent).contains(sessionID.rawValue))
        #expect(FileManager.default.fileExists(atPath: sessionDirectory.path) == false)
    }

    @Test func cleanupSkipsDirectoryWithoutMarker() throws {
        let root = try makeLifecycleRoot()
        let paths = SessionPaths(bundleID: testBundleID, baseDirectory: root)
        let cleanup = try makeCleanup()
        let sessionID = try SessionID(validating: "00000000-0000-4000-8000-000000000603")
        let sessionDirectory = paths.sessionDirectory(sessionID: sessionID)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        try Data("sqlite".utf8).write(to: paths.databaseURL(sessionID: sessionID))

        let lock = try SessionLock.acquire(at: paths.lockURL)
        defer { lock.release() }

        let removed = try cleanup.cleanupOrphanedSessions(
            paths: paths,
            excludingSessionID: nil
        )
        #expect(removed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sessionDirectory.path))
    }

    @Test func cleanupSkipsDirectoryWithMismatchedMarker() throws {
        let root = try makeLifecycleRoot()
        let paths = SessionPaths(bundleID: testBundleID, baseDirectory: root)
        let cleanup = try makeCleanup()
        let sessionID = try SessionID(validating: "00000000-0000-4000-8000-000000000604")
        let sessionDirectory = paths.sessionDirectory(sessionID: sessionID)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let marker = SessionMarker(
            bundleID: "other.bundle.id",
            sessionID: sessionID.rawValue,
            schemaVersion: SessionCleanup.expectedSchemaVersion
        )
        try writeMarker(marker, in: sessionDirectory)

        let lock = try SessionLock.acquire(at: paths.lockURL)
        defer { lock.release() }

        let removed = try cleanup.cleanupOrphanedSessions(
            paths: paths,
            excludingSessionID: nil
        )
        #expect(removed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sessionDirectory.path))
    }

    @Test func cleanupRejectsSymlinkedSessionDirectory() throws {
        let root = try makeLifecycleRoot()
        let paths = SessionPaths(bundleID: testBundleID, baseDirectory: root)
        let cleanup = try makeCleanup()
        let sessionID = try SessionID(validating: "00000000-0000-4000-8000-000000000605")
        let realDirectory = paths.sessionDirectory(sessionID: sessionID)
        try writeMarkedSession(paths: paths, sessionID: sessionID)
        let linkDirectory = paths.sessionsRoot.appendingPathComponent("linked-session", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkDirectory, withDestinationURL: realDirectory)

        let lock = try SessionLock.acquire(at: paths.lockURL)
        defer { lock.release() }

        let removed = try cleanup.cleanupOrphanedSessions(
            paths: paths,
            excludingSessionID: nil
        )
        #expect(removed.map(\.lastPathComponent).contains(sessionID.rawValue))
        #expect(FileManager.default.fileExists(atPath: realDirectory.path) == false)
        #expect(removed.map(\.lastPathComponent).contains("linked-session") == false)
        let remaining = try FileManager.default.contentsOfDirectory(
            at: paths.sessionsRoot,
            includingPropertiesForKeys: nil
        )
        #expect(remaining.map(\.lastPathComponent).contains("linked-session"))
        try? FileManager.default.removeItem(at: linkDirectory)
    }

    @Test func cleanupRejectsPathOutsideSessionsRoot() throws {
        let root = try makeLifecycleRoot()
        let paths = SessionPaths(bundleID: testBundleID, baseDirectory: root)
        let cleanup = try makeCleanup()
        let outside = root.appendingPathComponent("outside.sqlite")
        let lock = try SessionLock.acquire(at: paths.lockURL)
        defer { lock.release() }

        do {
            try cleanup.deleteSessionDirectory(
                at: outside,
                sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000606"),
                paths: paths
            )
            Issue.record("expected outside path deletion to fail")
        } catch SessionCleanupError.pathOutsideSessionsRoot {
            #expect(Bool(true))
        }
    }

    @Test func cleanupPreservesExcludedActiveSession() throws {
        let root = try makeLifecycleRoot()
        let paths = SessionPaths(bundleID: testBundleID, baseDirectory: root)
        let cleanup = try makeCleanup()
        let activeID = try SessionID(validating: "00000000-0000-4000-8000-000000000607")
        let orphanID = try SessionID(validating: "00000000-0000-4000-8000-000000000608")
        try writeMarkedSession(paths: paths, sessionID: activeID)
        try writeMarkedSession(paths: paths, sessionID: orphanID)

        let lock = try SessionLock.acquire(at: paths.lockURL)
        defer { lock.release() }

        let orphanDirectory = paths.sessionDirectory(sessionID: orphanID)
        let removed = try cleanup.cleanupOrphanedSessions(
            paths: paths,
            excludingSessionID: activeID
        )
        #expect(removed.map(\.lastPathComponent).contains(orphanID.rawValue))
        #expect(FileManager.default.fileExists(atPath: paths.sessionDirectory(sessionID: activeID).path))
        #expect(FileManager.default.fileExists(atPath: orphanDirectory.path) == false)
    }

    @Test func corruptedActiveDatabaseIsNotAutoDeleted() throws {
        let root = try makeLifecycleRoot()
        let paths = SessionPaths(bundleID: testBundleID, baseDirectory: root)
        let cleanup = try makeCleanup()
        let sessionID = try SessionID(validating: "00000000-0000-4000-8000-000000000609")
        try writeMarkedSession(paths: paths, sessionID: sessionID)
        try Data("not-a-database".utf8).write(to: paths.databaseURL(sessionID: sessionID))

        do {
            try cleanup.validateSessionDatabase(at: paths.databaseURL(sessionID: sessionID))
            Issue.record("expected corrupted database validation to fail")
        } catch SessionCleanupError.databaseCorrupt {
            #expect(Bool(true))
        }

        #expect(FileManager.default.fileExists(atPath: paths.databaseURL(sessionID: sessionID).path))
    }
}

private let testBundleID = "io.github.sisyphe550.TemperatureMonitor"

private func makeLifecycleRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SessionLifecycleTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeCleanup() throws -> SessionCleanup {
    SessionCleanup(
        bundleID: testBundleID,
        schemaVersion: SessionCleanup.expectedSchemaVersion
    )
}

private func writeMarkedSession(paths: SessionPaths, sessionID: SessionID) throws {
    let cleanup = try makeCleanup()
    let sessionDirectory = paths.sessionDirectory(sessionID: sessionID)
    try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
    try cleanup.writeMarker(for: sessionID, in: sessionDirectory)
    try Data("sqlite-placeholder".utf8).write(to: paths.databaseURL(sessionID: sessionID))
}

private func writeMarker(_ marker: SessionMarker, in directory: URL) throws {
    let url = directory.appendingPathComponent(SessionMarker.fileName)
    let data = try JSONEncoder().encode(marker)
    try data.write(to: url, options: .atomic)
}

