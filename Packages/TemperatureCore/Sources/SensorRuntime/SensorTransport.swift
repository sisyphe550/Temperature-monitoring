import Foundation
import TemperatureCore

public protocol SensorTransport: Sendable {
    func discoverRaw() async throws -> DiscoveredCatalog
    func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch
    func close() async
}
