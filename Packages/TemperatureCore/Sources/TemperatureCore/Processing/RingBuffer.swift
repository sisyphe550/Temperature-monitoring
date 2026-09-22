import Foundation

struct RingBufferConfiguration: Sendable, Equatable {
    let capacity: Int
    let retentionNS: Int64

    init(capacity: Int, retentionSeconds: Int64) {
        self.capacity = capacity
        self.retentionNS = retentionSeconds * 1_000_000_000
    }
}

struct RingBuffer<Element> {
    private(set) var elements: [Element] = []
    let configuration: RingBufferConfiguration
    let elapsedNS: (Element) -> Int64

    init(configuration: RingBufferConfiguration, elapsedNS: @escaping (Element) -> Int64) {
        self.configuration = configuration
        self.elapsedNS = elapsedNS
    }

    mutating func prune(nowElapsedNS: Int64) {
        let cutoff = nowElapsedNS - configuration.retentionNS
        elements.removeAll { elapsedNS($0) <= cutoff || elapsedNS($0) > nowElapsedNS }
    }

    mutating func append(_ element: Element, nowElapsedNS: Int64) {
        prune(nowElapsedNS: nowElapsedNS)
        if elements.count >= configuration.capacity {
            elements.removeFirst()
        }
        elements.append(element)
    }

    func visible(nowElapsedNS: Int64) -> [Element] {
        let cutoff = nowElapsedNS - configuration.retentionNS
        return elements.filter { elapsedNS($0) > cutoff && elapsedNS($0) <= nowElapsedNS }
    }

    var count: Int {
        elements.count
    }
}

struct SeriesBufferSet {
    var raw: RingBuffer<Sample>
    var ema: RingBuffer<EMAValue>

    init(configuration: RingBufferConfiguration) {
        raw = RingBuffer(configuration: configuration) { $0.timestamp.elapsedNS }
        ema = RingBuffer(configuration: configuration) { $0.timestamp.elapsedNS }
    }

    mutating func prune(nowElapsedNS: Int64) {
        raw.prune(nowElapsedNS: nowElapsedNS)
        ema.prune(nowElapsedNS: nowElapsedNS)
    }
}

struct RingBufferStore {
    private(set) var series: [SeriesID: SeriesBufferSet] = [:]
    let configuration: RingBufferConfiguration
    let maxActiveSeries: Int

    init(configuration: RingBufferConfiguration, maxActiveSeries: Int) {
        self.configuration = configuration
        self.maxActiveSeries = maxActiveSeries
    }

    var activeSeriesCount: Int {
        series.count
    }

    mutating func registerSeries(_ seriesID: SeriesID) throws {
        if series[seriesID] != nil {
            return
        }
        guard series.count < maxActiveSeries else {
            throw RingBufferError.seriesLimitExceeded
        }
        series[seriesID] = SeriesBufferSet(configuration: configuration)
    }

    mutating func appendRaw(_ sample: Sample, nowElapsedNS: Int64) throws {
        try registerSeries(sample.seriesID)
        series[sample.seriesID]?.raw.append(sample, nowElapsedNS: nowElapsedNS)
    }

    mutating func appendEMA(_ value: EMAValue, nowElapsedNS: Int64) throws {
        try registerSeries(value.seriesID)
        series[value.seriesID]?.ema.append(value, nowElapsedNS: nowElapsedNS)
    }

    func rawSamples(for seriesID: SeriesID, nowElapsedNS: Int64) -> [Sample] {
        series[seriesID]?.raw.visible(nowElapsedNS: nowElapsedNS) ?? []
    }

    func emaSamples(for seriesID: SeriesID, nowElapsedNS: Int64) -> [EMAValue] {
        series[seriesID]?.ema.visible(nowElapsedNS: nowElapsedNS) ?? []
    }

    mutating func prune(nowElapsedNS: Int64) {
        for key in series.keys {
            series[key]?.prune(nowElapsedNS: nowElapsedNS)
        }
    }
}

enum RingBufferError: Error, Sendable, Equatable {
    case seriesLimitExceeded
}
