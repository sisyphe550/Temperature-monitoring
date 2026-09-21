import Foundation
import Testing
import TemperatureCore

@Suite struct SourceRegistryTests {
    private let batteryPriority = [
        "iops:Temperature",
        "smc:TB1T",
        "smc:TB2T",
        "smc:TB0T",
    ]

    @Test func batteryPrefersIopsCFNumber() {
        let result = Registry.selectBatteryProvider(
            priority: batteryPriority,
            iops: IopsTemperatureField(kind: .celsius(28.5)),
            smcReadings: [
                SmcBatteryReading(rawKey: "TB1T", encoding: "flt ", bytes: [0, 0, 0xE1, 0x41]),
            ],
            expectedEncoding: "flt ",
            expectedByteCount: 4
        )
        guard case .selected(let selected) = result else {
            Issue.record("expected battery selection success")
            return
        }
        #expect(selected.provider == .iops)
        #expect(selected.rawKey == "Temperature")
    }

    @Test func batteryFallsBackToTB1TWhenIopsMissing() {
        let result = Registry.selectBatteryProvider(
            priority: batteryPriority,
            iops: IopsTemperatureField(kind: .absent),
            smcReadings: [
                SmcBatteryReading(rawKey: "TB1T", encoding: "flt ", bytes: [0, 0, 0xE1, 0x41]),
            ],
            expectedEncoding: "flt ",
            expectedByteCount: 4
        )
        guard case .selected(let selected) = result else {
            Issue.record("expected battery selection success")
            return
        }
        #expect(selected.provider == .smc)
        #expect(selected.rawKey == "TB1T")
    }

    @Test func batterySkipsIopsBooleanAndDoesNotFabricateZero() {
        let result = Registry.selectBatteryProvider(
            priority: batteryPriority,
            iops: IopsTemperatureField(kind: .boolean),
            smcReadings: [],
            expectedEncoding: "flt ",
            expectedByteCount: 4
        )
        guard case .unavailable(let record) = result else {
            Issue.record("expected battery selection failure")
            return
        }
        #expect(record.capability == .mappingUnknown)
    }

    @Test func batterySkipsBooleanIopsForTB1T() {
        let result = Registry.selectBatteryProvider(
            priority: batteryPriority,
            iops: IopsTemperatureField(kind: .boolean),
            smcReadings: [
                SmcBatteryReading(rawKey: "TB1T", encoding: "flt ", bytes: [0x00, 0x00, 0xCC, 0x41]),
            ],
            expectedEncoding: "flt ",
            expectedByteCount: 4
        )
        guard case .selected(let selected) = result else {
            Issue.record("expected TB1T fallback")
            return
        }
        #expect(selected.rawKey == "TB1T")
    }

    @Test func nvmeSelectsUniqueInternalCandidate() {
        let result = Registry.selectInternalNVMe(
            candidates: [
                NVMeDiscoveryCandidate(
                    registryID: "nvme-a",
                    interconnectLocation: "Internal",
                    lookupStatus: .ok
                ),
            ]
        )
        guard case .selected(let selected) = result else {
            Issue.record("expected nvme selection success")
            return
        }
        #expect(selected.registryID == "nvme-a")
    }

    @Test func nvmeRejectsMultipleInternalCandidates() {
        let result = Registry.selectInternalNVMe(
            candidates: [
                NVMeDiscoveryCandidate(registryID: "a", interconnectLocation: "Internal", lookupStatus: .ok),
                NVMeDiscoveryCandidate(registryID: "b", interconnectLocation: "Internal", lookupStatus: .ok),
            ]
        )
        guard case .unavailable(let record) = result else {
            Issue.record("expected nvme selection failure")
            return
        }
        #expect(record.reason == "multiple_internal_nvme_candidates")
    }

    @Test func nvmeRejectsParentTreeCycle() {
        let result = Registry.selectInternalNVMe(
            candidates: [
                NVMeDiscoveryCandidate(registryID: "loop", interconnectLocation: nil, lookupStatus: .cycle),
            ]
        )
        guard case .unavailable(let record) = result else {
            Issue.record("expected nvme lookup failure")
            return
        }
        #expect(record.capability == .mappingUnknown)
    }

    @Test func nvmeKelvinZeroIsNotReported() {
        #expect(SensorDecoding.nvmeTemperatureC(kelvin: 0) == nil)
    }

    @Test func nvmeKelvin300Is26Point85C() {
        let celsius = SensorDecoding.nvmeTemperatureC(kelvin: 300)
        #expect(celsius != nil)
        #expect(SensorDecoding.nearlyEqual(celsius!, 26.85))
    }

    @Test func hidMissingEventDoesNotYieldZeroCelsius() {
        #expect(Registry.hidTemperatureC(readStatus: -1, value: 0) == nil)
        #expect(Registry.hidTemperatureC(readStatus: 0, value: .infinity) == nil)
    }

    @Test func hidKeepsSameNameWithDifferentRegistryIDs() {
        let services = [
            (productName: "eACC CPU", registryID: "hid-1"),
            (productName: "eACC CPU", registryID: "hid-2"),
        ]
        #expect(Registry.hidDiagnosticSources(services).count == 2)
    }

    @Test func profileRegistryQualifiesAllTwelveCPUKeys() throws {
        let profile = try Configuration.bundledProfile()
        let catalog = try QualifyFixture.fullCPUCatalog(for: profile)
        let qualified = try ProfileRegistry(profile: profile).qualify(catalog)
        #expect(qualified.available.count == 12)
        #expect(qualified.unavailable.isEmpty)
    }

