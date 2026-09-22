import Foundation
import Testing
@testable import TemperatureCore

@Suite struct SQLiteStoreTests {
    @Test func bundledSchemaSetsUserVersionForeignKeysAndViews() throws {
        let url = try makeTemporaryDatabaseURL()
        defer { try? removeDatabaseFiles(at: url) }

        let store = try SQLiteStore(databaseURL: url)
        defer { store.close() }

        try store.applyBundledSchemaIfNeeded()
        try store.quickCheck()

        #expect(try store.userVersion() == SQLiteStore.expectedUserVersion)
        #expect(try store.foreignKeysEnabled())
        for view in SQLiteStore.requiredViews {
            #expect(try store.viewExists(view))
        }
    }

    @Test func sessionMetadataRoundTripThroughStore() throws {
        let url = try makeTemporaryDatabaseURL()
        defer { try? removeDatabaseFiles(at: url) }

        let store = try SQLiteStore(databaseURL: url)
        defer { store.close() }

        try store.applyBundledSchemaIfNeeded()
        let metadata = try sampleSessionMetadata()
        try store.insertSession(metadata)

        let loaded = try store.sessionRow(for: metadata.sessionID)
        #expect(loaded == metadata)
    }

    @Test func sessionPersistenceOpenPersistsMetadata() async throws {
        let url = try makeTemporaryDatabaseURL()
        defer { try? removeDatabaseFiles(at: url) }

        let metadata = try sampleSessionMetadata()
        let persistence = SessionPersistenceActor(databaseURL: url)
        try await persistence.open(metadata)

        let loaded = await persistence.openedSessionMetadata
        #expect(loaded == metadata)

        try await persistence.closeAndDeleteSession()
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test func badUserVersionFailsWithSchemaFatal() async throws {
        let url = try makeTemporaryDatabaseURL()
        defer { try? removeDatabaseFiles(at: url) }

        let store = try SQLiteStore(databaseURL: url)
        defer { store.close() }
        try store.applyBundledSchemaIfNeeded()
        try store.execSQL("PRAGMA user_version = 99")

        let persistence = SessionPersistenceActor(databaseURL: url)
        do {
            try await persistence.open(try sampleSessionMetadata())
            Issue.record("expected schema failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseSchema)
            #expect(failure.severity == .fatal)
        }
    }

    @Test func missingRequiredViewFailsWithSchemaFatal() async throws {
        let url = try makeTemporaryDatabaseURL()
        defer { try? removeDatabaseFiles(at: url) }

        let store = try SQLiteStore(databaseURL: url)
        defer { store.close() }
        try store.applyBundledSchemaIfNeeded()
        try store.execSQL("DROP VIEW samples_1s")

        let persistence = SessionPersistenceActor(databaseURL: url)
        do {
            try await persistence.open(try sampleSessionMetadata())
            Issue.record("expected schema failure")
        } catch let failure as MonitorFailure {
            #expect(failure.code == .databaseSchema)
        }
    }

    @Test func callerCannotAccessRawSQLiteConnection() {
        let persistence = SessionPersistenceActor(databaseURL: URL(fileURLWithPath: "/tmp/unused.sqlite"))
        #expect(Mirror(reflecting: persistence).children.contains(where: { $0.label == "handle" }) == false)
    }
}

private func sampleSessionMetadata() throws -> SessionMetadata {
    SessionMetadata(
        sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000099"),
        startedWallUnixNS: 1_700_000_000_000_000_000,
        model: "Mac16,13",
        osBuild: "24G419",
        appVersion: "0.1.0"
    )
}

private func makeTemporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SQLiteStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("session.sqlite")
}

private func removeDatabaseFiles(at databaseURL: URL) throws {
    let fm = FileManager.default
    let paths = [
        databaseURL,
        URL(fileURLWithPath: databaseURL.path + "-wal"),
        URL(fileURLWithPath: databaseURL.path + "-shm"),
    ]
    for url in paths where fm.fileExists(atPath: url.path) {
        try fm.removeItem(at: url)
    }
}
