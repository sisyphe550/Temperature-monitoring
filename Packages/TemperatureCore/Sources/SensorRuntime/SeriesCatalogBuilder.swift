import Foundation
import TemperatureCore

enum SeriesCatalogBuilder {
    static func definitions(from catalog: QualifiedSourceCatalog) throws -> [SeriesDefinition] {
        var definitions: [SeriesDefinition] = []
        let cpuZones = catalog.available.filter { $0.kind == .cpuZone }
        let cpuSourceIDs = cpuZones.map(\.sourceID)

        for (index, source) in cpuZones.enumerated() {
            let seriesID = try SeriesID(validating: source.sourceID.rawValue)
            definitions.append(
                SeriesDefinition(
                    seriesID: seriesID,
                    metricID: try MetricID(validating: "cpu.zone.\(index + 1)"),
                    definitionVersion: 1,
                    kind: .cpuZone,
                    displayName: source.rawKey,
                    memberSourceIDs: [source.sourceID],
                    formula: .identity
                )
            )
        }

        if cpuSourceIDs.count > 1 {
            let maxSeriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000200")
            definitions.append(
                try MetricResolver.makeCPUMaximumDefinition(
                    seriesID: maxSeriesID,
                    memberSourceIDs: cpuSourceIDs
                )
            )
        }

        for source in catalog.available where source.kind == .ssd {
            let seriesID = try SeriesID(validating: source.sourceID.rawValue)
            definitions.append(
                SeriesDefinition(
                    seriesID: seriesID,
                    metricID: try MetricID(validating: "storage.ssd"),
                    definitionVersion: 1,
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
                    definitionVersion: 1,
                    kind: .battery,
                    displayName: source.rawKey,
                    memberSourceIDs: [source.sourceID],
                    formula: .identity
                )
            )
        }

        return definitions
    }
}
