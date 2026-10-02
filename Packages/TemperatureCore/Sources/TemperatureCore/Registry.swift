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
                case .celsius(let value):
                    guard value.isFinite, value >= -273.15 else { continue }
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
        qualifyBatterySource(from: catalog, available: &available, unavailable: &unavailable)
        qualifySSDSource(from: catalog, available: &available, unavailable: &unavailable)
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

            guard let sourceID = try? cpuSourceID(keyIndex: index, generation: catalog.generation) else {
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

    private func qualifyBatterySource(
        from catalog: DiscoveredCatalog,
        available: inout [QualifiedSource],
        unavailable: inout [SourceCapabilityRecord]
    ) {
        var rejected: SourceCapabilityRecord?
        for entry in profile.batteryProviderPriority {
            let provider: ProviderKind
            let key: String
            if entry == "iops:Temperature" {
                provider = .iops
                key = "Temperature"
            } else if entry.hasPrefix("smc:") {
                provider = .smc
                key = String(entry.dropFirst(4))
            } else {
                continue
            }
            let matches = catalog.sources.filter { $0.provider == provider && $0.rawKey == key }
            if matches.count > 1 {
                unavailable.append(optionalFailure(
                    kind: .battery, provider: provider, rawKey: key,
                    capability: .mappingUnknown, reason: "duplicate_battery_provider"
                ))
                return
            }
            guard let source = matches.first else { continue }
            let expectedEncoding = provider == .iops ? "cfnumber_celsius" : profile.expectedSMCEncoding
            let expectedByteCount = provider == .iops ? 0 : profile.expectedSMCSizeBytes
            guard source.encoding == expectedEncoding, source.byteCount == expectedByteCount else {
                if rejected == nil {
                    rejected = optionalFailure(
                        kind: .battery, provider: provider, rawKey: key, registryID: source.registryID,
                        capability: .unsupported, reason: "battery_encoding_or_length_mismatch"
                    )
                }
                continue
            }
            guard !source.transportHandle.isEmpty,
                  catalog.sources.filter({ $0.transportHandle == source.transportHandle }).count == 1,
                  provider != .iops || source.registryID?.isEmpty == false else {
                if rejected == nil {
                    rejected = optionalFailure(
                        kind: .battery, provider: provider, rawKey: key, registryID: source.registryID,
                        capability: .mappingUnknown, reason: "battery_identity_missing_or_conflicting"
                    )
                }
                continue
            }
            let unitEvidence = provider == .iops
                ? "macOS SDK IOPSKeys.h kIOPSTemperatureKey: numeric CFNumber in Celsius; unique internal battery"
                : "Stats e31d279b battery-temperature classification; profile flt/4 bytes in Celsius"
            available.append(optionalSource(
                source, kind: .battery, generation: catalog.generation, unitEvidence: unitEvidence
            ))
            return
        }
        unavailable.append(rejected ?? optionalFailure(
            kind: .battery, provider: .iops, rawKey: "Temperature",
            capability: .unsupported, reason: "no_valid_battery_provider_in_priority_chain"
        ))
    }

    private func qualifySSDSource(
        from catalog: DiscoveredCatalog,
        available: inout [QualifiedSource],
        unavailable: inout [SourceCapabilityRecord]
    ) {
        let discovered = catalog.sources.filter { $0.provider == .nvme && $0.rawKey == "TEMPERATURE" }
        var candidates: [NVMeDiscoveryCandidate] = []
        for source in discovered {
            guard source.interconnectLookupStatus == .found,
                  let location = source.physicalInterconnectLocation,
                  !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !location.contains("\0") else {
                let reason: String
                switch source.interconnectLookupStatus {
                case .missingProperty: reason = "nvme_interconnect_property_missing"
                case .lookupFailed: reason = "nvme_interconnect_lookup_failed"
                case .found, nil: reason = "nvme_interconnect_facts_missing_or_invalid"
                }
                unavailable.append(optionalFailure(
                    kind: .ssd, provider: .nvme, rawKey: source.rawKey, registryID: source.registryID,
                    capability: .mappingUnknown, reason: reason
                ))
                return
            }
            guard let registryID = source.registryID, !registryID.isEmpty else {
                unavailable.append(optionalFailure(
                    kind: .ssd, provider: .nvme, rawKey: source.rawKey,
                    capability: .mappingUnknown, reason: "nvme_registry_identity_missing"
                ))
                return
            }
            candidates.append(NVMeDiscoveryCandidate(
                registryID: registryID, interconnectLocation: location, lookupStatus: .ok
            ))
        }
        switch Registry.selectInternalNVMe(candidates: candidates) {
        case .unavailable(let record):
            unavailable.append(record)
        case .selected(let selected):
            let matching = discovered.filter { $0.registryID == selected.registryID }
            guard matching.count == 1, let source = matching.first,
                  !source.transportHandle.isEmpty,
                  catalog.sources.filter({ $0.transportHandle == source.transportHandle }).count == 1 else {
                unavailable.append(optionalFailure(
                    kind: .ssd, provider: .nvme, rawKey: "TEMPERATURE", registryID: selected.registryID,
                    capability: .mappingUnknown, reason: "nvme_registry_identity_conflicting"
                ))
                return
            }
            guard source.encoding == "uint16_le_kelvin", source.byteCount == 2 else {
                unavailable.append(optionalFailure(
                    kind: .ssd, provider: .nvme, rawKey: source.rawKey, registryID: source.registryID,
                    capability: .unsupported, reason: "nvme_encoding_or_length_mismatch"
                ))
                return
            }
            available.append(optionalSource(
                source, kind: .ssd, generation: catalog.generation,
                unitEvidence: "macOS NVMeSMARTData TEMPERATURE: uint16 little-endian Kelvin; zero is not reported; unique Internal device composite"
            ))
        }
    }

    private func optionalSource(
        _ discovered: DiscoveredSource,
        kind: SensorKind,
        generation: UInt64,
        unitEvidence: String
    ) -> QualifiedSource {
        let identity = "\(mappingVersion)/\(discovered.registryID ?? discovered.transportHandle)/\(discovered.rawKey)"
        return QualifiedSource(
            sourceID: SourceID(ConnectionIdentity.uuid(
                role: "source.\(discovered.provider.rawValue).\(kind.rawValue)",
                generation: generation, identity: identity
            )),
            transportHandle: discovered.transportHandle,
            provider: discovered.provider,
            rawKey: discovered.rawKey,
            registryID: discovered.registryID,
            connectionGeneration: generation,
            kind: kind,
            encoding: discovered.encoding,
            unitEvidence: unitEvidence,
            evidence: .referenceClassified,
            mappingVersion: mappingVersion
        )
    }

    private func optionalFailure(
        kind: SensorKind,
        provider: ProviderKind,
        rawKey: String?,
        registryID: String? = nil,
        capability: Capability,
        reason: String
    ) -> SourceCapabilityRecord {
        SourceCapabilityRecord(
            provider: provider, rawKey: rawKey, registryID: registryID,
            intendedKind: kind, capability: capability, reason: reason
        )
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

    private func cpuSourceID(keyIndex: Int, generation: UInt64) throws -> SourceID {
        if generation == 1 {
            return try SourceID(validating: String(format: "00000000-0000-4000-8000-%012d", keyIndex + 1))
        }
        return SourceID(ConnectionIdentity.uuid(role: "source.smc.cpu", generation: generation, identity: "\(mappingVersion)/\(profile.cpuKeys[keyIndex])"))
    }

    public func sourceID(forRegistryID registryID: String) throws -> SourceID {
        try SourceID(validating: registryID)
    }
}
