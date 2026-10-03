import CSQLite
import Foundation
import Testing
@testable import TemperatureCore

// Counts SQLite VM work, not machine-dependent wall time. The SQL comes from
// the real production methods; no copied predicate can let this pass by itself.
@Suite(.serialized) struct RetentionLookupScalingTests {
    @Test(arguments: ["raw_samples", "ema_samples"])
    func parentLookupWorkDoesNotScaleWithEarlierWindows(table: String) throws {
        let sql = try productionDeleteSQL(table: table)
        let small = try measureDelete(sql: sql, table: table, parentCount: 32)
        let large = try measureDelete(sql: sql, table: table, parentCount: 2_048)
        print("RETENTION_VM_SCALE table=\(table) small_steps=\(small.steps) large_steps=\(large.steps) deleted=\(large.deleted)")
        #expect(small.deleted == 20)
        #expect(large.deleted == 20)
        // The expired rows and foreign-key work are fixed. More earlier windows
        // must not cause each parent lookup to scan that growing prefix.
        #expect(large.steps <= small.steps * 2)
    }

    @Test func midSecondRecoveryProducesAlignedPartialParentAndStoreKeepsSegmentsSeparate() throws {
        let fixture = try LookupFixture()
        defer { fixture.cleanup() }
        let seriesID = SeriesID(Fixtures.uuid(101))
        let old = Sample(sampleID: "before-recovery", seriesID: seriesID, segment: 1,
            timestamp: Fixtures.timestamp(ms: 250), periodMS: 50, valueC: 50,
            freshness: .unknown, sourceWallUnixNS: nil, memberSampleIDs: [])
        let recovered = Sample(sampleID: "after-recovery", seriesID: seriesID, segment: 2,
            timestamp: Fixtures.timestamp(ms: 750), periodMS: 50, valueC: 50,
            freshness: .unknown, sourceWallUnixNS: nil, memberSampleIDs: [])
        var aggregation = AggregationEngine()
        aggregation.ingest(old)
        aggregation.ingest(recovered)
        let windows = aggregation.advance(to: 1_000_000_000)
        let parent = try #require(windows.first { $0.segment == 2 && $0.widthSeconds == 1 })
        #expect(parent.startElapsedNS == 0)
        #expect(parent.endElapsedNS == 1_000_000_000)
        #expect(parent.isPartial)
        #expect(parent.latestElapsedNS == 750_000_000)
        try fixture.insertSample(id: old.sampleID, segment: 1, elapsed: old.timestamp.elapsedNS)
        try fixture.insertSample(id: recovered.sampleID, segment: 2, elapsed: recovered.timestamp.elapsedNS)
        // Commit the actual generated parent through the production Store path.
        let batch = PersistenceBatch(batchID: BatchID(UUID()), sources: [], definitions: [], segments: [],
            raw: [], ema: [], buckets: [parent], trends: [], gaps: [])
        _ = try fixture.store.commitBatch(batch, sessionID: SessionID(Fixtures.uuid(301)), snapshotGeneration: 1)
        try fixture.deleteSamples(cutoff: 2_000_000_000)
        #expect(try fixture.sampleIDs(table: "raw_samples") == [old.sampleID])
        #expect(try fixture.sampleIDs(table: "ema_samples") == [old.sampleID])
    }

    @Test func matchingParentDeletesOnlyItsOwnSegment() throws {
        let fixture = try LookupFixture()
        defer { fixture.cleanup() }
        try fixture.insertSample(id: "old-segment", segment: 1, elapsed: 750_000_000)
        try fixture.insertSample(id: "new-segment", segment: 2, elapsed: 750_000_000)
        try fixture.insertParent(segment: 2, start: 0, partial: true)
        try fixture.deleteSamples(cutoff: 2_000_000_000)
        #expect(try fixture.sampleIDs(table: "raw_samples") == ["old-segment"])
        #expect(try fixture.sampleIDs(table: "ema_samples") == ["old-segment"])
    }

