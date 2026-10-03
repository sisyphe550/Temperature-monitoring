import Darwin
import Foundation
import Testing
@testable import SensorRuntime

@Suite(.serialized) struct WorkerPipeWriteTests {
    @Test func closedReaderThrowsWithoutChangingGlobalSignalDispositionOrOtherPipe() throws {
        var dispositionBefore = sigaction()
        try #require(sigaction(SIGPIPE, nil, &dispositionBefore) == 0)
        try #require(dispositionBefore.__sigaction_u.__sa_handler == nil)
        let pipe = Pipe()
        let other = Pipe()
        defer {
            try? pipe.fileHandleForWriting.close()
            try? other.fileHandleForReading.close()
            try? other.fileHandleForWriting.close()
        }
        let descriptor = pipe.fileHandleForWriting.fileDescriptor
        #expect(fcntl(descriptor, F_GETNOSIGPIPE) == 0)
        #expect(fcntl(other.fileHandleForWriting.fileDescriptor, F_GETNOSIGPIPE) == 0)
        try WorkerClient.configureRequestPipe(descriptor: descriptor)
        try pipe.fileHandleForReading.close()
        #expect(throws: WorkerClientError.workerExitedUnexpectedly) {
            try WorkerClient.writeRequest(Data("broken reader".utf8), to: pipe.fileHandleForWriting)
        }
        #expect(fcntl(descriptor, F_GETNOSIGPIPE) == 1)
        #expect(fcntl(other.fileHandleForWriting.fileDescriptor, F_GETNOSIGPIPE) == 0)
        var dispositionAfter = sigaction()
        try #require(sigaction(SIGPIPE, nil, &dispositionAfter) == 0)
        #expect(dispositionAfter.__sigaction_u.__sa_handler == nil)
        #expect(dispositionAfter.sa_flags == dispositionBefore.sa_flags)
    }

    @Test func successfulWriteKeepsCompleteNewlineDelimitedFrame() throws {
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        try WorkerClient.configureRequestPipe(descriptor: pipe.fileHandleForWriting.fileDescriptor)
        try WorkerClient.writeRequest(Data("{\"command\":\"discover\"}".utf8), to: pipe.fileHandleForWriting)
        let received = try #require(try pipe.fileHandleForReading.read(upToCount: 23))
        #expect(received == Data("{\"command\":\"discover\"}\n".utf8))
    }

    @Test func invalidDescriptorReportsFlagSetupFailure() {
        #expect(throws: POSIXError(.EBADF)) {
            try WorkerClient.configureRequestPipe(descriptor: -1)
        }
    }

    @Test func alreadyClosedFileHandleWriteThrowsSwiftError() throws {
        let pipe = Pipe()
        try pipe.fileHandleForReading.close()
        try pipe.fileHandleForWriting.close()
        #expect(throws: (any Error).self) {
            try WorkerClient.writeRequest(Data("closed".utf8), to: pipe.fileHandleForWriting)
        }
    }
}
