import Foundation
import Testing
@testable import SensorRuntime
import TemperatureCore

@Suite(.serialized) struct SessionClockRegressionTests {
    @Test func realWorkerKeepsParentClockOriginAcrossConnectionRestart() async throws {
        let clock = SystemClock()
        try await Task.sleep(for: .milliseconds(100))
        let client = WorkerClient(configuration: WorkerClientConfiguration(executableURL: try workerURL(), environment: ["TEMPERATURE_MONITOR_ORIGIN_TICKS": String(clock.basis.originTicks)]))
        var previous: Int64 = 0
        for _ in 0..<2 {
            let catalog = try await client.discoverRaw()
            let before = clock.now().elapsedNS
            // Unknown handles still traverse the production worker and have real
            // read timestamps. This does not require a sensor or claim hardware QA.
            let batch = try await client.readRaw(TransportReadRequest(requestID: RequestID(UUID()), generation: catalog.generation, transportHandles: ["clock-test:unknown"], requestedPeriodMS: 200))
            let reading = try #require(batch.readings.first)
            #expect(reading.started.elapsedNS >= before)
            #expect(reading.finished.elapsedNS <= clock.now().elapsedNS)
            #expect(reading.finished.elapsedNS > previous)
            previous = reading.finished.elapsedNS
            await client.releaseConnection()
            try await Task.sleep(for: .milliseconds(50))
        }
        await client.close()
    }

    @Test func malformedOrFutureParentOriginRejectsWorkerStartup() async throws {
        for origin in ["invalid", String(UInt64.max)] {
            let client = WorkerClient(configuration: WorkerClientConfiguration(executableURL: try workerURL(), environment: ["TEMPERATURE_MONITOR_ORIGIN_TICKS": origin]))
            do { _ = try await client.discoverRaw(); Issue.record("worker accepted invalid parent clock") }
            catch let failure as MonitorFailure { #expect(failure.code == .sensorProtocol) }
            await client.close()
        }
    }

    private func workerURL() throws -> URL {
        let fixture = try WorkerTestSupport.protocolWorkerURL()
        let url = fixture.deletingLastPathComponent().appendingPathComponent("SensorWorker")
        try #require(FileManager.default.isExecutableFile(atPath: url.path))
        return url
    }
}