    @Test func missingParentAndOtherSeriesOrWidthCannotAuthorizeDeletion() throws {
        let fixture = try LookupFixture()
        defer { fixture.cleanup() }
        try fixture.insertSample(id: "uncommitted-parent", elapsed: 200_000_000)
        try fixture.insertParent(series: LookupFixture.otherSeries, segment: 1, start: 0)
        try fixture.insertParent(segment: 1, start: 0, width: 10)
        try fixture.deleteSamples(cutoff: 2_000_000_000)
        #expect(try fixture.sampleIDs(table: "raw_samples") == ["uncommitted-parent"])
        #expect(try fixture.sampleIDs(table: "ema_samples") == ["uncommitted-parent"])
        // Once the correct parent has committed, the same pending rows expire.
        try fixture.insertParent(segment: 1, start: 0)
        try fixture.deleteSamples(cutoff: 2_000_000_000)
        #expect(try fixture.sampleIDs(table: "raw_samples").isEmpty)
        #expect(try fixture.sampleIDs(table: "ema_samples").isEmpty)
    }

    @Test func halfOpenParentCutoffPartialAndMemberCascadeRemainCorrect() throws {
        let fixture = try LookupFixture()
        defer { fixture.cleanup() }
        // A point exactly at the previous parent's end needs the next parent.
        try fixture.insertSample(id: "at-uncovered-end", elapsed: 2_000_000_000)
        try fixture.insertParent(segment: 1, start: 1_000_000_000)
        try fixture.insertSample(id: "at-cutoff", elapsed: 3_000_000_000)
        try fixture.insertSample(id: "after-cutoff", elapsed: 3_000_000_001)
        try fixture.insertParent(segment: 1, start: 3_000_000_000, partial: true)
        try fixture.store.exec("INSERT INTO sample_members VALUES ('at-cutoff','expired-member'), ('after-cutoff','retained-member')")
        try fixture.deleteSamples(cutoff: 3_000_000_000)
        let expected = ["after-cutoff", "at-uncovered-end"]
        #expect(try fixture.sampleIDs(table: "raw_samples") == expected)
        #expect(try fixture.sampleIDs(table: "ema_samples") == expected)
        #expect(try fixture.store.queryInt64("SELECT COUNT(*) FROM sample_members") == 1)
        #expect(try fixture.memberDerivedIDs() == ["after-cutoff"])
        try fixture.deleteSamples(cutoff: 3_000_000_000)
        #expect(try fixture.sampleIDs(table: "raw_samples") == expected)
        #expect(try fixture.sampleIDs(table: "ema_samples") == expected)
    }
}

private func productionDeleteSQL(table: String) throws -> String {
    let method = table == "raw_samples" ? "deleteRawSamples" : "deleteEMASamples"
    let package = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: package.appendingPathComponent("Sources/TemperatureCore/Storage/Retention.swift"), encoding: .utf8)
    let signature = "func \(method)(beforeOrAt elapsedNS: Int64) throws {"
    guard let body = source.range(of: signature),
          let start = source.range(of: "sql: \"\"\"", range: body.upperBound..<source.endIndex),
          let end = source.range(of: "\"\"\"", range: start.upperBound..<source.endIndex) else {
        throw LookupError.missingProductionSQL(method)
    }
    return String(source[start.upperBound..<end.lowerBound])
}

private struct LookupMeasurement { let steps: Int32; let deleted: Int32 }

