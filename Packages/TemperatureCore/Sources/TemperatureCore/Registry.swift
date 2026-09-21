import Foundation

public struct IopsTemperatureField: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case absent
        case boolean
        case nonNumber
        case nonFinite
        case celsius(Double)
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }
}

public struct SmcBatteryReading: Sendable, Equatable {
    public let rawKey: String
    public let encoding: String
    public let bytes: [UInt8]

    public init(rawKey: String, encoding: String, bytes: [UInt8]) {
        self.rawKey = rawKey
        self.encoding = encoding
        self.bytes = bytes
    }
}

public struct NVMeDiscoveryCandidate: Sendable, Equatable {
    public enum LookupStatus: Sendable, Equatable {
        case ok
        case missingProperty
        case tooDeep
        case cycle
    }

    public let registryID: String
    public let interconnectLocation: String?
    public let lookupStatus: LookupStatus

    public init(registryID: String, interconnectLocation: String?, lookupStatus: LookupStatus) {
        self.registryID = registryID
        self.interconnectLocation = interconnectLocation
        self.lookupStatus = lookupStatus
    }
}

public struct SelectedOptionalProvider: Sendable, Equatable {
    public let provider: ProviderKind
    public let rawKey: String
    public let registryID: String?

    public init(provider: ProviderKind, rawKey: String, registryID: String? = nil) {
        self.provider = provider
        self.rawKey = rawKey
        self.registryID = registryID
    }
}

public enum BatteryProviderSelection: Sendable, Equatable {
    case selected(SelectedOptionalProvider)
    case unavailable(SourceCapabilityRecord)
}

public enum NVMeProviderSelection: Sendable, Equatable {
    case selected(NVMeDiscoveryCandidate)
    case unavailable(SourceCapabilityRecord)
}

public enum Registry {
    public static func selectBatteryProvider(
        priority: [String],
        iops: IopsTemperatureField,
        smcReadings: [SmcBatteryReading],
        expectedEncoding: String,
        expectedByteCount: Int
    ) -> BatteryProviderSelection {
        for entry in priority {
            if entry == "iops:Temperature" {
                switch iops.kind {
                case .celsius:
                    return .selected(SelectedOptionalProvider(provider: .iops, rawKey: "Temperature"))
                case .absent, .boolean, .nonNumber, .nonFinite:
                    continue
                }
            }

            guard entry.hasPrefix("smc:") else {
                continue
            }
            let rawKey = String(entry.dropFirst(4))
            guard let reading = smcReadings.first(where: { $0.rawKey == rawKey }) else {
                continue
            }
            guard reading.encoding == expectedEncoding, reading.bytes.count == expectedByteCount else {
                continue
            }
            guard let celsius = SensorDecoding.smcTemperatureC(
                encoding: reading.encoding,
                bytes: reading.bytes
            ) else {
                continue
            }
            guard celsius.isFinite else {
                continue
            }
            return .selected(SelectedOptionalProvider(provider: .smc, rawKey: rawKey))
        }

        return .unavailable(
            SourceCapabilityRecord(
                provider: .iops,
                rawKey: "Temperature",
                registryID: nil,
                intendedKind: .battery,
                capability: .mappingUnknown,
                reason: "no_battery_provider_in_priority_chain"
            )
        )
    }

    public static func selectInternalNVMe(
        candidates: [NVMeDiscoveryCandidate]
    ) -> NVMeProviderSelection {
        let blocked = candidates.filter {
            $0.lookupStatus == .cycle || $0.lookupStatus == .tooDeep || $0.lookupStatus == .missingProperty
        }
        if !blocked.isEmpty {
            return .unavailable(
                SourceCapabilityRecord(
                    provider: .nvme,
                    rawKey: nil,
                    registryID: blocked[0].registryID,
                    intendedKind: .ssd,
                    capability: .mappingUnknown,
                    reason: "nvme_interconnect_lookup_failed"
                )
            )
        }

        let internalCandidates = candidates.filter { $0.interconnectLocation == "Internal" }
        switch internalCandidates.count {
        case 1:
            return .selected(internalCandidates[0])
        case 0:
            return .unavailable(
                SourceCapabilityRecord(
                    provider: .nvme,
                    rawKey: nil,
                    registryID: nil,
                    intendedKind: .ssd,
                    capability: .unsupported,
                    reason: "no_internal_nvme_candidate"
                )
            )
        default:
            return .unavailable(
                SourceCapabilityRecord(
                    provider: .nvme,
                    rawKey: nil,
                    registryID: nil,
                    intendedKind: .ssd,
                    capability: .mappingUnknown,
                    reason: "multiple_internal_nvme_candidates"
                )
            )
        }
    }

