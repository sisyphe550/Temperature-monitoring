import Foundation
@testable import TemperatureCore

struct TemporaryStoreFixture {
    let session: SessionPersistenceActor
    let databaseURL: URL

    static func make(retentionPolicy: RetentionPolicy? = nil) async throws -> TemporaryStoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemporaryStoreFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("session.sqlite")
        let session: SessionPersistenceActor
        if let retentionPolicy {
            session = SessionPersistenceActor(databaseURL: databaseURL, retentionPolicy: retentionPolicy)
        } else {
            session = SessionPersistenceActor(databaseURL: databaseURL)
        }
        try await session.open(try testSessionMetadata())
        return TemporaryStoreFixture(session: session, databaseURL: databaseURL)
    }

    func appendForTesting(_ batch: PersistenceBatch) async throws -> ProcessingReceipt {
        try await session.appendForTesting(batch)
    }

    func rows(in table: String) async throws -> Int {
        try await session.rows(in: table)
    }

    func closeAndDeleteSession() async throws {
        try await session.closeAndDeleteSession()
    }

    private static func testSessionMetadata() throws -> SessionMetadata {
        SessionMetadata(
            sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000301"),
            startedWallUnixNS: 1_700_000_000_000_000_000,
            model: "Mac16,13",
            osBuild: "24G419",
            appVersion: "0.1.0-test"
        )
    }
}
