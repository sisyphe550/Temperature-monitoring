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
}
