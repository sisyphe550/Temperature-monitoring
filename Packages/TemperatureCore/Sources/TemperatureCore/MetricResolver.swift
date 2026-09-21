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
}