private func measureDelete(sql: String, table: String, parentCount: Int) throws -> LookupMeasurement {
    let fixture = try LookupFixture()
    defer { fixture.cleanup() }
    try fixture.store.exec("BEGIN IMMEDIATE")
    for index in 0..<parentCount {
        try fixture.insertParent(segment: 1, start: Int64(index) * 1_000_000_000)
    }
    let start = Int64(parentCount - 1) * 1_000_000_000
    for index in 0..<20 {
        try fixture.insertSample(id: "scale-\(index)", elapsed: start + Int64(index) * 50_000_000 + 1)
    }
    try fixture.store.exec("COMMIT")
    fixture.store.close()
    var handle: OpaquePointer?
    let opened = sqlite3_open_v2(fixture.url.path, &handle, SQLITE_OPEN_READWRITE, nil)
    guard opened == SQLITE_OK, let handle else { throw LookupError.sqlite(opened) }
    defer { sqlite3_close(handle) }
    guard sqlite3_exec(handle, "PRAGMA foreign_keys=ON", nil, nil, nil) == SQLITE_OK else {
        throw LookupError.sqlite(sqlite3_errcode(handle))
    }
    var statement: OpaquePointer?
    let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
    guard prepared == SQLITE_OK, let statement else { throw LookupError.sqlite(prepared) }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int64(statement, 1, start + 999_999_999) == SQLITE_OK else {
        throw LookupError.sqlite(sqlite3_errcode(handle))
    }
    let stepped = sqlite3_step(statement)
    guard stepped == SQLITE_DONE else { throw LookupError.sqlite(stepped) }
    return LookupMeasurement(steps: sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_VM_STEP, 0),
                             deleted: sqlite3_changes(handle))
}

private final class LookupFixture {
    static let series = "00000000-0000-4000-8000-000000000101"
    static let otherSeries = "00000000-0000-4000-8000-000000000102"
    let directory: URL
    let url: URL
    let store: SQLiteStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RetentionLookup-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("monitor.sqlite")
        store = try SQLiteStore(databaseURL: url)
        try store.applyBundledSchemaIfNeeded()
        try store.exec("""
            INSERT INTO session VALUES ('00000000-0000-4000-8000-000000000301',1,'test','test','test');
            INSERT INTO series VALUES ('\(Self.series)','00000000-0000-4000-8000-000000000301','cpu.zone.1',1,'cpuZone','one','identity');
            INSERT INTO series VALUES ('\(Self.otherSeries)','00000000-0000-4000-8000-000000000301','cpu.zone.2',1,'cpuZone','two','identity');
            INSERT INTO segments VALUES ('\(Self.series)',1,0,1,'initial'), ('\(Self.series)',2,500000000,1,'gap'), ('\(Self.otherSeries)',1,0,1,'initial');
            """)
    }

    func insertSample(id: String, segment: Int = 1, elapsed: Int64) throws {
        try store.exec("""
            INSERT INTO raw_samples VALUES ('\(id)','\(Self.series)',\(segment),\(elapsed),1,50,50.0,'unknown',NULL);
            INSERT INTO ema_samples VALUES ('\(id)','\(Self.series)',\(segment),\(elapsed),1,50.0);
            """)
    }

    func insertParent(series: String = LookupFixture.series, segment: Int, start: Int64, width: Int64 = 1, partial: Bool = true) throws {
        let end = start + width * 1_000_000_000
        try store.exec("""
            INSERT INTO aggregates VALUES ('\(series)',\(segment),\(width),\(start),\(end),50.0,50.0,50.0,50.0,\(start), 'parent',1,50000000,\(partial ? 1 : 0));
            """)
    }

    func deleteSamples(cutoff: Int64) throws {
        try store.deleteRawSamples(beforeOrAt: cutoff)
        try store.deleteEMASamples(beforeOrAt: cutoff)
    }

    func sampleIDs(table: String) throws -> [String] {
        try store.queryRows(sql: "SELECT sample_id FROM \(table) ORDER BY sample_id", bindings: []) { statement in
            guard let value = sqlite3_column_text(statement, 0) else { throw LookupError.sqlite(SQLITE_ERROR) }
            return String(cString: value)
        }
    }

    func memberDerivedIDs() throws -> [String] {
        try store.queryRows(sql: "SELECT derived_sample_id FROM sample_members ORDER BY derived_sample_id", bindings: []) { statement in
            guard let value = sqlite3_column_text(statement, 0) else { throw LookupError.sqlite(SQLITE_ERROR) }
            return String(cString: value)
        }
    }

    func cleanup() {
        store.close()
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum LookupError: Error { case missingProductionSQL(String), sqlite(Int32) }
