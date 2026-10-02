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
        let transportHandle: String
    }

    private var smcConnection: UInt32 = 0
    private var hidProbe: OpaquePointer?
    private var nvmeProbe: OpaquePointer?
    private var smcKeys: [String: SMCKeyInfo] = [:]
    private var hidServices: [HIDServiceInfo] = []
    private var nvmeDevices: [NVMeDeviceInfo] = []
    private var iopsSourceID: Int64?
    private let clock: WorkerClock

    init(clock: WorkerClock) { self.clock = clock }

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
        iopsSourceID = nil
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

        let batteryKeys = Set((try? Configuration.bundledProfile())?.batteryProviderPriority.compactMap {
            $0.hasPrefix("smc:") ? String($0.dropFirst(4)) : nil
        } ?? [])
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
            // Optional SMC battery candidates must have a real, valid initial reading.
            // CPU encoding/value facts remain visible for Registry's mandatory checks.
            if batteryKeys.contains(rawKey), SensorDecoding.smcTemperatureC(
                encoding: encoding, bytes: SensorBridgeSupport.smcBytes(from: value)
            ) == nil {
                continue
            }
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
        guard status == 0, let nvmeProbe else {
            // A failed/incomplete enumeration must not select from a partial device set.
            return [DiscoveredSource(
                transportHandle: "nvme:discovery-failed", provider: .nvme,
                rawKey: "TEMPERATURE", registryID: nil,
                encoding: "uint16_le_kelvin", byteCount: 2,
                physicalInterconnectLocation: nil, interconnectLookupStatus: .lookupFailed
            )]
        }
        var sources: [DiscoveredSource] = []
        for index in 0..<sp_nvme_count(nvmeProbe) {
            var identity: UInt64 = 0
            let identityStatus = sp_nvme_identity(nvmeProbe, index, &identity)
            let registryID = identityStatus == 0 && identity != 0 ? String(identity) : nil
            var locationBuffer = [CChar](repeating: 0, count: 256)
            var lookup: Int32 = SP_NVME_LOCATION_LOOKUP_FAILED
            let locationStatus = sp_nvme_location(
                nvmeProbe, index, &locationBuffer, locationBuffer.count, &lookup
            )
            let lookupStatus: InterconnectLookupStatus
            switch (locationStatus, lookup) {
            case (0, SP_NVME_LOCATION_FOUND): lookupStatus = .found
            case (0, SP_NVME_LOCATION_MISSING_PROPERTY): lookupStatus = .missingProperty
            default: lookupStatus = .lookupFailed
            }
            let location = lookupStatus == .found ? String(
                decoding: locationBuffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
                as: UTF8.self
            ) : nil
            // Index is only a local read handle for an unidentifiable device, never a registry identity.
            let handle = registryID.map { "nvme:\($0)" } ?? "nvme:identity-missing:\(index)"
            nvmeDevices.append(NVMeDeviceInfo(index: index, transportHandle: handle))
            sources.append(DiscoveredSource(
                transportHandle: handle, provider: .nvme, rawKey: "TEMPERATURE",
                registryID: registryID, encoding: "uint16_le_kelvin", byteCount: 2,
                physicalInterconnectLocation: location, interconnectLookupStatus: lookupStatus
            ))
        }
        return sources
    }

    private func discoverIOPSSource() -> DiscoveredSource? {
        guard let battery = uniqueInternalBattery(),
              SensorDecoding.iopsTemperatureC(field: battery.description[kIOPSTemperatureKey]) != nil else {
            return nil
        }
        iopsSourceID = battery.id
        return DiscoveredSource(
            transportHandle: "iops:\(battery.id):Temperature", provider: .iops,
            rawKey: "Temperature", registryID: "iops:\(battery.id)",
            encoding: "cfnumber_celsius", byteCount: 0
        )
    }

    // Select the unique internal battery by its SDK-defined Power Source ID.
    // External UPS order in IOPS is not evidence for a battery identity.
    private func uniqueInternalBattery() -> (id: Int64, description: [String: Any])? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceList = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        var batteries: [(id: Int64, description: [String: Any])] = []
        for source in sourceList {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            guard let number = description[kIOPSPowerSourceIDKey] as? NSNumber,
                  CFGetTypeID(number) == CFNumberGetTypeID(),
                  !CFNumberIsFloatType(unsafeBitCast(number, to: CFNumber.self)) else {
                return nil
            }
            batteries.append((number.int64Value, description))
        }
        return batteries.count == 1 ? batteries[0] : nil
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
        } else if let iopsSourceID, handle == "iops:\(iopsSourceID):Temperature" {
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
        guard let celsius = SensorDecoding.smcTemperatureC(
            encoding: encoding, bytes: bytes,
            expectedEncoding: info.encoding, expectedByteCount: info.byteCount
        ) else {
            return .failure(code: .sensorValue, underlyingCode: "smc_encoding_length_or_value_changed")
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
              let device = nvmeDevices.first(where: { $0.transportHandle == handle }) else {
            return .failure(code: .sensorRead, underlyingCode: "missing_nvme_device")
        }

        var kelvin: UInt16 = 0
        let status = sp_nvme_read(nvmeProbe, device.index, &kelvin)
        guard status == 0 else {
            return .failure(code: .sensorRead, underlyingCode: SensorBridgeSupport.statusText(status))
        }
        guard let celsius = SensorDecoding.nvmeTemperatureC(kelvin: kelvin) else {
            return .failure(code: .sensorValue, underlyingCode: "kelvin_not_reported")
        }
        return .success(valueC: celsius, sourceWallUnixNS: nil, freshness: .unknown)
    }

    private func readIOPSTemperature() -> TransportReadingOutcome {
        guard let selectedID = iopsSourceID,
              let battery = uniqueInternalBattery(), battery.id == selectedID else {
            return .failure(code: .sensorRead, underlyingCode: "iops_battery_identity_changed_or_missing")
        }
        guard let raw = battery.description[kIOPSTemperatureKey] else {
            return .failure(code: .sensorValue, underlyingCode: "field_absent")
        }
        guard let value = SensorDecoding.iopsTemperatureC(field: raw) else {
            return .failure(code: .sensorValue, underlyingCode: "invalid_iops_temperature")
        }
        return .success(valueC: value, sourceWallUnixNS: nil, freshness: .unknown)
    }
}
