import Foundation

enum GapDetector {
    static func isTimeoutGap(
        deltaElapsedNS: Int64,
        previousPeriodMS: Int,
        currentPeriodMS: Int,
        gapPeriodMultiplier: Int,
        gapFloorMS: Int
    ) -> Bool {
        let thresholdMS = max(
            gapPeriodMultiplier * max(previousPeriodMS, currentPeriodMS),
            gapFloorMS
        )
        return deltaElapsedNS > Int64(thresholdMS) * 1_000_000
    }
}

struct TrendCalculator {
    let trendWindowSeconds: KindSeconds
    let minPoints: Int
    let minCoverageFraction: Double
    let stableAbsCelsiusPerSecond: Double

    init(configuration: RuntimeConfiguration) {
        trendWindowSeconds = configuration.trendWindowSeconds
        minPoints = configuration.trendMinPoints
        minCoverageFraction = configuration.trendMinCoverageFraction
        stableAbsCelsiusPerSecond = configuration.trendStableAbsCelsiusPerSecond
    }

    func windowSeconds(for kind: SensorKind) -> Double {
        switch kind {
        case .cpuMain:
            trendWindowSeconds.cpuMain
        case .cpuZone:
            trendWindowSeconds.cpuZone
        case .ssd:
            trendWindowSeconds.ssd
        case .battery:
            trendWindowSeconds.battery
        }
    }

    func compute(
        seriesID: SeriesID,
        segment: Int64,
        kind: SensorKind,
        emaSamples: [EMAValue],
        at: Timestamp
    ) -> TrendValue {
        let windowNS = Int64(windowSeconds(for: kind) * 1_000_000_000)
        let windowStart = at.elapsedNS - windowNS
        let points = emaSamples
            .filter { sample in
                sample.seriesID == seriesID
                    && sample.segment == segment
                    && sample.timestamp.elapsedNS > windowStart
                    && sample.timestamp.elapsedNS <= at.elapsedNS
            }
            .sorted { $0.timestamp.elapsedNS < $1.timestamp.elapsedNS }

        guard points.count >= minPoints else {
            return TrendValue(
                seriesID: seriesID,
                segment: segment,
                at: at,
                slopeCPerSecond: nil,
                direction: .insufficient,
                pointCount: points.count
            )
        }

        let coverageNS = points[points.count - 1].timestamp.elapsedNS - points[0].timestamp.elapsedNS
        guard Double(coverageNS) / Double(windowNS) >= minCoverageFraction else {
            return TrendValue(
                seriesID: seriesID,
                segment: segment,
                at: at,
                slopeCPerSecond: nil,
                direction: .insufficient,
                pointCount: points.count
            )
        }

        guard let slope = linearSlope(points: points) else {
            return TrendValue(
                seriesID: seriesID,
                segment: segment,
                at: at,
                slopeCPerSecond: nil,
                direction: .insufficient,
                pointCount: points.count
            )
        }

        let direction: TrendDirection
        let stableBand = stableAbsCelsiusPerSecond + 1e-9
        if abs(slope) <= stableBand {
            direction = .stable
        } else if slope > 0 {
            direction = .rising
        } else {
            direction = .falling
        }

        return TrendValue(
            seriesID: seriesID,
            segment: segment,
            at: at,
            slopeCPerSecond: slope,
            direction: direction,
            pointCount: points.count
        )
    }

    private func linearSlope(points: [EMAValue]) -> Double? {
        guard points.count >= 2 else {
            return nil
        }
        let origin = points[0].timestamp.elapsedNS
        var sumT = 0.0
        var sumY = 0.0
        var sumTT = 0.0
        var sumTY = 0.0
        let count = Double(points.count)
        for point in points {
            let t = Double(point.timestamp.elapsedNS - origin) / 1_000_000_000
            let y = point.valueC
            sumT += t
            sumY += y
            sumTT += t * t
            sumTY += t * y
        }
        let denominator = count * sumTT - sumT * sumT
        guard denominator > 0 else {
            return nil
        }
        return (count * sumTY - sumT * sumY) / denominator
    }
}
