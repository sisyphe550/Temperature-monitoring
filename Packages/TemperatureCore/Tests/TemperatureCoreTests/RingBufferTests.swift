import Foundation
import Testing
@testable import TemperatureCore

@Suite struct RingBufferTests {
    @Test func retainsSamplesWithinThreeHundredSecondWindow() {
        let config = RingBufferConfiguration(capacity: 8192, retentionSeconds: 300)
        var buffer = RingBufferStore(configuration: config, maxActiveSeries: 32)
        let seriesID = SeriesID(Fixtures.uuid(101))
        let intervalNS: Int64 = 50_000_000

        for index in 0..<7000 {
            let elapsed = Int64(index) * intervalNS
            let sample = sample(atMS: elapsed / 1_000_000, seriesID: seriesID, value: Double(index))
            try? buffer.appendRaw(sample, nowElapsedNS: elapsed)
        }

        let now = 7000 * intervalNS
        let visible = buffer.rawSamples(for: seriesID, nowElapsedNS: now)
        #expect(visible.count == 5999)
        #expect(visible.first?.timestamp.elapsedNS == 1001 * intervalNS)
        #expect(visible.last?.timestamp.elapsedNS == 6999 * intervalNS)
    }

    @Test func enforcesCapacityAfterWindowPrune() {
        let config = RingBufferConfiguration(capacity: 8, retentionSeconds: 300)
        var buffer = RingBufferStore(configuration: config, maxActiveSeries: 32)
        let seriesID = SeriesID(Fixtures.uuid(102))

        for index in 0..<12 {
            let elapsed = Int64(index) * 10_000_000
            try? buffer.appendRaw(
                sample(atMS: elapsed / 1_000_000, seriesID: seriesID, value: Double(index)),
                nowElapsedNS: elapsed
            )
        }

        let visible = buffer.rawSamples(for: seriesID, nowElapsedNS: 110_000_000)
        #expect(visible.count == 8)
        #expect(visible.first?.valueC == 4)
        #expect(visible.last?.valueC == 11)
    }

    @Test func rejectsThirtyThirdActiveSeries() throws {
        let config = RingBufferConfiguration(capacity: 8192, retentionSeconds: 300)
        var buffer = RingBufferStore(configuration: config, maxActiveSeries: 32)

        for index in 0..<32 {
            let seriesID = SeriesID(Fixtures.uuid(200 + index))
            try buffer.registerSeries(seriesID)
        }

        do {
            try buffer.registerSeries(SeriesID(Fixtures.uuid(999)))
            Issue.record("expected series limit")
        } catch RingBufferError.seriesLimitExceeded {
        }
    }

    @Test func rawAndEMABuffersAreIndependent() throws {
        let config = RingBufferConfiguration(capacity: 4, retentionSeconds: 300)
        var buffer = RingBufferStore(configuration: config, maxActiveSeries: 32)
        let seriesID = SeriesID(Fixtures.uuid(103))
        let timestamp = Fixtures.timestamp(ms: 100)

        try buffer.appendRaw(
            Sample(
                sampleID: "fixture-session:1",
                seriesID: seriesID,
                segment: 1,
                timestamp: timestamp,
                periodMS: 200,
                valueC: 70,
                freshness: .unknown,
                sourceWallUnixNS: nil,
                memberSampleIDs: []
            ),
            nowElapsedNS: timestamp.elapsedNS
        )
        try buffer.appendEMA(
            EMAValue(
                sampleID: "fixture-session:1",
                seriesID: seriesID,
                segment: 1,
                timestamp: timestamp,
                valueC: 70
            ),
            nowElapsedNS: timestamp.elapsedNS
        )

        #expect(buffer.rawSamples(for: seriesID, nowElapsedNS: timestamp.elapsedNS).count == 1)
        #expect(buffer.emaSamples(for: seriesID, nowElapsedNS: timestamp.elapsedNS).count == 1)
    }
}

private func sample(atMS ms: Int64, seriesID: SeriesID, value: Double) -> Sample {
    Sample(
        sampleID: "fixture-session:\(ms)",
        seriesID: seriesID,
        segment: 1,
        timestamp: Fixtures.timestamp(ms: ms),
        periodMS: 200,
        valueC: value,
        freshness: .unknown,
        sourceWallUnixNS: nil,
        memberSampleIDs: []
    )
}