    @Test func profileRegistryMarksMissingCPUKeyUnavailable() throws {
        let profile = try Configuration.bundledProfile()
        let catalog = try QualifyFixture.fullCPUCatalog(for: profile, omitting: "Tp01")
        let qualified = try ProfileRegistry(profile: profile).qualify(catalog)
        #expect(qualified.available.count == 11)
        #expect(qualified.unavailable.contains(where: { $0.rawKey == "Tp01" }))
    }

    @Test func profileRegistryRejectsDuplicateCPUKey() throws {
        let profile = try Configuration.bundledProfile()
        var catalog = try QualifyFixture.fullCPUCatalog(for: profile)
        if let duplicate = catalog.sources.first(where: { $0.rawKey == "Tp01" }) {
            catalog = DiscoveredCatalog(
                generation: catalog.generation,
                sources: catalog.sources + [duplicate]
            )
        }
        let qualified = try ProfileRegistry(profile: profile).qualify(catalog)
        #expect(qualified.available.count == 11)
        #expect(qualified.unavailable.contains(where: { $0.reason == "duplicate_profile_cpu_key" }))
    }

    @Test func profileRegistryRejectsEncodingMismatch() throws {
        let profile = try Configuration.bundledProfile()
        let catalog = try QualifyFixture.fullCPUCatalog(for: profile, encodingOverride: "sp78")
        let qualified = try ProfileRegistry(profile: profile).qualify(catalog)
        #expect(qualified.available.isEmpty)
        #expect(qualified.unavailable.allSatisfy { $0.reason == "encoding_or_length_mismatch" })
    }

    @Test func profileRegistryKeepsDistinctHIDRegistryIDs() throws {
        let profile = try Configuration.bundledProfile()
        let catalog = DiscoveredCatalog(
            generation: 1,
            sources: [
                DiscoveredSource(
                    transportHandle: "hid:0",
                    provider: .hid,
                    rawKey: "eACC CPU",
                    registryID: "00000000-0000-4000-8000-000000000101",
                    encoding: "event",
                    byteCount: 0
                ),
                DiscoveredSource(
                    transportHandle: "hid:1",
                    provider: .hid,
                    rawKey: "eACC CPU",
                    registryID: "00000000-0000-4000-8000-000000000102",
                    encoding: "event",
                    byteCount: 0
                ),
            ]
        )
        let qualified = try ProfileRegistry(profile: profile).qualify(catalog)
        let hidRecords = qualified.unavailable.filter { $0.provider == .hid }
        #expect(hidRecords.count == 2)
        #expect(Set(hidRecords.compactMap(\.registryID)).count == 2)
    }

    @Test func metricResolverDoesNotInferTenPhysicalCores() throws {
        let profile = try Configuration.bundledProfile()
        let catalog = try QualifyFixture.fullCPUCatalog(for: profile)
        let qualified = try ProfileRegistry(profile: profile).qualify(catalog)
        #expect(MetricResolver.infersPhysicalCoreCount(from: qualified.available.count) == nil)
        let metrics = try MetricResolver.seriesMetricIDs(for: qualified.available)
        #expect(metrics.count == 1)
        #expect(try metrics[0].rawValue == "cpu.zone.max")
    }

    @Test func qualifiedClientMapsSourceIDsToReadBatch() async throws {
        let profile = try Configuration.bundledProfile()
        let catalog = try QualifyFixture.fullCPUCatalog(for: profile)
        let transport = QualifyFixture.StubTransport(catalog: catalog)
        let client = QualifiedSensorClient(
            transport: transport,
            registry: ProfileRegistry(profile: profile)
        )
        let qualified = try await client.discover()
        let first = try #require(qualified.available.first)
        let request = ReadRequest(
            requestID: try RequestID(validating: "00000000-0000-4000-8000-000000000301"),
            sourceIDs: [first.sourceID],
            requestedPeriodMS: 200
        )
        let batch = try await client.read(request)
        #expect(batch.readings.count == 1)
        #expect(batch.readings[0].sourceID == first.sourceID)
        await client.close()
    }
}

private enum QualifyFixture {
    struct StubTransport: SensorTransport {
        let catalog: DiscoveredCatalog

        func discoverRaw() async throws -> DiscoveredCatalog {
            catalog
        }

        func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch {
            TransportReadBatch(
                requestID: request.requestID,
                generation: request.generation,
                readings: request.transportHandles.map { handle in
                    TransportReading(
                        transportHandle: handle,
                        started: Timestamp(elapsedNS: 0, wallUnixNS: 1),
                        finished: Timestamp(elapsedNS: 1_000_000, wallUnixNS: 2),
                        outcome: .success(valueC: 25.5, sourceWallUnixNS: nil, freshness: .unknown)
                    )
                }
            )
        }

        func close() async {}
    }

    static func fullCPUCatalog(
        for profile: SensorProfile,
        omitting omittedKey: String? = nil,
        encodingOverride: String? = nil
    ) throws -> DiscoveredCatalog {
        let encoding = encodingOverride ?? profile.expectedSMCEncoding
        let sources = profile.cpuKeys.compactMap { key -> DiscoveredSource? in
            if key == omittedKey {
                return nil
            }
            return DiscoveredSource(
                transportHandle: "smc:\(key)",
                provider: .smc,
                rawKey: key,
                registryID: "reg-\(key)",
                encoding: encoding,
                byteCount: profile.expectedSMCSizeBytes
            )
        }
        return DiscoveredCatalog(generation: 1, sources: sources)
    }
}
