import Foundation
import TemperatureCore

public protocol SystemThermalStateProviding: Sendable {
    func currentState() -> SystemThermalState
}

/// Reads macOS's whole-system state once per presentation update.
public struct ProcessInfoThermalStateProvider: SystemThermalStateProviding {
    private let readRawState: @Sendable () -> Int

    public init(readRawState: @escaping @Sendable () -> Int = { ProcessInfo.processInfo.thermalState.rawValue }) {
        self.readRawState = readRawState
    }

    public func currentState() -> SystemThermalState {
        guard let state = ProcessInfo.ThermalState(rawValue: readRawState()) else { return .unknown }
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}
