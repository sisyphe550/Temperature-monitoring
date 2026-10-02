import CoreFoundation
import Foundation

public enum SensorDecoding {
    private static let floatTolerance = 1e-8

    public static func smcTemperatureC(encoding: String, bytes: [UInt8]) -> Double? {
        let value: Double
        switch (encoding, bytes.count) {
        case ("flt ", 4):
            let bits = bytes.enumerated().reduce(UInt32(0)) { partial, element in
                partial | UInt32(element.element) << (element.offset * 8)
            }
            value = Double(Float(bitPattern: bits))
        case ("sp78", 2):
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            value = Double(Int16(bitPattern: raw)) / 256
        default:
            return nil
        }
        return value.isFinite && value >= -273.15 ? value : nil
    }

    // A previously qualified SMC source cannot silently adopt a new encoding.
    public static func smcTemperatureC(
        encoding: String,
        bytes: [UInt8],
        expectedEncoding: String,
        expectedByteCount: Int
    ) -> Double? {
        guard encoding == expectedEncoding, bytes.count == expectedByteCount else {
            return nil
        }
        return smcTemperatureC(encoding: encoding, bytes: bytes)
    }

    // SDK IOPSKeys.h defines Temperature as a CFNumber in degrees Celsius.
    // CFBoolean also bridges to NSNumber, so its CF type must be rejected.
    public static func iopsTemperatureC(field: Any?) -> Double? {
        guard let number = field as? NSNumber,
              CFGetTypeID(number) == CFNumberGetTypeID() else {
            return nil
        }
        let value = number.doubleValue
        return value.isFinite && value >= -273.15 ? value : nil
    }

    public static func nvmeTemperatureC(kelvin: UInt16) -> Double? {
        kelvin == 0 ? nil : Double(kelvin) - 273.15
    }

    public static func rawKeyMatches(profileKey: String, discoveredKey: String) -> Bool {
        profileKey == discoveredKey
    }

    public static func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= floatTolerance
    }
}
