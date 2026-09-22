import Foundation
import Testing
@testable import TemperatureCore

@Suite struct EMAProcessorTests {
    @Test func emaUsesActualElapsedTime() async throws {
        let fixture = try await ProcessorFixture.make()
        let aID = RequestID(Fixtures.uuid(201))
        let bID = RequestID(Fixtures.uuid(202))
        let cID = RequestID(Fixtures.uuid(203))
        let ar = fixture.lease(owner: .request(aID), generation: 1)
        let br = fixture.lease(owner: .request(bID), generation: 1)
        let cr = fixture.lease(owner: .request(cID), generation: 1)
        let arx = try await fixture.accept(Fixtures.read(id: aID, ms: 0, values: [80]), lease: ar)
        let brx = try await fixture.accept(Fixtures.read(id: bID, ms: 500, values: [100]), lease: br)
        let crx = try await fixture.accept(Fixtures.read(id: cID, ms: 1000, values: [100]), lease: cr)
        let a = try #require(await fixture.committedBatch(for: arx))
        let b = try #require(await fixture.committedBatch(for: brx))
        let c = try #require(await fixture.committedBatch(for: crx))
        #expect(a.ema.first?.valueC == 80)
        #expect(abs(try #require(b.ema.first).valueC - 92.6424111766) < 1e-8)
        #expect(abs(try #require(c.ema.first).valueC - 97.2932943353) < 1e-8)
    }

    @Test func rejectsNonPositiveDeltaTime() throws {
        let processor = EMAProcessor(tauSeconds: try Configuration.bundledDefaults().emaTauSeconds)
        let timestamp = Fixtures.timestamp(ms: 100)
        let raw = Sample(
            sampleID: "fixture-session:1",
            seriesID: SeriesID(Fixtures.uuid(101)),
            segment: 1,
            timestamp: timestamp,
            periodMS: 200,
            valueC: 80,
            freshness: .unknown,
            sourceWallUnixNS: nil,
            memberSampleIDs: []
        )
        let previous = EMAValue(
            sampleID: "fixture-session:0",
            seriesID: SeriesID(Fixtures.uuid(101)),
            segment: 1,
            timestamp: timestamp,
            valueC: 70
        )

        do {
            _ = try processor.nextEMA(raw: raw, previous: previous, kind: .cpuZone)
            Issue.record("expected non-positive dt failure")
        } catch EMAError.nonPositiveDeltaTime {
        }
    }
}
