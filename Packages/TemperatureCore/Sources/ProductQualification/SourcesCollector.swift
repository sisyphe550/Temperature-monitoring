import Darwin
import Foundation
import SensorRuntime
import TemperatureCore

struct SourcesReport: Encodable {
    struct CPUKey: Encodable {
        let rawKey: String
        let status: String
        let encoding: String?
        let byteCount: Int?
        let reason: String?
    }

    struct OptionalProvider: Encodable {
        let kind: String
        let status: String
        let provider: String?
        let rawKey: String?
        let reason: String?
    }

    let artifactKind = "product-hardware-sources"
    let schemaVersion = 1
    let recordedAt: String
    let generation: UInt64
    let cpuKeys: [CPUKey]
    let cpuAvailableCount: Int
    let cpuExpectedCount: Int
    let ssd: OptionalProvider
    let battery: OptionalProvider
    let hidDiagnosticCount: Int
    let mappingAndFreshness = "not inferred from names or repeated values"
}

enum SourcesCollector {
    static func collect(workerURL: URL, profileURL: URL) async throws -> SourcesReport {
        let profile = try Configuration.loadProfile(from: profileURL)
        try assertHostModel(profile: profile)

        let transport = WorkerClient(
            configuration: WorkerClientConfiguration(executableURL: workerURL)
        )
        let registry = ProfileRegistry(profile: profile)
        let discovered = try await transport.discoverRaw()
        let catalog = try registry.qualify(discovered)
        let cpuKeys = cpuEvidence(profile: profile, catalog: catalog)
        let ssd = ssdEvidence(from: discovered)
        let battery = try await batteryEvidence(
            profile: profile,
            discovered: discovered,
            transport: transport,
            generation: discovered.generation
        )
        let hidCount = discovered.sources.filter { $0.provider == .hid }.count
        await transport.close()

        guard cpuKeys.filter({ $0.status == "available" }).count == profile.cpuKeys.count else {
            throw QualificationError.cpuMembershipIncomplete(
                expected: profile.cpuKeys.count,
                available: cpuKeys.filter { $0.status == "available" }.count
            )
        }

        return SourcesReport(
            recordedAt: ISO8601DateFormatter().string(from: Date()),
            generation: catalog.generation,
            cpuKeys: cpuKeys,
            cpuAvailableCount: cpuKeys.filter { $0.status == "available" }.count,
            cpuExpectedCount: profile.cpuKeys.count,
            ssd: ssd,
            battery: battery,
            hidDiagnosticCount: hidCount
        )
    }

    private static func cpuEvidence(
        profile: SensorProfile,
        catalog: QualifiedSourceCatalog
    ) -> [SourcesReport.CPUKey] {
        profile.cpuKeys.map { key in
            if let source = catalog.available.first(where: { $0.rawKey == key && $0.kind == .cpuZone }) {
                return SourcesReport.CPUKey(
                    rawKey: key,
                    status: "available",
                    encoding: source.encoding,
                    byteCount: profile.expectedSMCSizeBytes,
                    reason: nil
                )
            }
            let unavailable = catalog.unavailable.first(where: { $0.rawKey == key })
            return SourcesReport.CPUKey(
                rawKey: key,
                status: "unavailable",
                encoding: unavailable?.provider.rawValue,
                byteCount: nil,
                reason: unavailable?.reason
            )
        }
    }

    private static func ssdEvidence(from discovered: DiscoveredCatalog) -> SourcesReport.OptionalProvider {
        let candidates = discovered.sources
            .filter { $0.provider == .nvme }
            .map {
                NVMeDiscoveryCandidate(
                    registryID: $0.registryID ?? $0.transportHandle,
                    interconnectLocation: nil,
                    lookupStatus: .missingProperty
                )
            }
        let selection = Registry.selectInternalNVMe(candidates: candidates)
        switch selection {
        case .selected(let selected):
            return SourcesReport.OptionalProvider(
                kind: "ssd",
                status: "selected",
                provider: ProviderKind.nvme.rawValue,
                rawKey: "TEMPERATURE",
                reason: selected.registryID
            )
        case .unavailable(let record):
            return SourcesReport.OptionalProvider(
                kind: "ssd",
                status: "unavailable",
                provider: record.provider.rawValue,
                rawKey: record.rawKey,
                reason: record.reason
            )
        }
    }

