import Foundation

struct AggregationKey: Hashable, Sendable {
    let seriesID: SeriesID
    let segment: Int64
}

enum AggregationWindow {
    static let oneSecondNS: Int64 = 1_000_000_000
    static let tenSecondsNS: Int64 = 10 * oneSecondNS
    static let sixtySecondsNS: Int64 = 60 * oneSecondNS

    static func index(elapsedNS: Int64, widthNS: Int64) -> Int64 {
        max(0, elapsedNS / widthNS)
    }

    static func start(forIndex index: Int64, widthNS: Int64) -> Int64 {
        index * widthNS
    }

    static func end(forIndex index: Int64, widthNS: Int64) -> Int64 {
        (index + 1) * widthNS
    }
}

struct RawBucketBuilder {
    let seriesID: SeriesID
    let segment: Int64
    let startElapsedNS: Int64
    let endElapsedNS: Int64
    private(set) var samples: [Sample] = []

    mutating func add(_ sample: Sample) {
        samples.append(sample)
    }

    func build() -> Bucket? {
        guard !samples.isEmpty else {
            return nil
        }
        let sorted = samples.sorted {
            if $0.timestamp.elapsedNS == $1.timestamp.elapsedNS {
                return $0.sampleID < $1.sampleID
            }
            return $0.timestamp.elapsedNS < $1.timestamp.elapsedNS
        }
        let minC = sorted.map(\.valueC).min() ?? 0
        let maxC = sorted.map(\.valueC).max() ?? 0
        let sumC = sorted.reduce(into: 0.0) { $0 += $1.valueC }
        let count = Int64(sorted.count)
        let latest = sorted.max { lhs, rhs in
            if lhs.timestamp.elapsedNS == rhs.timestamp.elapsedNS {
                return lhs.sampleID < rhs.sampleID
            }
            return lhs.timestamp.elapsedNS < rhs.timestamp.elapsedNS
        } ?? sorted[sorted.count - 1]
        let widthNS = endElapsedNS - startElapsedNS
        let coverageNS = BucketCoverage.unionCoverage(
            samples: sorted,
            windowEndNS: endElapsedNS
        )
        return Bucket(
            seriesID: seriesID,
            segment: segment,
            widthSeconds: Int(widthNS / AggregationWindow.oneSecondNS),
            startElapsedNS: startElapsedNS,
            endElapsedNS: endElapsedNS,
            minC: minC,
            maxC: maxC,
            sumC: sumC,
            count: count,
            latestC: latest.valueC,
            latestElapsedNS: latest.timestamp.elapsedNS,
            latestSampleID: latest.sampleID,
            isPartial: coverageNS < widthNS,
            coverageNS: coverageNS
        )
    }
}

enum BucketCoverage {
    static func unionCoverage(samples: [Sample], windowEndNS: Int64) -> Int64 {
        let sorted = samples.sorted { $0.timestamp.elapsedNS < $1.timestamp.elapsedNS }
        var total: Int64 = 0
        for (index, sample) in sorted.enumerated() {
            let start = sample.timestamp.elapsedNS
            let periodEnd = start + Int64(sample.periodMS) * 1_000_000
            let nextStart = index + 1 < sorted.count
                ? sorted[index + 1].timestamp.elapsedNS
                : windowEndNS
            let end = min(windowEndNS, periodEnd, nextStart)
            if end > start {
                total += end - start
            }
        }
        return total
    }
}

enum BucketMerger {
    static func merge(
        children: [Bucket],
        widthSeconds: Int,
        startElapsedNS: Int64,
        endElapsedNS: Int64
    ) -> Bucket? {
        guard !children.isEmpty else {
            return nil
        }
        let seriesID = children[0].seriesID
        let segment = children[0].segment
        let minC = children.map(\.minC).min() ?? 0
        let maxC = children.map(\.maxC).max() ?? 0
        let sumC = children.reduce(into: 0.0) { $0 += $1.sumC }
        let count = children.reduce(into: Int64(0)) { $0 += $1.count }
        let latest = children.max { lhs, rhs in
            if lhs.latestElapsedNS == rhs.latestElapsedNS {
                return lhs.latestSampleID < rhs.latestSampleID
            }
            return lhs.latestElapsedNS < rhs.latestElapsedNS
        } ?? children[children.count - 1]
        let widthNS = endElapsedNS - startElapsedNS
        let coverageNS = min(widthNS, children.reduce(into: Int64(0)) { $0 += $1.coverageNS })
        let isPartial = children.contains(where: \.isPartial) || coverageNS < widthNS
        return Bucket(
            seriesID: seriesID,
            segment: segment,
            widthSeconds: widthSeconds,
            startElapsedNS: startElapsedNS,
            endElapsedNS: endElapsedNS,
            minC: minC,
            maxC: maxC,
            sumC: sumC,
            count: count,
            latestC: latest.latestC,
            latestElapsedNS: latest.latestElapsedNS,
            latestSampleID: latest.latestSampleID,
            isPartial: isPartial,
            coverageNS: coverageNS
        )
    }
}

struct SeriesAggregationState {
    var openOneSecond: [Int64: RawBucketBuilder] = [:]
    var openTenSeconds: [Int64: [Bucket]] = [:]
    var openSixtySeconds: [Int64: [Bucket]] = [:]
}

