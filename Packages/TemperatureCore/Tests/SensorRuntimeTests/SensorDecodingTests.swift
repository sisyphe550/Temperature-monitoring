import Foundation
import Testing
import TemperatureCore

@Suite struct SensorDecodingTests {
    @Test func decodesLittleEndianFloatAs25Point5C() {
        let decoded = SensorDecoding.smcTemperatureC(
            encoding: "flt ",
            bytes: [0x00, 0x00, 0xCC, 0x41]
        )
        #expect(decoded != nil)
        #expect(SensorDecoding.nearlyEqual(decoded!, 25.5))
    }

    @Test func decodesBigEndianSignedFixedPointAs25Point5C() {
        let decoded = SensorDecoding.smcTemperatureC(encoding: "sp78", bytes: [0x19, 0x80])
        #expect(decoded != nil)
        #expect(SensorDecoding.nearlyEqual(decoded!, 25.5))
    }

    @Test func decodesNegativeSignedFixedPoint() {
        let decoded = SensorDecoding.smcTemperatureC(encoding: "sp78", bytes: [0xFE, 0x80])
        #expect(decoded != nil)
        #expect(SensorDecoding.nearlyEqual(decoded!, -1.5))
    }

    @Test func rejectsWrongLengthUnknownEncodingAndNonFiniteValues() {
        let malformed: [(String, [UInt8])] = [
            ("flt ", []),
            ("flt ", [0, 0, 0xCC]),
            ("flt ", [0, 0, 0xCC, 0x41, 0]),
            ("sp78", [0x19]),
            ("ui32", [0, 0, 0, 50]),
            ("flt ", [0, 0, 0x80, 0x7F]),
            ("flt ", [0, 0, 0xC0, 0x7F]),
        ]
        for (encoding, bytes) in malformed {
            #expect(SensorDecoding.smcTemperatureC(encoding: encoding, bytes: bytes) == nil)
        }
    }

    @Test func encodingMatchingIsCaseSensitive() {
        let bytes: [UInt8] = [0x00, 0x00, 0xCC, 0x41]
        #expect(SensorDecoding.smcTemperatureC(encoding: "flt ", bytes: bytes) != nil)
        #expect(SensorDecoding.smcTemperatureC(encoding: "FLT ", bytes: bytes) == nil)
        #expect(SensorDecoding.smcTemperatureC(encoding: "sp78", bytes: [0x19, 0x80]) != nil)
        #expect(SensorDecoding.smcTemperatureC(encoding: "SP78", bytes: [0x19, 0x80]) == nil)
    }

    @Test func decodesSmartKelvinLittleEndian() {
        let kelvin = UInt16(0x012C)
        let decoded = SensorDecoding.nvmeTemperatureC(kelvin: kelvin)
        #expect(decoded != nil)
        #expect(SensorDecoding.nearlyEqual(decoded!, 26.85))
    }

    @Test func qualifiedSMCReadingRejectsChangedEncodingAndLength() {
        #expect(SensorDecoding.smcTemperatureC(
            encoding: "flt ", bytes: [0x00, 0x00, 0xCC, 0x41],
            expectedEncoding: "flt ", expectedByteCount: 4
        ) == 25.5)
        #expect(SensorDecoding.smcTemperatureC(
            encoding: "sp78", bytes: [0x19, 0x80],
            expectedEncoding: "flt ", expectedByteCount: 4
        ) == nil)
        #expect(SensorDecoding.smcTemperatureC(
            encoding: "flt ", bytes: [0x00, 0x00, 0xCC, 0x41],
            expectedEncoding: "flt ", expectedByteCount: 2
        ) == nil)
    }

    @Test func iopsAcceptsCelsiusCFNumberAndRejectsMissingBooleanInvalidValues() {
        #expect(SensorDecoding.iopsTemperatureC(field: NSNumber(value: 28.5)) == 28.5)
        #expect(SensorDecoding.iopsTemperatureC(field: NSNumber(value: 0)) == 0)
        #expect(SensorDecoding.iopsTemperatureC(field: nil) == nil)
        #expect(SensorDecoding.iopsTemperatureC(field: true) == nil)
        #expect(SensorDecoding.iopsTemperatureC(field: NSNumber(value: false)) == nil)
        #expect(SensorDecoding.iopsTemperatureC(field: "28.5") == nil)
        for invalid in [Double.nan, Double.infinity, -Double.infinity, -274] {
            #expect(SensorDecoding.iopsTemperatureC(field: NSNumber(value: invalid)) == nil)
        }
    }

    @Test func smcRejectsTemperatureBelowAbsoluteZero() {
        let bits = Float(-274).bitPattern
        let bytes = (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
        #expect(SensorDecoding.smcTemperatureC(encoding: "flt ", bytes: bytes) == nil)
    }

    @Test func rawKeysAreCaseSensitive() {
        #expect(SensorDecoding.rawKeyMatches(profileKey: "Tp01", discoveredKey: "Tp01"))
        #expect(!SensorDecoding.rawKeyMatches(profileKey: "Tp01", discoveredKey: "tp01"))
        #expect(!SensorDecoding.rawKeyMatches(profileKey: "Te05", discoveredKey: "TE05"))
    }

    @Test func smcBridgeSourceContainsNoWriteOrPrivilegeSymbols() throws {
        let source = try Self.sensorBridgeSource()
        let forbidden = [
            "command = 6",
            "command = 7",
            "command=6",
            "command=7",
            ".command = 6",
            ".command = 7",
            "AuthorizationExecute",
            "setuid",
            "system(",
            "popen(",
            "NSTask",
            "SMSet",
            "AppleSMCForce",
            "kSMCSupervisor",
        ]
        for token in forbidden {
            #expect(!source.contains(token), "forbidden token found: \(token)")
        }
    }

    private static func sensorBridgeSource() throws -> String {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                let source = url.appendingPathComponent("Sources/SensorBridge/SensorBridge.c")
                return try String(contentsOf: source, encoding: .utf8)
            }
            url.deleteLastPathComponent()
        }
        throw SensorDecodingTestError.missingBridgeSource
    }
}

enum SensorDecodingTestError: Error {
    case missingBridgeSource
}
