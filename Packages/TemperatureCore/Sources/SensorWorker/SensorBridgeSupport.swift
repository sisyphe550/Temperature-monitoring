import Foundation
import SensorBridge

enum SensorBridgeSupport {
    static func fourCC(_ number: UInt32) -> String {
        String(
            bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: number >> $0) },
            encoding: .ascii
        ) ?? String(format: "%08x", number)
    }

    static func smcCode(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func statusText(_ status: Int32) -> String {
        String(format: "error:0x%08x", UInt32(bitPattern: status))
    }

    static func smcBytes(from value: SPValue) -> [UInt8] {
        withUnsafeBytes(of: value.bytes) { raw in
            Array(raw.prefix(min(Int(value.size), 32)))
        }
    }

    static func smcEncoding(from value: SPValue) -> String {
        value.type == 0 ? "unknown" : fourCC(value.type)
    }
}
