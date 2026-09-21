import Foundation
import Testing
@testable import TemperatureCore

@Suite struct ContractTests {
    @Test func taggedUUIDRequiresCanonicalLowercase() throws {
        let uuid = try SessionID(validating: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        #expect(uuid.rawValue == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        #expect(throws: IdentifierError.self) {
            _ = try SessionID(validating: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")
        }
        #expect(throws: IdentifierError.self) {
            _ = try SourceID(validating: "not-a-uuid")
        }
    }

    @Test func metricIDRejectsInvalidAndEmptyValues() {
        #expect(throws: IdentifierError.emptyMetricID) {
            _ = try MetricID(validating: "")
        }
        #expect(throws: IdentifierError.invalidMetricID("CPU.Zone")) {
            _ = try MetricID(validating: "CPU.Zone")
        }
        #expect(throws: IdentifierError.invalidMetricID("cpu-zone")) {
            _ = try MetricID(validating: "cpu-zone")
        }
    }

    @Test func unknownClosedEnumFailsDecoding() throws {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SensorKind.self, from: Data("\"physicalCore\"".utf8))
        }
    }

    @Test func timestampPreservesNanoseconds() throws {
        let original = Timestamp(elapsedNS: 9_007_199_254_740_993, wallUnixNS: 1_700_000_000_000_000_001)
        let decoded = try JSONDecoder().decode(Timestamp.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func readingOutcomeCannotCarrySuccessAndFailure() {
        let success = ReadingOutcome.success(valueC: 42.5, sourceWallUnixNS: nil, freshness: .unknown)
        let failure = ReadingOutcome.failure(
            MonitorFailure(
                code: .sensorRead,
                severity: .fatal,
                component: "test",
                operation: "read",
                retryCount: 0,
                sourceID: nil,
                underlyingCode: nil
            )
        )
        #expect(success != failure)
        switch success {
        case .success(let value, _, _):
            #expect(value == 42.5)
        case .failure:
            Issue.record("success case must not be failure")
        }
    }

    @Test func presentationStateIsMutuallyExclusive() {
        let running = PresentationState.running(
            RunningPresentationState(
                asOf: Timestamp(elapsedNS: 0, wallUnixNS: 0),
                cpuPeriodMS: 200,
                primaryCPU: .loading,
                sections: [],
                chart: .loading(previous: [])
            )
        )
        let fatal = PresentationState.fatal(
            FatalPresentationState(
                failure: MonitorFailure(
                    code: .appInit,
                    severity: .fatal,
                    component: "app",
                    operation: "start",
                    retryCount: 0,
                    sourceID: nil,
                    underlyingCode: nil
                ),
                reportPath: nil,
                exitDeadline: Timestamp(elapsedNS: 1, wallUnixNS: 1)
            )
        )
        #expect(running != fatal)
    }

    @Test func persistenceLeaseHasNoPublicCodableOrEmptyInit() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/TemperatureCore/Contracts/PersistenceTypes.swift"),
            encoding: .utf8
        )
        guard let start = source.range(of: "public struct PersistenceLease"),
              let end = source.range(of: "public struct ProcessingReceipt")
        else {
            Issue.record("PersistenceLease block missing")
            return
        }
        let lease = source[start.lowerBound..<end.lowerBound]
        #expect(lease.contains("public struct PersistenceLease: Sendable, Equatable"))
        #expect(!lease.contains("Codable"))
        #expect(!lease.contains("public init("))
        #expect(!source.contains("public struct QueueReservation"))
    }

    @Test func obsoleteContractTokensAreAbsentFromSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/TemperatureCore")
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
        let forbidden = ["public struct QueueReservation", "valueC: Double?", "case success(valueC: Double?"]
        for file in files {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for token in forbidden {
                #expect(!text.contains(token), "\(file) still contains \(token)")
            }
        }
    }
}
