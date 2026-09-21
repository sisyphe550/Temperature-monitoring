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
        return value.isFinite ? value : nil
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
