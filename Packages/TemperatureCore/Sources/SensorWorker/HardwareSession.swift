import Foundation
import IOKit.ps
import SensorBridge
import TemperatureCore

final class HardwareSession {
    private struct SMCKeyInfo {
        let key: UInt32
        let encoding: String
        let byteCount: Int
    }

    private struct HIDServiceInfo {
        let index: Int32
        let productName: String
        let registryID: String
    }

    private struct NVMeDeviceInfo {
        let index: Int32
        let registryID: String
    }

    private var smcConnection: UInt32 = 0
    private var hidProbe: OpaquePointer?
    private var nvmeProbe: OpaquePointer?
    private var smcKeys: [String: SMCKeyInfo] = [:]
    private var hidServices: [HIDServiceInfo] = []
    private var nvmeDevices: [NVMeDeviceInfo] = []
    private let clock = WorkerClock()

    deinit {
        closeConnections()
    }

    func discover(generation: UInt64) -> DiscoveredCatalog {
        closeConnections()
        smcKeys.removeAll(keepingCapacity: true)
        hidServices.removeAll(keepingCapacity: true)
        nvmeDevices.removeAll(keepingCapacity: true)

        var sources: [DiscoveredSource] = []
        sources.append(contentsOf: discoverSMCSources())
        sources.append(contentsOf: discoverHIDSources())
        sources.append(contentsOf: discoverNVMESources())
        if let iopsSource = discoverIOPSSource() {
            sources.append(iopsSource)
        }
        return DiscoveredCatalog(generation: generation, sources: sources)
    }

    func read(
        requestID: RequestID,
        generation: UInt64,
        transportHandles: [String]
    ) -> TransportReadBatch {
        let readings = transportHandles.map { handle in
            readHandle(handle)
        }
        return TransportReadBatch(
            requestID: requestID,
            generation: generation,
            readings: readings
        )
    }

    func closeConnections() {
        if smcConnection != 0 {
            sp_smc_close(smcConnection)
            smcConnection = 0
        }
        if let hidProbe {
            sp_hid_close(hidProbe)
            self.hidProbe = nil
        }
        if let nvmeProbe {
            sp_nvme_close(nvmeProbe)
            self.nvmeProbe = nil
        }
        smcKeys.removeAll(keepingCapacity: true)
        hidServices.removeAll(keepingCapacity: true)
        nvmeDevices.removeAll(keepingCapacity: true)
    }

    private func discoverSMCSources() -> [DiscoveredSource] {
        let status = sp_smc_open(&smcConnection)
        guard status == 0 else {
            return []
        }

        var raw = SPValue()
        let countStatus = sp_smc_read(smcConnection, SensorBridgeSupport.smcCode("#KEY"), &raw)
        guard countStatus == 0,
              raw.size == 4,
              SensorBridgeSupport.fourCC(raw.type) == "ui32" else {
            return []
        }

        let count = SensorBridgeSupport.smcBytes(from: raw).prefix(4).reduce(UInt32(0)) {
            $0 << 8 | UInt32($1)
        }
        guard count <= 16_384 else {
            return []
        }

        var sources: [DiscoveredSource] = []
        for index in 0..<count {
            var key: UInt32 = 0
            let keyStatus = sp_smc_key(smcConnection, index, &key)
            guard keyStatus == 0 else {
                continue
            }

            let rawKey = SensorBridgeSupport.fourCC(key)
            guard rawKey.hasPrefix("T") else {
                continue
            }

            var value = SPValue()
            let readStatus = sp_smc_read(smcConnection, key, &value)
            guard readStatus == 0 else {
                continue
            }

            let encoding = SensorBridgeSupport.smcEncoding(from: value)
            let byteCount = Int(value.size)
            smcKeys[rawKey] = SMCKeyInfo(key: key, encoding: encoding, byteCount: byteCount)
            sources.append(
                DiscoveredSource(
                    transportHandle: "smc:\(rawKey)",
                    provider: .smc,
                    rawKey: rawKey,
                    registryID: rawKey,
                    encoding: encoding,
                    byteCount: byteCount
                )
            )
        }
        return sources
    }

