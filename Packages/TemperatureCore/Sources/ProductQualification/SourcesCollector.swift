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
        let registryID: String?
        let unitEvidence: String?
        let reason: String?
    }

    struct NVMeFacts: Encodable {
        let registryID: String?
        let physicalInterconnectLocation: String?
        let interconnectLookupStatus: InterconnectLookupStatus?
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
    let nvmeDiscovery: [NVMeFacts]
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
        let discovered: DiscoveredCatalog
        let catalog: QualifiedSourceCatalog
        do {
            discovered = try await transport.discoverRaw()
            catalog = try registry.qualify(discovered)
        } catch {
            await transport.close()
            throw error
        }
        await transport.close()
        let cpuKeys = cpuEvidence(profile: profile, catalog: catalog)
        let ssd = optionalEvidence(kind: .ssd, catalog: catalog)
        let battery = optionalEvidence(kind: .battery, catalog: catalog)
        let hidCount = discovered.sources.filter { $0.provider == .hid }.count
        let nvmeDiscovery = discovered.sources.filter { $0.provider == .nvme }.map {
            SourcesReport.NVMeFacts(
                registryID: $0.registryID,
                physicalInterconnectLocation: $0.physicalInterconnectLocation,
                interconnectLookupStatus: $0.interconnectLookupStatus
            )
        }

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
            hidDiagnosticCount: hidCount,
            nvmeDiscovery: nvmeDiscovery
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

    // Hardware qualification reports the same Registry decision as production sampling.
    // No raw/unqualified read or reconstructed SMC bytes can create an alternate result.
    private static func optionalEvidence(
        kind: SensorKind,
        catalog: QualifiedSourceCatalog
    ) -> SourcesReport.OptionalProvider {
        if let selected = catalog.available.first(where: { $0.kind == kind }) {
            return SourcesReport.OptionalProvider(
                kind: kind.rawValue, status: "selected",
                provider: selected.provider.rawValue, rawKey: selected.rawKey,
                registryID: selected.registryID, unitEvidence: selected.unitEvidence, reason: nil
            )
        }
        let unavailable = catalog.unavailable.first(where: { $0.intendedKind == kind })
        return SourcesReport.OptionalProvider(
            kind: kind.rawValue, status: "unavailable",
            provider: unavailable?.provider.rawValue, rawKey: unavailable?.rawKey,
            registryID: unavailable?.registryID, unitEvidence: nil,
            reason: unavailable?.reason ?? "registry_did_not_qualify_optional_provider"
        )
    }
}