    private static func batteryEvidence(
        profile: SensorProfile,
        discovered: DiscoveredCatalog,
        transport: WorkerClient,
        generation: UInt64
    ) async throws -> SourcesReport.OptionalProvider {
        let iopsField: IopsTemperatureField
        iopsField = try await readIopsField(
            discovered: discovered,
            transport: transport,
            generation: generation
        )
        let smcReadings = try await readBatterySMCCandidates(
            profile: profile,
            discovered: discovered,
            transport: transport,
            generation: generation
        )

        let selection = Registry.selectBatteryProvider(
            priority: profile.batteryProviderPriority,
            iops: iopsField,
            smcReadings: smcReadings,
            expectedEncoding: profile.expectedSMCEncoding,
            expectedByteCount: profile.expectedSMCSizeBytes
        )

        switch selection {
        case .selected(let selected):
            return SourcesReport.OptionalProvider(
                kind: "battery",
                status: "selected",
                provider: selected.provider.rawValue,
                rawKey: selected.rawKey,
                reason: nil
            )
        case .unavailable(let record):
            return SourcesReport.OptionalProvider(
                kind: "battery",
                status: "unavailable",
                provider: record.provider.rawValue,
                rawKey: record.rawKey,
                reason: record.reason
            )
        }
    }

    private static func readIopsField(
        discovered: DiscoveredCatalog,
        transport: WorkerClient,
        generation: UInt64
    ) async throws -> IopsTemperatureField {
        guard discovered.sources.contains(where: { $0.transportHandle == "iops:Temperature" }) else {
            return IopsTemperatureField(kind: .absent)
        }
        let requestID = try RequestID(validating: UUID().uuidString.lowercased())
        let batch = try await transport.readRaw(
            TransportReadRequest(
                requestID: requestID,
                generation: generation,
                transportHandles: ["iops:Temperature"],
                requestedPeriodMS: 0
            )
        )
        guard let reading = batch.readings.first else {
            return IopsTemperatureField(kind: .absent)
        }
        switch reading.outcome {
        case .success(let value, _, _):
            return IopsTemperatureField(kind: .celsius(value))
        case .failure(_, let underlying) where underlying == "field_absent":
            return IopsTemperatureField(kind: .absent)
        case .failure(_, let underlying) where underlying == "unexpected_type":
            return IopsTemperatureField(kind: .boolean)
        default:
            return IopsTemperatureField(kind: .nonNumber)
        }
    }

    private static func readBatterySMCCandidates(
        profile: SensorProfile,
        discovered: DiscoveredCatalog,
        transport: WorkerClient,
        generation: UInt64
    ) async throws -> [SmcBatteryReading] {
        let keys = profile.batteryProviderPriority.compactMap { entry -> String? in
            guard entry.hasPrefix("smc:") else {
                return nil
            }
            return String(entry.dropFirst(4))
        }
        var readings: [SmcBatteryReading] = []
        for key in keys {
            guard let source = discovered.sources.first(where: { $0.provider == .smc && $0.rawKey == key }) else {
                continue
            }
            let requestID = try RequestID(validating: UUID().uuidString.lowercased())
            let batch = try await transport.readRaw(
                TransportReadRequest(
                    requestID: requestID,
                    generation: generation,
                    transportHandles: [source.transportHandle],
                    requestedPeriodMS: 0
                )
            )
            guard let outcome = batch.readings.first?.outcome,
                  case .success(let value, _, _) = outcome,
                  value.isFinite else {
                continue
            }
            readings.append(
                SmcBatteryReading(
                    rawKey: key,
                    encoding: source.encoding,
                    bytes: smcBytes(for: value, byteCount: source.byteCount)
                )
            )
        }
        return readings
    }

    private static func smcBytes(for celsius: Double, byteCount: Int) -> [UInt8] {
        guard byteCount == 4 else {
            return []
        }
        var float = Float(celsius)
        let data = withUnsafeBytes(of: &float) { Array($0) }
        return data
    }
}
