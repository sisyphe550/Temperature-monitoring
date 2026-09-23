import Foundation
import Testing
@testable import TemperatureCore

enum Fixtures {
    static func timestamp(ms: Int64) -> Timestamp {
        Timestamp(
            elapsedNS: ms * 1_000_000,
            wallUnixNS: 1_700_000_000_000_000_000 + ms * 1_000_000
        )
    }

    static func uuid(_ ordinal: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", ordinal))!
    }

    static func source(index: Int = 1, key: String = "Tp01") -> QualifiedSource {
        QualifiedSource(
            sourceID: SourceID(uuid(index)),
            transportHandle: "handle-\(index)",
            provider: .smc,
            rawKey: key,
            registryID: nil,
            connectionGeneration: 1,
            kind: .cpuZone,
            encoding: "flt ",
            unitEvidence: "test-fixture-celsius",
            evidence: .referenceClassified,
            mappingVersion: "fixture-v1"
        )
    }

    static func definition() throws -> SeriesDefinition {
        SeriesDefinition(
            seriesID: SeriesID(uuid(101)),
            metricID: try MetricID(validating: "fixture.cpu"),
            definitionVersion: 1,
            kind: .cpuZone,
            displayName: "测试来源",
            memberSourceIDs: [SourceID(uuid(1))],
            formula: .identity
        )
    }

    static func read(id: RequestID, ms: Int64, values: [Double], requestedPeriodMS: Int = 200) -> ReadBatch {
        ReadBatch(
            requestID: id,
            generation: 1,
            requestedPeriodMS: requestedPeriodMS,
            readings: values.enumerated().map { index, value in
                Reading(
                    sourceID: SourceID(uuid(index + 1)),
                    started: timestamp(ms: ms),
                    finished: timestamp(ms: ms),
                    outcome: .success(valueC: value, sourceWallUnixNS: nil, freshness: .unknown)
                )
            }
        )
    }

    static func persistence(id: BatchID, value: Double, ms: Int64) throws -> PersistenceBatch {
        let t = timestamp(ms: ms)
        return PersistenceBatch(
            batchID: id,
            sources: [source()],
            definitions: [try definition()],
            segments: [
                Segment(
                    seriesID: SeriesID(uuid(101)),
                    number: 1,
                    started: timestamp(ms: 0),
                    reason: .sessionStart
                )
            ],
            raw: [
                Sample(
                    sampleID: "fixture-session:1",
                    seriesID: SeriesID(uuid(101)),
                    segment: 1,
                    timestamp: t,
                    periodMS: 200,
                    valueC: value,
                    freshness: .unknown,
                    sourceWallUnixNS: nil,
                    memberSampleIDs: []
                )
            ],
            ema: [
                EMAValue(
                    sampleID: "fixture-session:1",
                    seriesID: SeriesID(uuid(101)),
                    segment: 1,
                    timestamp: t,
                    valueC: value
                )
            ],
            buckets: [],
            trends: [],
            gaps: []
        )
    }

    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var contractRoot: URL {
        packageRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/contracts")
    }
}
