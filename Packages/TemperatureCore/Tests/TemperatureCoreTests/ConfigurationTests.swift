import Foundation
import Testing
@testable import TemperatureCore

@Suite struct ConfigurationTests {
    @Test func bundledRevisionTwoDefaultsLoad() throws {
        let configuration = try Configuration.bundledDefaults()
        #expect(configuration.contractVersion == 2)
        #expect(configuration.cpuIntervalsMS == [50, 100, 200, 500, 1000])
        #expect(configuration.cpuDefaultMS == 200)
        #expect(configuration.emaTauSeconds.cpuMain > 0)
        #expect(configuration.writerResumeBelowRecords < configuration.writerPauseAtRecords)
        #expect(configuration.writerPauseAtRecords < configuration.writerMaxRecords)
        #expect(configuration.writerReserveRecordsPerEvent <= configuration.writerFlushRecords)
    }

    @Test func bundledProfileHasTwelveCaseSensitiveKeys() throws {
        let profile = try Configuration.bundledProfile()
        #expect(profile.profileID == "Mac16,13-m4-v1")
        #expect(profile.cpuKeys.count == 12)
        #expect(Set(profile.cpuKeys).count == 12)
        #expect(profile.cpuKeys.contains("Tp0b"))
        #expect(!profile.cpuKeys.contains("TP0B"))
        #expect(profile.expectedSMCEncoding == "flt ")
        #expect(profile.automaticUnknownModelProfile == false)
    }

    @Test func rejectsContractVersionOne() throws {
        let json = try mutatedDefaults { $0["contract_version"] = NSNumber(value: 1) }
        #expect(throws: ConfigurationError.unsupportedContractVersion(1)) {
            _ = try Configuration.decodeConfiguration(json)
        }
    }

    @Test func rejectsUnknownContractVersion() throws {
        let json = try mutatedDefaults { $0["contract_version"] = NSNumber(value: 99) }
        #expect(throws: ConfigurationError.unsupportedContractVersion(99)) {
            _ = try Configuration.decodeConfiguration(json)
        }
    }

    @Test func rejectsMissingRequiredField() throws {
        let json = try mutatedDefaults { $0.removeObject(forKey: "cpu_default_ms") }
        #expect(throws: ConfigurationError.missingField("cpu_default_ms")) {
            _ = try Configuration.decodeConfiguration(json)
        }
    }

    @Test func rejectsNegativeCapacity() throws {
        let json = try mutatedDefaults { $0["ring_capacity_per_series"] = NSNumber(value: -1) }
        #expect(throws: ConfigurationError.invalidValue("capacity")) {
            _ = try Configuration.decodeConfiguration(json)
        }
    }

    @Test func rejectsInvalidJSON() {
        #expect(throws: ConfigurationError.invalidJSON) {
            _ = try Configuration.decodeConfiguration(Data("{".utf8))
        }
    }

    @Test func rejectsInvalidWriterWatermarkOrdering() throws {
        let json = try mutatedDefaults {
            $0["writer_resume_below_records"] = NSNumber(value: 20_000)
            $0["writer_pause_at_records"] = NSNumber(value: 10_000)
        }
        #expect(throws: ConfigurationError.invalidValue("writer watermarks")) {
            _ = try Configuration.decodeConfiguration(json)
        }
    }

    @Test func rejectsReserveExceedingFlush() throws {
        let json = try mutatedDefaults {
            $0["writer_reserve_records_per_event"] = NSNumber(value: 999)
            $0["writer_flush_records"] = NSNumber(value: 512)
        }
        #expect(throws: ConfigurationError.invalidValue("writer_reserve_records_per_event")) {
            _ = try Configuration.decodeConfiguration(json)
        }
    }

    @Test func rejectsInvalidRetentionOrdering() throws {
        let json = try mutatedDefaults {
            let retention = ($0["retention_seconds"] as! NSMutableDictionary)
            retention["raw"] = NSNumber(value: 999_999)
        }
        #expect(throws: ConfigurationError.invalidValue("retention_seconds")) {
            _ = try Configuration.decodeConfiguration(json)
        }
    }

    @Test func rejectsDuplicateOrReorderedCPUKeys() throws {
        let url = Fixtures.packageRoot.appendingPathComponent("Sources/TemperatureCore/Resources/first-profile-v1.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url), options: [.mutableContainers]) as! NSMutableDictionary
        let keys = object["cpu_keys"] as! NSArray
        object["cpu_keys"] = NSArray(array: keys.reversed())
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ConfigurationError.invalidValue("sensor profile")) {
            _ = try Configuration.decodeProfile(data)
        }
    }

    private func mutatedDefaults(_ mutate: (NSMutableDictionary) -> Void) throws -> Data {
        let url = Fixtures.packageRoot.appendingPathComponent("Sources/TemperatureCore/Resources/defaults-v1.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url), options: [.mutableContainers]) as! NSMutableDictionary
        mutate(object)
        return try JSONSerialization.data(withJSONObject: object)
    }
}
