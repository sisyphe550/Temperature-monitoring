import Foundation
import Testing
import TemperatureCore

@Suite struct NVMeSourceQualificationTests {
    @Test func uniqueInternalNVMeIsQualifiedWithRealIdentityAndKelvinEvidence() throws {
        let result = try qualify([nvme("42", location: "Internal")])
        let ssd = try #require(result.available.first(where: { $0.kind == .ssd }))
        #expect(ssd.registryID == "42")
        #expect(ssd.transportHandle == "nvme:42")
        #expect(ssd.encoding == "uint16_le_kelvin")
        #expect(ssd.unitEvidence.contains("Kelvin"))
        #expect(ssd.connectionGeneration == 1)
        #expect(result.available.filter { $0.kind == .cpuZone }.count == 12)
    }

    @Test func externalDeviceDoesNotDisplaceUniqueInternalDevice() throws {
        let result = try qualify([
            nvme("external", location: "External"), nvme("internal", location: "Internal"),
        ])
        let ssd = try #require(result.available.first(where: { $0.kind == .ssd }))
        #expect(ssd.registryID == "internal")
        #expect(result.available.filter { $0.kind == .ssd }.count == 1)
    }

    @Test func externalOnlyIsUnavailableWithoutStoppingCPU() throws {
        let result = try qualify([nvme("external", location: "External")])
        let unavailable = try unavailableSSD(result)
        #expect(unavailable.reason == "no_internal_nvme_candidate")
        #expect(unavailable.capability == .unsupported)
    }

    @Test func multipleInternalDevicesAreUnavailable() throws {
        let result = try qualify([nvme("42", location: "Internal"), nvme("43", location: "Internal")])
        #expect(try unavailableSSD(result).reason == "multiple_internal_nvme_candidates")
    }

    @Test func missingFailedAndUnattemptedInterconnectFactsBlockSelection() throws {
        let statuses: [InterconnectLookupStatus?] = [.missingProperty, .lookupFailed, nil]
        for status in statuses {
            let result = try qualify([
                nvme("known-internal", location: "Internal"),
                nvme("unknown", location: nil, status: status),
            ])
            let unavailable = try unavailableSSD(result)
            #expect(unavailable.capability == .mappingUnknown)
            #expect(unavailable.registryID == "unknown")
            #expect(!unavailable.reason.isEmpty)
        }
    }

    @Test func foundRequiresNonemptyLocationAndRealRegistryIdentity() throws {
        let invalidLocations: [String?] = [nil, "", "  ", "Internal\0External"]
        for location in invalidLocations {
            let result = try qualify([nvme("42", location: location)])
            #expect(try unavailableSSD(result).capability == .mappingUnknown)
        }
        let missingID = DiscoveredSource(
            transportHandle: "nvme:local-index", provider: .nvme, rawKey: "TEMPERATURE",
            registryID: nil, encoding: "uint16_le_kelvin", byteCount: 2,
            physicalInterconnectLocation: "Internal", interconnectLookupStatus: .found
        )
        #expect(try unavailableSSD(qualify([missingID])).reason == "nvme_registry_identity_missing")
    }

    @Test func invalidEncodingAndLengthDoNotBecomeSSD() throws {
        let candidates = [
            nvme("42", location: "Internal", encoding: "flt "),
            nvme("42", location: "Internal", byteCount: 4),
        ]
        for candidate in candidates {
            let result = try qualify([candidate])
            #expect(try unavailableSSD(result).reason == "nvme_encoding_or_length_mismatch")
        }
    }

    @Test func duplicateTransportHandleCannotReadAnotherDeviceAsSSD() throws {
        let internalDevice = nvme("42", location: "Internal")
        let conflicting = DiscoveredSource(
            transportHandle: internalDevice.transportHandle, provider: .nvme,
            rawKey: "TEMPERATURE", registryID: "external", encoding: "uint16_le_kelvin", byteCount: 2,
            physicalInterconnectLocation: "External", interconnectLookupStatus: .found
        )
        let result = try qualify([internalDevice, conflicting])
        #expect(try unavailableSSD(result).reason == "nvme_registry_identity_conflicting")
    }

    @Test func optionalIdentityIncludesGenerationAndSelectedProvider() throws {
        let first = try qualify([nvme("42", location: "Internal"), smc("TB1T")], generation: 1)
        let second = try qualify([nvme("42", location: "Internal"), smc("TB1T")], generation: 2)
        for kind in [SensorKind.ssd, .battery] {
            let source1 = try #require(first.available.first(where: { $0.kind == kind }))
            let source2 = try #require(second.available.first(where: { $0.kind == kind }))
            #expect(source1.sourceID != source2.sourceID)
        }
        let replacement = try qualify([smc("TB2T")], generation: 1)
        let battery1 = try #require(first.available.first(where: { $0.kind == .battery }))
        let battery2 = try #require(replacement.available.first(where: { $0.kind == .battery }))
        #expect(battery1.sourceID != battery2.sourceID)
    }

    @Test func missingIOPSIdentityFallsBackToValidSMC() throws {
        let missingIdentity = DiscoveredSource(
            transportHandle: "iops:Temperature", provider: .iops, rawKey: "Temperature",
            registryID: nil, encoding: "cfnumber_celsius", byteCount: 0
        )
        let result = try qualify([missingIdentity, smc("TB1T")])
        let battery = try #require(result.available.first(where: { $0.kind == .battery }))
        #expect(battery.provider == .smc)
    }

    private func unavailableSSD(_ catalog: QualifiedSourceCatalog) throws -> SourceCapabilityRecord {
        #expect(catalog.available.filter { $0.kind == .ssd }.isEmpty)
        #expect(catalog.available.filter { $0.kind == .cpuZone }.count == 12)
        return try #require(catalog.unavailable.first(where: { $0.intendedKind == .ssd }))
    }

    private func qualify(_ optional: [DiscoveredSource], generation: UInt64 = 1) throws -> QualifiedSourceCatalog {
        let profile = try Configuration.bundledProfile()
        return try ProfileRegistry(profile: profile).qualify(
            DiscoveredCatalog(generation: generation, sources: profile.cpuKeys.map { smc($0) } + optional)
        )
    }

    private func smc(_ key: String) -> DiscoveredSource {
        DiscoveredSource(
            transportHandle: "smc:\(key)", provider: .smc, rawKey: key,
            registryID: key, encoding: "flt ", byteCount: 4
        )
    }

    private func nvme(
        _ id: String, location: String?, status: InterconnectLookupStatus? = .found,
        encoding: String = "uint16_le_kelvin", byteCount: Int = 2
    ) -> DiscoveredSource {
        DiscoveredSource(
            transportHandle: "nvme:\(id)", provider: .nvme, rawKey: "TEMPERATURE", registryID: id,
            encoding: encoding, byteCount: byteCount,
            physicalInterconnectLocation: location, interconnectLookupStatus: status
        )
    }
}