    private func discoverHIDSources() -> [DiscoveredSource] {
        var status: Int32 = 0
        hidProbe = sp_hid_open(&status)
        guard status == 0, let hidProbe else {
            return []
        }

        var sources: [DiscoveredSource] = []
        let count = sp_hid_count(hidProbe)
        for index in 0..<count {
            var nameBuffer = [CChar](repeating: 0, count: 512)
            sp_hid_name(hidProbe, index, &nameBuffer, nameBuffer.count)
            let productName = String(
                decoding: nameBuffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            let registryID = String(format: "00000000-0000-4000-8000-%012x", index + 1)
            hidServices.append(
                HIDServiceInfo(index: index, productName: productName, registryID: registryID)
            )
            sources.append(
                DiscoveredSource(
                    transportHandle: "hid:\(index)",
                    provider: .hid,
                    rawKey: productName,
                    registryID: registryID,
                    encoding: "event",
                    byteCount: 0
                )
            )
        }
        return sources
    }

    private func discoverNVMESources() -> [DiscoveredSource] {
        var status: Int32 = 0
        nvmeProbe = sp_nvme_open(&status)
        guard let nvmeProbe else {
            return []
        }

        var sources: [DiscoveredSource] = []
        let count = sp_nvme_count(nvmeProbe)
        for index in 0..<count {
            let registryID = String(format: "00000000-0000-4000-8001-%012x", index + 1)
            nvmeDevices.append(NVMeDeviceInfo(index: index, registryID: registryID))
            sources.append(
                DiscoveredSource(
                    transportHandle: "nvme:\(index)",
                    provider: .nvme,
                    rawKey: "TEMPERATURE",
                    registryID: registryID,
                    encoding: "uint16_le_kelvin",
                    byteCount: 2
                )
            )
        }
        return sources
    }

    private func discoverIOPSSource() -> DiscoveredSource? {
        guard IOPSCopyPowerSourcesInfo()?.takeRetainedValue() != nil else {
            return nil
        }
        return DiscoveredSource(
            transportHandle: "iops:Temperature",
            provider: .iops,
            rawKey: "Temperature",
            registryID: nil,
            encoding: "cfnumber_celsius",
            byteCount: 0
        )
    }

    private func readHandle(_ handle: String) -> TransportReading {
        let started = clock.timestamp()
        let outcome: TransportReadingOutcome
        if handle.hasPrefix("smc:") {
            outcome = readSMCHandle(String(handle.dropFirst(4)))
        } else if handle.hasPrefix("hid:") {
            outcome = readHIDHandle(handle)
        } else if handle.hasPrefix("nvme:") {
            outcome = readNVMeHandle(handle)
        } else if handle == "iops:Temperature" {
            outcome = readIOPSTemperature()
        } else {
            outcome = .failure(code: .sensorRead, underlyingCode: "unknown_transport_handle")
        }
        let finished = clock.timestamp()
        return TransportReading(
            transportHandle: handle,
            started: started,
            finished: finished,
            outcome: outcome
        )
    }

    private func readSMCHandle(_ rawKey: String) -> TransportReadingOutcome {
        guard let info = smcKeys[rawKey], smcConnection != 0 else {
            return .failure(code: .sensorRead, underlyingCode: "missing_smc_key")
        }

        var value = SPValue()
        let status = sp_smc_read(smcConnection, info.key, &value)
        guard status == 0 else {
            return .failure(code: .sensorRead, underlyingCode: SensorBridgeSupport.statusText(status))
        }

        let encoding = SensorBridgeSupport.smcEncoding(from: value)
        let bytes = SensorBridgeSupport.smcBytes(from: value)
        guard let celsius = SensorDecoding.smcTemperatureC(encoding: encoding, bytes: bytes) else {
            return .failure(code: .sensorValue, underlyingCode: "unsupported_smc_encoding")
        }
        return .success(valueC: celsius, sourceWallUnixNS: nil, freshness: .unknown)
    }

    private func readHIDHandle(_ handle: String) -> TransportReadingOutcome {
        guard let hidProbe,
              let index = Int32(handle.dropFirst(4)),
              hidServices.contains(where: { $0.index == index }) else {
            return .failure(code: .sensorRead, underlyingCode: "missing_hid_service")
        }

        var value = Double.nan
        let status = sp_hid_read(hidProbe, index, &value)
        guard let celsius = Registry.hidTemperatureC(readStatus: status, value: value) else {
            return .failure(code: .sensorValue, underlyingCode: SensorBridgeSupport.statusText(status))
        }
        return .success(valueC: celsius, sourceWallUnixNS: nil, freshness: .unknown)
    }

    private func readNVMeHandle(_ handle: String) -> TransportReadingOutcome {
        guard let nvmeProbe,
              let index = Int32(handle.dropFirst(5)),
              nvmeDevices.contains(where: { $0.index == index }) else {
            return .failure(code: .sensorRead, underlyingCode: "missing_nvme_device")
        }

        var kelvin: UInt16 = 0
        let status = sp_nvme_read(nvmeProbe, index, &kelvin)
        guard status == 0 else {
            return .failure(code: .sensorRead, underlyingCode: SensorBridgeSupport.statusText(status))
        }
        guard let celsius = SensorDecoding.nvmeTemperatureC(kelvin: kelvin) else {
            return .failure(code: .sensorValue, underlyingCode: "kelvin_not_reported")
        }
        return .success(valueC: celsius, sourceWallUnixNS: nil, freshness: .unknown)
    }

    private func readIOPSTemperature() -> TransportReadingOutcome {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceList = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sourceList.first,
              let description = IOPSGetPowerSourceDescription(info, firstSource)?
            .takeUnretainedValue() as? [String: Any] else {
            return .failure(code: .sensorRead, underlyingCode: "missing_iops_source")
        }

        guard let raw = description[kIOPSTemperatureKey] else {
            return .failure(code: .sensorValue, underlyingCode: "field_absent")
        }
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID() else {
            return .failure(code: .sensorValue, underlyingCode: "unexpected_type")
        }
        let value = number.doubleValue
        guard value.isFinite else {
            return .failure(code: .sensorValue, underlyingCode: "nonfinite")
        }
        return .success(valueC: value, sourceWallUnixNS: nil, freshness: .unknown)
    }
}
