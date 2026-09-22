import Foundation
import Testing
@testable import SensorRuntime
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

    @Test func stopIsIdempotent() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
        ])
        await fixture.controller.stop()
        await fixture.controller.stop()
        #expect(await fixture.controller.isStopped)
        try await fixture.closeAndDeleteSession()
    }

    @Test func stopDuringReadDoesNotAcceptLateResponse() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
        ])
        await fixture.controller.stop()
        await fixture.client.respond(allMembersCelsius: 88)
        fixture.clock.advance(to: Fixtures.timestamp(ms: 500))
        #expect(await fixture.client.readCount == 1)
        #expect(try await fixture.session.rows(in: "raw_samples") == 0)
        try await fixture.closeAndDeleteSession()
    }

    @Test func fatalDisplayReceiptExpiresAfterConfiguredDuration() throws {
        let configuration = try Configuration.bundledDefaults()
        let visibleAt = Timestamp(elapsedNS: 1_000_000_000, wallUnixNS: 1_700_000_000_000_000_000)
        let receipt = FatalDisplayReceipt(
            failure: MonitorFailure(
                code: .sensorRead,
                severity: .fatal,
                component: "test",
                operation: "read",
                retryCount: 0,
                sourceID: nil,
                underlyingCode: nil
            ),
            visibleAt: visibleAt,
            configuration: configuration,
            reportPath: nil
        )
        let beforeDeadline = Timestamp(
            elapsedNS: visibleAt.elapsedNS + Int64(configuration.fatalDisplayMS - 1) * 1_000_000,
            wallUnixNS: visibleAt.wallUnixNS
        )
        let atDeadline = Timestamp(
            elapsedNS: visibleAt.elapsedNS + Int64(configuration.fatalDisplayMS) * 1_000_000,
            wallUnixNS: visibleAt.wallUnixNS
        )
        #expect(receipt.hasExpired(at: beforeDeadline) == false)
        #expect(receipt.hasExpired(at: atDeadline))
        #expect(receipt.remainingMS(at: beforeDeadline) == 1)
    }

    @Test func shutdownRecordsCompletedSteps() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
        ])
        await fixture.controller.stop()
        let outcome = await fixture.controller.lastShutdownOutcome()
        let steps = try #require(outcome?.stepResults.map(\.name))
        #expect(steps.contains("stop_snapshot_loop"))
        #expect(steps.contains("stop_coordinator"))
        #expect(steps.contains("close_client"))
        #expect(outcome?.incompleteSteps.isEmpty == true)
        try await fixture.closeAndDeleteSession()
    }

    @Test func sleepWakeOpensAndClosesSleepGap() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 210, event: .respond(allMembersCelsius: 70)),
        ])
        try await fixture.controller.suspendForSleep()
        #expect(try await fixture.session.rows(in: "gaps") >= 1)
        fixture.clock.advance(to: Fixtures.timestamp(ms: 5_000))
        try await fixture.controller.resumeAfterWake()
        #expect(try await fixture.session.rows(in: "segments") >= 2)
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
    }

    @Test func sleepAcrossRetentionPrunesWithoutCreatingBuckets() async throws {
        let fixture = try await ControllerFixture.make()
        try await fixture.run([
            TimedControllerEvent(atMS: 0, event: .start(cpuPeriodMS: 200)),
            TimedControllerEvent(atMS: 200, event: .expectRead(kind: .cpu)),
            TimedControllerEvent(atMS: 210, event: .respond(allMembersCelsius: 70)),
        ])
        try await fixture.controller.suspendForSleep()
        let configuration = try Configuration.bundledDefaults()
        let jumpNS = (configuration.retentionSeconds.raw + 50) * 1_000_000_000
        fixture.clock.advance(
            to: Timestamp(
                elapsedNS: jumpNS,
                wallUnixNS: Fixtures.timestamp(ms: 0).wallUnixNS + jumpNS
            )
        )
        try await fixture.controller.resumeAfterWake()
        #expect(try await fixture.session.rows(in: "aggregates") == 0)
        await fixture.controller.stop()
        try await fixture.closeAndDeleteSession()
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

