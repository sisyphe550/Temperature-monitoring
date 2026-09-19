import Foundation
import IOKit
import IOKit.ps
import SensorBridge
import ProbeCore

struct Reading: Codable {
    var rawType: String
    var rawValue: String
    var celsius: Double?
    var status: String
}

struct Sensor {
    let provider: String
    let id: String
    let role: String
    let unitEvidence: String
    let read: () -> Reading
}

func fourCC(_ number: UInt32) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: number >> $0) }, encoding: .ascii) ?? String(format: "%08x", number)
}
func smcCode(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
func statusText(_ status: Int32) -> String { String(format: "error:0x%08x", UInt32(bitPattern: status)) }

final class Hardware {
    var smc: UInt32 = 0
    var hid: OpaquePointer?
    var nvme: OpaquePointer?
    var sensors: [Sensor] = []
    var diagnostics: [String: String] = [:]

    init() {
        discoverSMC()
        discoverHID()
        discoverNVMe()
        discoverBattery()
    }

    deinit { sp_smc_close(smc); sp_hid_close(hid); sp_nvme_close(nvme) }

    func smcReading(key: UInt32) -> Reading {
        var raw = SPValue()
        let status = sp_smc_read(smc, key, &raw)
        let type = raw.type == 0 ? "unavailable" : fourCC(raw.type)
        let bytes = withUnsafeBytes(of: raw.bytes) { Array($0.prefix(min(Int(raw.size), 32))) }
        let value = status == 0 ? Decode.smc(type: type, bytes: bytes) : nil
        return Reading(rawType: type, rawValue: status == 0 ? bytes.map { String(format: "%02x", $0) }.joined() : "", celsius: value,
                       status: status != 0 ? statusText(status) : (value == nil ? "unsupported_type_or_nonfinite" : "decoded_mapping_unverified"))
    }

    private func discoverSMC() {
        let status = sp_smc_open(&smc)
        diagnostics["AppleSMC.open"] = status == 0 ? "ok" : statusText(status)
        guard status == 0 else { return }
        var raw = SPValue()
        let countStatus = sp_smc_read(smc, smcCode("#KEY"), &raw)
        guard countStatus == 0, raw.size == 4, fourCC(raw.type) == "ui32" else {
            diagnostics["AppleSMC.enumeration"] = "invalid_key_count:\(statusText(countStatus))"
            return
        }
        let count = withUnsafeBytes(of: raw.bytes) { $0.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
        diagnostics["AppleSMC.key_count"] = String(count)
        guard count <= 16384 else { diagnostics["AppleSMC.enumeration"] = "count_exceeds_probe_bound"; return }
        var failed = 0
        for index in 0..<count {
            var key: UInt32 = 0
            let result = sp_smc_key(smc, index, &key)
            guard result == 0 else { failed += 1; continue }
            let name = fourCC(key)
            // A T prefix is a candidate filter, not proof of temperature semantics.
            guard name.hasPrefix("T") else { continue }
            let role = name.hasPrefix("Te") || name.hasPrefix("Tp") ? "cpu_candidate" : "unmapped"
            sensors.append(Sensor(provider: "AppleSMC", id: name, role: role,
                                  unitEvidence: "macmon protocol; Celsius interpretation and physical mapping unverified",
                                  read: { [unowned self] in self.smcReading(key: key) }))
        }
        diagnostics["AppleSMC.failed_key_indices"] = String(failed)
    }

    private func discoverHID() {
        var status: Int32 = 0
        hid = sp_hid_open(&status)
        diagnostics["HID.open"] = status == 0 ? "ok" : statusText(status)
        diagnostics["HID.service_count"] = String(sp_hid_count(hid))
        for index in 0..<sp_hid_count(hid) {
            var name = [CChar](repeating: 0, count: 512)
            sp_hid_name(hid, index, &name, name.count)
            let product = String(decoding: name.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let role: String
            if product.hasPrefix("eACC") || product.hasPrefix("pACC") { role = "cpu_candidate" }
            else if product == "gas gauge battery" { role = "battery_candidate" }
            else if product.hasPrefix("NAND CH") { role = "ssd_candidate" }
            else { role = "unmapped" }
            sensors.append(Sensor(provider: "HID", id: "\(index):\(product)", role: role,
                                  unitEvidence: "private HID temperature event 15; ID only stable within this process",
                                  read: { [unowned self] in
                var value = Double.nan
                let result = sp_hid_read(self.hid, index, &value)
                return Reading(rawType: "IOHIDEventFloat", rawValue: result == 0 ? String(value) : "", celsius: result == 0 && value.isFinite ? value : nil,
                               status: result != 0 ? statusText(result) : (value.isFinite ? "decoded_mapping_unverified" : "nonfinite"))
            }))
        }
    }

    private func discoverNVMe() {
        var status: Int32 = 0
        nvme = sp_nvme_open(&status)
        diagnostics["NVMe.discovery"] = status == 0 ? "ok" : statusText(status)
        diagnostics["NVMe.smart_capable_count"] = String(sp_nvme_count(nvme))
        for index in 0..<sp_nvme_count(nvme) {
            sensors.append(Sensor(provider: "NVMeSMART", id: "device:\(index):TEMPERATURE", role: "ssd",
                                  unitEvidence: "NVMe SMART composite temperature, uint16 little-endian Kelvin; Celsius = K - 273.15",
                                  read: { [unowned self] in
                var kelvin: UInt16 = 0
                let result = sp_nvme_read(self.nvme, index, &kelvin)
                let value = result == 0 ? Decode.nvme(kelvin: kelvin) : nil
                return Reading(rawType: "uint16_le_kelvin", rawValue: result == 0 ? String(kelvin) : "", celsius: value,
                               status: result != 0 ? statusText(result) : (value == nil ? "not_reported" : "ok"))
            }))
        }
    }

    private func discoverBattery() {
        let descriptions = batteryDescriptions()
        diagnostics["IOPowerSources.count"] = String(descriptions.count)
        for index in descriptions.indices {
            diagnostics["IOPowerSources.\(index).power_state"] = descriptions[index][kIOPSPowerSourceStateKey] as? String ?? "unknown"
            sensors.append(Sensor(provider: "IOPowerSources", id: "source:\(index):Temperature", role: "battery",
                                  unitEvidence: "IOPSKeys.h kIOPSTemperatureKey: CFNumber, Celsius",
                                  read: {
                let current = batteryDescriptions()
                guard current.indices.contains(index), let raw = current[index][kIOPSTemperatureKey] else {
                    return Reading(rawType: "missing", rawValue: "", celsius: nil, status: "field_absent")
                }
                guard let number = raw as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID() else {
                    return Reading(rawType: String(describing: type(of: raw)), rawValue: String(describing: raw), celsius: nil, status: "unexpected_type")
                }
                let value = number.doubleValue
                return Reading(rawType: "CFNumber_Celsius", rawValue: number.stringValue, celsius: value.isFinite ? value : nil, status: value.isFinite ? "ok" : "nonfinite")
            }))
        }
        // Preserve driver-specific raw value without guessing its unit.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let raw = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, nil, 0)?.takeRetainedValue() {
                diagnostics["IORegistry.AppleSmartBattery.Temperature.raw"] = String(describing: raw)
                diagnostics["IORegistry.AppleSmartBattery.Temperature.unit"] = "unknown; not converted or sampled"
            }
        }
    }
}

func batteryDescriptions() -> [[String: Any]] {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
    return sources.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
}
