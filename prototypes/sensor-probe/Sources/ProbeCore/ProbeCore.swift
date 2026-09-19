import Foundation

public enum Decode {
    public static func smc(type: String, bytes: [UInt8]) -> Double? {
        let value: Double
        switch (type, bytes.count) {
        case ("flt ", 4):
            let bits = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            value = Double(Float(bitPattern: bits))
        case ("sp78", 2):
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default: return nil
        }
        return value.isFinite ? value : nil
    }
    public static func nvme(kelvin: UInt16) -> Double? {
        kelvin == 0 ? nil : Double(kelvin) - 273.15
    }
}

public enum Schedule {
    public static func nextSlot(current: UInt64, finishedNS: UInt64, periodNS: UInt64) -> UInt64 {
        precondition(periodNS > 0)
        let ceiling = finishedNS / periodNS + (finishedNS % periodNS == 0 ? 0 : 1)
        return max(current + 1, ceiling)
    }
}

public func csvField(_ text: String) -> String {
    guard text.contains(where: { ",\"\n\r".contains($0) }) else { return text }
    return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

public struct Options {
    public var intervals: [Int] = [200]
    public var seconds: Int = 10
    public var output: String = "validation-runs/probe"
    public init(arguments: [String]) throws {
        enum Invalid: Error { case arguments }
        guard arguments.count % 2 == 0 else { throw Invalid.arguments }
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--intervals":
                let parts = value.split(separator: ",", omittingEmptySubsequences: false)
                let parsed = parts.compactMap { Int($0) }
                guard parsed.count == parts.count, !parsed.isEmpty,
                      Set(parsed).count == parsed.count,
                      parsed.allSatisfy({ [50, 100, 200, 500, 1000].contains($0) }) else { throw Invalid.arguments }
                intervals = parsed
            case "--seconds":
                guard let parsed = Int(value), (1...3600).contains(parsed) else { throw Invalid.arguments }
                seconds = parsed
            case "--output":
                guard !value.isEmpty else { throw Invalid.arguments }
                output = value
            default: throw Invalid.arguments
            }
        }
    }
}
