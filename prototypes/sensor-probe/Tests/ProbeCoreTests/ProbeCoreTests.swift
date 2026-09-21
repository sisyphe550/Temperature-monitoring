import Testing
@testable import ProbeCore

struct ProbeCoreTests {
    // Catch wrong endianness and unsigned decoding of signed fixed point.
    @Test func testSMCDecodesFloatAndSignedFixedPoint() {
        checkEqual(Decode.smc(type: "flt ", bytes: [0, 0, 72, 66]), 50)
        checkEqual(Decode.smc(type: "sp78", bytes: [0x19, 0x80]), 25.5)
        checkEqual(Decode.smc(type: "sp78", bytes: [0xfe, 0x80]), -1.5)
    }

    @Test func testMalformedAndNonFiniteSMCValuesHaveNoTemperature() {
        for (type, bytes): (String, [UInt8]) in [
            ("flt ", []), ("flt ", [0, 0, 72]), ("flt ", [0, 0, 72, 66, 0]),
            ("sp78", [1]), ("ui32", [0, 0, 0, 50]),
            ("flt ", [0, 0, 0x80, 0x7f]), ("flt ", [0, 0, 0xc0, 0x7f])
        ] {
            checkNil(Decode.smc(type: type, bytes: bytes))
        }
    }

    @Test func testZeroAndRepeatedFiniteReadingsAreNotDiscarded() {
        checkEqual(Decode.smc(type: "flt ", bytes: [0, 0, 0, 0]), 0)
        checkEqual(Decode.smc(type: "flt ", bytes: [0, 0, 72, 66]), 50)
        checkEqual(Decode.smc(type: "flt ", bytes: [0, 0, 72, 66]), 50)
    }

    @Test func testNVMeKelvinConversionAndMissingValue() throws {
        #expect(abs(try #require(Decode.nvme(kelvin: 300)) - 26.85) < 0.00001)
        checkNil(Decode.nvme(kelvin: 0))
    }

    @Test func testScheduleSkipsElapsedSlotsWithoutCatchupOrDrift() {
        checkEqual(Schedule.nextSlot(current: 0, finishedNS: 2, periodNS: 50), 1)
        checkEqual(Schedule.nextSlot(current: 0, finishedNS: 50, periodNS: 50), 1)
        checkEqual(Schedule.nextSlot(current: 0, finishedNS: 121, periodNS: 50), 3)
        checkEqual(Schedule.nextSlot(current: 3, finishedNS: 151, periodNS: 50), 4)
    }

    @Test func testCSVPreservesCommasQuotesAndNewlines() {
        checkEqual(csvField("Te05"), "Te05")
        checkEqual(csvField("a,b"), "\"a,b\"")
        checkEqual(csvField("a\"b"), "\"a\"\"b\"")
        checkEqual(csvField("a\nb"), "\"a\nb\"")
    }

    @Test func testOptionsApplyDefaultsAndAllFiveIntervals() throws {
        let defaults = try Options(arguments: [])
        checkEqual(defaults.intervals, [200])
        checkEqual(defaults.seconds, 10)
        let all = try Options(arguments: ["--intervals", "50,100,200,500,1000", "--seconds", "120", "--output", "example"])
        checkEqual(all.intervals, [50, 100, 200, 500, 1000])
        checkEqual(all.seconds, 120)
        checkEqual(all.output, "example")
    }

    @Test func testOptionsRejectUnboundedOrAmbiguousRuns() {
        for args in [["--seconds"], ["--seconds", "0"], ["--seconds", "3601"],
                     ["--seconds", "nan"], ["--intervals", "49"], ["--intervals", ""],
                     ["--intervals", "50,50"], ["--intervals", "50,"], ["--output", ""],
                     ["--unknown", "1"]] {
            #expect(throws: (any Error).self) { try Options(arguments: args) }
        }
    }
}

private func checkEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, sourceLocation: sourceLocation)
}

private func checkNil<T>(_ actual: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == nil, sourceLocation: sourceLocation)
}
