import Foundation
import Testing
import TemperatureCore

@Suite struct OptionalSourceQualificationTests {
    @Test func profileQualifiesOnlyHighestPrioritySMCBatterySource() throws {
        let result = try qualify([
            smc("TB0T"), smc("TB2T"), smc("TB1T"),
        ])
        let battery = try #require(result.available.first(where: { $0.kind == .battery }))
        #expect(result.available.filter { $0.kind == .battery }.count == 1)
        #expect(battery.rawKey == "TB1T")
        #expect(battery.provider == .smc)
        #expect(battery.connectionGeneration == 1)
        #expect(!battery.unitEvidence.isEmpty)
        #expect(result.available.filter { $0.kind == .cpuZone }.count == 12)
    }

    @Test func profilePrefersValidIOPSTemperatureOverSMC() throws {
        let result = try qualify([
            DiscoveredSource(
                transportHandle: "iops:42:Temperature",
                provider: .iops,
                rawKey: "Temperature",
                registryID: "iops:42",
                encoding: "cfnumber_celsius",
                byteCount: 0
            ),
            smc("TB1T"),
        ])
        let battery = try #require(result.available.first(where: { $0.kind == .battery }))
        #expect(battery.provider == .iops)
        #expect(battery.transportHandle == "iops:42:Temperature")
        #expect(result.available.filter { $0.kind == .battery }.count == 1)
    }

    @Test func badBatteryEncodingFallsThroughToNextProfileCandidate() throws {
        let result = try qualify([
            smc("TB1T", encoding: "sp78", byteCount: 2),
            smc("TB2T"), smc("TB0T"),
        ])
        let battery = try #require(result.available.first(where: { $0.kind == .battery }))
        #expect(battery.rawKey == "TB2T")
        #expect(battery.encoding == "flt ")
    }

    @Test func duplicateBatteryIdentityIsUnavailableWithoutStoppingCPU() throws {
        let duplicate = DiscoveredSource(
            transportHandle: "smc:other:TB1T",
            provider: .smc,
            rawKey: "TB1T",
            registryID: "other-smc-endpoint",
            encoding: "flt ",
            byteCount: 4
        )
        let result = try qualify([smc("TB1T"), duplicate])
        #expect(result.available.filter { $0.kind == .battery }.isEmpty)
        let unavailable = try #require(result.unavailable.first(where: { $0.intendedKind == .battery }))
        #expect(unavailable.capability == .mappingUnknown)
        #expect(!unavailable.reason.isEmpty)
        #expect(result.available.filter { $0.kind == .cpuZone }.count == 12)
    }

    @Test func absentOptionalProvidersProduceExplicitCapabilityRecords() throws {
        let result = try qualify([])
        let battery = try #require(result.unavailable.first(where: { $0.intendedKind == .battery }))
        let ssd = try #require(result.unavailable.first(where: { $0.intendedKind == .ssd }))
        #expect(!battery.reason.isEmpty)
        #expect(!ssd.reason.isEmpty)
        #expect(result.available.filter { $0.kind == .cpuZone }.count == 12)
    }

    @Test func nonFiniteIOPSCannotDisplaceValidSMCBattery() throws {
        let selection = Registry.selectBatteryProvider(
            priority: ["iops:Temperature", "smc:TB1T"],
            iops: IopsTemperatureField(kind: .celsius(.nan)),
            smcReadings: [SmcBatteryReading(rawKey: "TB1T", encoding: "flt ", bytes: [0, 0, 0x10, 0x42])],
            expectedEncoding: "flt ",
            expectedByteCount: 4
        )
        guard case .selected(let battery) = selection else {
            Issue.record("valid SMC battery should remain selectable")
            return
        }
        #expect(battery.provider == .smc)
        #expect(battery.rawKey == "TB1T")
    }

    private func qualify(_ optionalSources: [DiscoveredSource], generation: UInt64 = 1) throws -> QualifiedSourceCatalog {
        let profile = try Configuration.bundledProfile()
        let cpu = profile.cpuKeys.map { smc($0) }
        return try ProfileRegistry(profile: profile).qualify(
            DiscoveredCatalog(generation: generation, sources: cpu + optionalSources)
        )
    }

    private func smc(_ key: String, encoding: String = "flt ", byteCount: Int = 4) -> DiscoveredSource {
        DiscoveredSource(
            transportHandle: "smc:\(key)",
            provider: .smc,
            rawKey: key,
            registryID: "reg-\(key)",
            encoding: encoding,
            byteCount: byteCount
        )
    }
}