    public static func hidDiagnosticSources(
        _ services: [(productName: String, registryID: String)]
    ) -> [(productName: String, registryID: String)] {
        services
    }

    public static func hidTemperatureC(readStatus: Int32, value: Double) -> Double? {
        guard readStatus == 0, value.isFinite else {
            return nil
        }
        return value
    }
}

public struct ProfileRegistry: SourceRegistry {
    public let profile: SensorProfile
    public let mappingVersion: String

    public init(profile: SensorProfile, mappingVersion: String = "mac16-13-v1") {
        self.profile = profile
        self.mappingVersion = mappingVersion
    }

    public func qualify(_ catalog: DiscoveredCatalog) throws -> QualifiedSourceCatalog {
        var available: [QualifiedSource] = []
        var unavailable: [SourceCapabilityRecord] = []

        qualifyCPUSources(from: catalog, available: &available, unavailable: &unavailable)
        recordHIDDiagnostics(from: catalog, unavailable: &unavailable)

        return QualifiedSourceCatalog(
            generation: catalog.generation,
            available: available,
            unavailable: unavailable
        )
    }

    private func qualifyCPUSources(
        from catalog: DiscoveredCatalog,
        available: inout [QualifiedSource],
        unavailable: inout [SourceCapabilityRecord]
    ) {
        let smcSources = catalog.sources.filter { $0.provider == .smc }

        for (index, key) in profile.cpuKeys.enumerated() {
            let matches = smcSources.filter { $0.rawKey == key }
            if matches.isEmpty {
                unavailable.append(
                    SourceCapabilityRecord(
                        provider: .smc,
                        rawKey: key,
                        registryID: nil,
                        intendedKind: .cpuZone,
                        capability: .failed,
                        reason: "missing_profile_cpu_key"
                    )
                )
                continue
            }
            if matches.count > 1 {
                unavailable.append(
                    SourceCapabilityRecord(
                        provider: .smc,
                        rawKey: key,
                        registryID: nil,
                        intendedKind: .cpuZone,
                        capability: .failed,
                        reason: "duplicate_profile_cpu_key"
                    )
                )
                continue
            }

            let discovered = matches[0]
            if discovered.encoding != profile.expectedSMCEncoding
                || discovered.byteCount != profile.expectedSMCSizeBytes
            {
                unavailable.append(
                    SourceCapabilityRecord(
                        provider: .smc,
                        rawKey: key,
                        registryID: discovered.registryID,
                        intendedKind: .cpuZone,
                        capability: .unsupported,
                        reason: "encoding_or_length_mismatch"
                    )
                )
                continue
            }

            guard let sourceID = try? cpuSourceID(keyIndex: index) else {
                continue
            }

            available.append(
                QualifiedSource(
                    sourceID: sourceID,
                    transportHandle: discovered.transportHandle,
                    provider: discovered.provider,
                    rawKey: discovered.rawKey,
                    registryID: discovered.registryID,
                    connectionGeneration: catalog.generation,
                    kind: .cpuZone,
                    encoding: discovered.encoding,
                    unitEvidence: profile.cpuSemanticEvidence,
                    evidence: .targetQualified,
                    mappingVersion: mappingVersion
                )
            )
        }
    }

    private func recordHIDDiagnostics(
        from catalog: DiscoveredCatalog,
        unavailable: inout [SourceCapabilityRecord]
    ) {
        guard !profile.automaticHIDFallback else {
            return
        }
        for source in catalog.sources where source.provider == .hid {
            unavailable.append(
                SourceCapabilityRecord(
                    provider: .hid,
                    rawKey: source.rawKey,
                    registryID: source.registryID,
                    intendedKind: .cpuZone,
                    capability: .unsupported,
                    reason: "hid_diagnostic_only"
                )
            )
        }
    }

    private func cpuSourceID(keyIndex: Int) throws -> SourceID {
        try SourceID(validating: String(format: "00000000-0000-4000-8000-%012d", keyIndex + 1))
    }

    public func sourceID(forRegistryID registryID: String) throws -> SourceID {
        try SourceID(validating: registryID)
    }
}