struct AggregationEngine {
    private var states: [AggregationKey: SeriesAggregationState] = [:]
    private var inFlightStartElapsedNS: [Int64] = []

    mutating func beginInFlight(startElapsedNS: [Int64]) {
        inFlightStartElapsedNS.append(contentsOf: startElapsedNS)
    }

    mutating func endInFlight(startElapsedNS: [Int64]) {
        for start in startElapsedNS {
            if let index = inFlightStartElapsedNS.firstIndex(of: start) {
                inFlightStartElapsedNS.remove(at: index)
            }
        }
    }

    mutating func ingest(_ sample: Sample) {
        let key = AggregationKey(seriesID: sample.seriesID, segment: sample.segment)
        var state = states[key] ?? SeriesAggregationState()
        let windowIndex = AggregationWindow.index(
            elapsedNS: sample.timestamp.elapsedNS,
            widthNS: AggregationWindow.oneSecondNS
        )
        let start = AggregationWindow.start(forIndex: windowIndex, widthNS: AggregationWindow.oneSecondNS)
        let end = AggregationWindow.end(forIndex: windowIndex, widthNS: AggregationWindow.oneSecondNS)
        var builder = state.openOneSecond[windowIndex] ?? RawBucketBuilder(
            seriesID: sample.seriesID,
            segment: sample.segment,
            startElapsedNS: start,
            endElapsedNS: end
        )
        builder.add(sample)
        state.openOneSecond[windowIndex] = builder
        states[key] = state
    }

    mutating func advance(to watermarkElapsedNS: Int64) -> [Bucket] {
        var closed: [Bucket] = []
        for key in states.keys {
            closed.append(contentsOf: closeWindows(for: key, watermarkElapsedNS: watermarkElapsedNS))
        }
        return closed.sorted {
            if $0.startElapsedNS == $1.startElapsedNS {
                return $0.widthSeconds < $1.widthSeconds
            }
            return $0.startElapsedNS < $1.startElapsedNS
        }
    }

    private mutating func closeWindows(for key: AggregationKey, watermarkElapsedNS: Int64) -> [Bucket] {
        guard var state = states[key] else {
            return []
        }
        var closed: [Bucket] = []

        let closableOneSecond = state.openOneSecond.keys.sorted().filter { windowIndex in
            let end = AggregationWindow.end(forIndex: windowIndex, widthNS: AggregationWindow.oneSecondNS)
            return end <= watermarkElapsedNS && !blocksClosure(until: end)
        }
        for windowIndex in closableOneSecond {
            guard let builder = state.openOneSecond.removeValue(forKey: windowIndex),
                  let bucket = builder.build()
            else {
                state.openOneSecond.removeValue(forKey: windowIndex)
                continue
            }
            closed.append(bucket)
            let parentIndex = AggregationWindow.index(
                elapsedNS: bucket.startElapsedNS,
                widthNS: AggregationWindow.tenSecondsNS
            )
            state.openTenSeconds[parentIndex, default: []].append(bucket)
        }

        let closableTenSeconds = state.openTenSeconds.keys.sorted().filter { windowIndex in
            let end = AggregationWindow.end(forIndex: windowIndex, widthNS: AggregationWindow.tenSecondsNS)
            return end <= watermarkElapsedNS && !blocksClosure(until: end)
        }
        for windowIndex in closableTenSeconds {
            let children = state.openTenSeconds.removeValue(forKey: windowIndex) ?? []
            let start = AggregationWindow.start(forIndex: windowIndex, widthNS: AggregationWindow.tenSecondsNS)
            let end = AggregationWindow.end(forIndex: windowIndex, widthNS: AggregationWindow.tenSecondsNS)
            if let bucket = BucketMerger.merge(
                children: children,
                widthSeconds: 10,
                startElapsedNS: start,
                endElapsedNS: end
            ) {
                closed.append(bucket)
                let parentIndex = AggregationWindow.index(
                    elapsedNS: bucket.startElapsedNS,
                    widthNS: AggregationWindow.sixtySecondsNS
                )
                state.openSixtySeconds[parentIndex, default: []].append(bucket)
            }
        }

        let closableSixtySeconds = state.openSixtySeconds.keys.sorted().filter { windowIndex in
            let end = AggregationWindow.end(forIndex: windowIndex, widthNS: AggregationWindow.sixtySecondsNS)
            return end <= watermarkElapsedNS && !blocksClosure(until: end)
        }
        for windowIndex in closableSixtySeconds {
            let children = state.openSixtySeconds.removeValue(forKey: windowIndex) ?? []
            let start = AggregationWindow.start(forIndex: windowIndex, widthNS: AggregationWindow.sixtySecondsNS)
            let end = AggregationWindow.end(forIndex: windowIndex, widthNS: AggregationWindow.sixtySecondsNS)
            if let bucket = BucketMerger.merge(
                children: children,
                widthSeconds: 60,
                startElapsedNS: start,
                endElapsedNS: end
            ) {
                closed.append(bucket)
            }
        }

        states[key] = state
        return closed
    }

    private func blocksClosure(until windowEndNS: Int64) -> Bool {
        inFlightStartElapsedNS.contains { $0 < windowEndNS }
    }

    func activeInFlightStarts() -> [Int64] {
        inFlightStartElapsedNS
    }
}
