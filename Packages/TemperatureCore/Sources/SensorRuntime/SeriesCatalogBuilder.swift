import Foundation
import TemperatureCore

enum SeriesCatalogBuilder {
    static func definitions(from catalog: QualifiedSourceCatalog) throws -> [SeriesDefinition] {
        guard catalog.generation > 0, catalog.generation <= UInt64(Int.max) else {
            throw MonitorFailure(code: .sensorTag, severity: .fatal, component: "SeriesCatalogBuilder", operation: "generation", retryCount: 0, sourceID: nil, underlyingCode: "invalid_generation")
        }
        var definitions: [SeriesDefinition] = []
        let cpuZones = catalog.available.filter { $0.kind == .cpuZone }
        let cpuSourceIDs = cpuZones.map(\.sourceID)
        let failedRequired = catalog.unavailable.contains {
            $0.provider == .smc && $0.intendedKind == .cpuZone
        }
        let profileSources = cpuZones.filter { $0.mappingVersion == "mac16-13-v1" }
        let expectedKeys = Set(try Configuration.bundledProfile().cpuKeys)
        guard !cpuZones.isEmpty, !failedRequired,
              Set(cpuSourceIDs).count == cpuSourceIDs.count,
              profileSources.isEmpty || Set(profileSources.map(\.rawKey)) == expectedKeys else {
            throw MonitorFailure(code: .sensorDiscover, severity: .fatal, component: "SeriesCatalogBuilder",
                operation: "requiredCPU", retryCount: 0, sourceID: nil, underlyingCode: "incomplete_required_cpu_set")
        }

        for (index, source) in cpuZones.enumerated() {
            let seriesID = try SeriesID(validating: source.sourceID.rawValue)
            definitions.append(
                SeriesDefinition(
                    seriesID: seriesID,
                    metricID: try MetricID(validating: "cpu.zone.\(index + 1)"),
                    definitionVersion: Int(catalog.generation),
                    kind: .cpuZone,
                    displayName: source.rawKey,
                    memberSourceIDs: [source.sourceID],
                    formula: .identity
                )
            )
        }

        if cpuSourceIDs.count > 1 {
            let maxSeriesID = catalog.generation == 1
                ? try SeriesID(validating: "00000000-0000-4000-8000-000000000200")
                : SeriesID(ConnectionIdentity.uuid(role: "series.cpu.zone.max", generation: catalog.generation,
                    identity: cpuSourceIDs.map(\.rawValue).sorted().joined(separator: ",")))
            definitions.append(
                SeriesDefinition(seriesID: maxSeriesID, metricID: try MetricResolver.cpuZoneMaximumMetricID(),
                    definitionVersion: Int(catalog.generation), kind: .cpuMain, displayName: "CPU热区最高温度",
                    memberSourceIDs: cpuSourceIDs, formula: .maximum)
            )
        }

        for source in catalog.available where source.kind == .ssd {
            let seriesID = try SeriesID(validating: source.sourceID.rawValue)
            definitions.append(
                SeriesDefinition(
                    seriesID: seriesID,
                    metricID: try MetricID(validating: "storage.ssd"),
                    definitionVersion: Int(catalog.generation),
                    kind: .ssd,
                    displayName: source.rawKey,
                    memberSourceIDs: [source.sourceID],
                    formula: .identity
                )
            )
        }

        for source in catalog.available where source.kind == .battery {
            let seriesID = try SeriesID(validating: source.sourceID.rawValue)
            definitions.append(
                SeriesDefinition(
                    seriesID: seriesID,
                    metricID: try MetricID(validating: "power.battery"),
                    definitionVersion: Int(catalog.generation),
                    kind: .battery,
                    displayName: source.rawKey,
                    memberSourceIDs: [source.sourceID],
                    formula: .identity
                )
            )
        }

        return definitions
    }
    static func unavailableValues(from catalog: QualifiedSourceCatalog) throws -> [LatestValue] {
        try [SensorKind.ssd, .battery].compactMap { kind in
            guard !catalog.available.contains(where: { $0.kind == kind }),
                  let record = catalog.unavailable.first(where: { $0.intendedKind == kind }) else { return nil }
            let metric = kind == .ssd ? "storage.ssd" : "power.battery"
            let definition = SeriesDefinition(seriesID: SeriesID(ConnectionIdentity.uuid(role: "capability", generation: catalog.generation, identity: metric)),
                metricID: try MetricID(validating: metric), definitionVersion: Int(catalog.generation), kind: kind,
                displayName: kind == .ssd ? "SSD温度" : "电池温度", memberSourceIDs: [], formula: .identity)
            return LatestValue(definition: definition, state: .unavailable(capability: record.capability, reason: record.reason))
        }
    }

}
