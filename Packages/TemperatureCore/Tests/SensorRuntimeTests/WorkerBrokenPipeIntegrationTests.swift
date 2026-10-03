import Darwin
import Foundation
import Testing
import SensorRuntime
import TemperatureCore

@Suite(.serialized) struct WorkerBrokenPipeIntegrationTests {
    @Test func publicClientMapsClosedWorkerInputToProtocolFailureAndReapsChild() async throws {
        var disposition = sigaction()
        try #require(sigaction(SIGPIPE, nil, &disposition) == 0)
        try #require(disposition.__sigaction_u.__sa_handler == nil)
        let client = try WorkerTestSupport.client(scenario: "closedInputAfterDiscover", timeouts: WorkerClientTimeouts(readDeadlineMS: 1_000, discoverDeadlineMS: 5_000, terminateGraceMS: 100))
        do {
            let catalog = try await client.discoverRaw()
            let childPID = try #require(await client.childProcessID)
            // The fixture closes stdin before writing this catalog, so readRaw
            // deterministically meets a closed reader through production spawn/IO.
            do {
                _ = try await client.readRaw(TransportReadRequest(
                    requestID: RequestID(UUID()), generation: catalog.generation,
                    transportHandles: ["smc:Tp01"], requestedPeriodMS: 200
                ))
                Issue.record("expected protocol failure from closed worker input")
            } catch let failure as MonitorFailure {
                #expect(failure.code == .sensorProtocol)
                #expect(failure.underlyingCode == "exit")
            }
            #expect(await client.childProcessID == nil)
            let status = kill(childPID, 0)
            let savedErrno = errno
            #expect(status == -1)
            #expect(savedErrno == ESRCH)
            await client.close()
        } catch {
            await client.close()
            throw error
        }
    }

    @Test func immediateExitWorkerIsReportedWithoutTerminatingParent() async throws {
        for _ in 0..<16 {
            let client = WorkerClient(configuration: WorkerClientConfiguration(
                executableURL: URL(fileURLWithPath: "/usr/bin/false"),
                timeouts: WorkerTestSupport.fastTimeouts
            ))
            do { _ = try await client.discoverRaw(); Issue.record("expected early worker exit") }
            catch let failure as MonitorFailure { #expect(failure.code == .sensorProtocol) }
            await client.close()
        }
    }
}
