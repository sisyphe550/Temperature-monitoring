import Foundation

public enum MetricResolver {
    public static func cpuZoneMaximumMetricID() throws -> MetricID {
        try MetricID(validating: "cpu.zone.max")
    }

    public static func seriesMetricIDs(for members: [QualifiedSource]) throws -> [MetricID] {
        guard !members.isEmpty else {
            return []
        }
        guard members.allSatisfy({ $0.kind == .cpuZone }) else {
            return []
        }
        return [try cpuZoneMaximumMetricID()]
    }

    public static func infersPhysicalCoreCount(from memberCount: Int) -> Int? {
        nil
    }

    public static func makeCPUMaximumDefinition(
        seriesID: SeriesID,
        memberSourceIDs: [SourceID],
        displayName: String = "CPU热区最高温度"
    ) throws -> SeriesDefinition {
        SeriesDefinition(
            seriesID: seriesID,
            metricID: try cpuZoneMaximumMetricID(),
            definitionVersion: 1,
            kind: .cpuMain,
            displayName: displayName,
            memberSourceIDs: memberSourceIDs,
            formula: .maximum
        )
    }

    public static func makeCPUZoneIdentityDefinition(
        seriesID: SeriesID,
        sourceID: SourceID,
        displayName: String
    ) throws -> SeriesDefinition {
        SeriesDefinition(
            seriesID: seriesID,
            metricID: try MetricID(validating: "fixture.cpu.zone"),
            definitionVersion: 1,
            kind: .cpuZone,
            displayName: displayName,
            memberSourceIDs: [sourceID],
            formula: .identity
        )
    }
}
