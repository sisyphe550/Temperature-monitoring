import Foundation
import Testing
@testable import TemperatureCore
@testable import TemperaturePresentation

@Suite struct PresentationHistoryRegressionTests {
    @Test(arguments: [50, 100]) func fiveMinutesPreservesFullRangeAndExtrema(periodMS: Int) throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000801")
        let count: Int = 300_000 / periodMS
        let points: [HistoryPoint] = (0..<count).map { index -> HistoryPoint in
            let elapsedNS: Int64 = Int64(index * periodMS) * 1_000_000
            let wallNS: Int64 = 1_700_000_000_000_000_000 + elapsedNS
            let valueC: Double
            if index == 100 { valueC = 99 }
            else if index == 101 { valueC = -8 }
            else { valueC = 50 }
            return
            HistoryPoint(
                seriesID: seriesID, segment: 1,
                elapsedNS: elapsedNS, wallUnixNS: wallNS, valueC: valueC,
                minC: nil, maxC: nil, count: 1
            )
        }
        let state = ready(points: points, seriesID: seriesID, pointLimit: 2000)
        guard case let .ready(series, _) = state, let output = series.first?.points else {
            Issue.record("Expected bounded history"); return
        }
        #expect(output.count <= 2000)
        #expect(output.first?.elapsedNS == 0)
        #expect(output.last?.elapsedNS == Int64(300_000 - periodMS) * 1_000_000)
        #expect(output.map { $0.minC ?? $0.valueC }.min() == -8)
        #expect(HistoryChartModel.peakMaxC(in: state) == 99)
        #expect(output.reduce(Int64(0)) { $0 + $1.count } == Int64(count))
    }

    @Test func requestedPointBudgetIsRespectedAcrossEntireRange() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000802")
        let points = (0..<3000).map { point(seriesID: seriesID, index: $0, segment: 1) }
        guard case let .ready(series, _) = ready(points: points, seriesID: seriesID, pointLimit: 60),
              let output = series.first?.points else {
            Issue.record("Expected bounded history"); return
        }
        #expect(output.count <= 60)
        #expect(output.first?.elapsedNS == 0)
        #expect(output.last?.elapsedNS == 299_900_000_000)
    }

    @Test func explicitGapBreaksLineEvenWithinOneSegment() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000803")
        let gap = Gap(
            gapID: try GapID(validating: "00000000-0000-4000-8000-000000000903"),
            seriesID: seriesID, startedElapsedNS: 150_000_000,
            endedElapsedNS: 250_000_000, reason: .readFailure
        )
        let points = [0, 1, 3, 4].map { point(seriesID: seriesID, index: $0, segment: 1) }
        let state = ready(points: points, seriesID: seriesID, pointLimit: 2000, gaps: [gap])
        let segments = HistoryChartModel.plotSegments(from: state)
        #expect(segments.count == 2)
        #expect(Set(segments.map(\.id)).count == 2)
        #expect(segments.first?.points.last?.elapsedNS == 100_000_000)
        #expect(segments.last?.points.first?.elapsedNS == 300_000_000)
    }

    @Test func segmentBoundariesSurviveDownsampling() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000804")
        let points = (0..<6000).map { index in
            HistoryPoint(seriesID: seriesID, segment: index < 3000 ? 1 : 2,
                elapsedNS: Int64(index) * 50_000_000, wallUnixNS: nil,
                valueC: 50, minC: nil, maxC: nil, count: 1)
        }
        let state = ready(points: points, seriesID: seriesID, pointLimit: 50)
        let segments = HistoryChartModel.plotSegments(from: state)
        #expect(segments.count == 2)
        guard segments.count == 2 else { return }
        #expect(segments[0].points.first?.elapsedNS == 0)
        #expect(segments[0].points.last?.elapsedNS == 149_950_000_000)
        #expect(segments[1].points.first?.elapsedNS == 150_000_000_000)
        #expect(segments[1].points.last?.elapsedNS == 299_950_000_000)
        #expect(segments.reduce(0) { $0 + $1.points.count } <= 50)
    }

    @Test func insufficientBudgetFailsInsteadOfDroppingSegments() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000805")
        let points = (0..<40).map { point(seriesID: seriesID, index: $0, segment: Int64($0 / 2 + 1)) }
        let state = ready(points: points, seriesID: seriesID, pointLimit: 20)
        guard case .failed = state else {
            Issue.record("Must report an unrepresentable boundary budget instead of dropping history"); return
        }
    }

    @Test @MainActor func batteryCacheKeepsItsIndependentThreeSecondLifetime() throws {
        let metricID = try MetricID(validating: "battery.temp")
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000806")
        let definition = SeriesDefinition(seriesID: seriesID, metricID: metricID, definitionVersion: 1,
            kind: .battery, displayName: "Battery", memberSourceIDs: [], formula: .identity)
        let observed = Timestamp(elapsedNS: 0, wallUnixNS: 1_700_000_000_000_000_000)
        let failure = MonitorFailure(code: .sensorRead, severity: .degraded, component: "test",
            operation: "read", retryCount: 1, sourceID: nil, underlyingCode: "timeout")
        let value = LatestValue(definition: definition,
            state: .available(ema: EMAValue(sampleID: "battery:1", seriesID: seriesID, segment: 1,
                timestamp: observed, valueC: 31), lastSuccessfulAt: observed, lastFailure: failure))
        let model = PresentationModel(primaryCPUMetricID: try MetricID(validating: "cpu.zone.max"))
        model.apply(snapshot: Snapshot(asOf: Timestamp(elapsedNS: 2_500_000_000,
            wallUnixNS: 1_700_000_002_500_000_000), values: [value], gapIDs: [], cpuPeriodMS: 50, generation: 1))
        guard case let .running(running) = model.state,
              let row = running.sections.first?.rows.first else { Issue.record("Missing battery"); return }
        guard case let .cached(valueC, _, reason) = row.value else { Issue.record("Battery expired before its third period"); return }
        #expect(valueC == 31)
        #expect(reason.contains("timeout"))
    }

    @Test func extraSourceVersionsAreRejectedExplicitly() throws {
        let ids: [SeriesID] = try (1...9).map { try SeriesID(validating: String(format: "00000000-0000-4000-8000-%012d", $0 + 810)) }
        let points = ids.map { point(seriesID: $0, index: 0, segment: 1) }
        let state = HistoryChartModel.makeReadyState(
            from: HistoryResult(layer: .ema, points: points, gaps: [], availableFromElapsedNS: 0, persistedThroughElapsedNS: nil),
            request: HistoryRequest(seriesIDs: ids, range: .fiveMinutes, asOfElapsedNS: 300_000_000_000, pointLimit: 2000))
        guard case let .failed(failure, _) = state else { Issue.record("Source versions must not be silently dropped"); return }
        #expect(failure.underlyingCode?.contains("8") == true)
    }

    @Test func twoPointBudgetPreservesEnvelopeAndSampleCount() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000820")
        let temperatures: [Double] = [10, 99, -8, 40, 15]
        let points = temperatures.enumerated().map { index, value in
            HistoryPoint(seriesID: seriesID, segment: 1, elapsedNS: Int64(index) * 100_000_000,
                wallUnixNS: nil, valueC: value, minC: nil, maxC: nil, count: Int64(index + 1))
        }
        let state = ready(points: points, seriesID: seriesID, pointLimit: 2)
        guard case let .ready(series, _) = state, let output = series.first?.points else {
            Issue.record("Expected two boundary points"); return
        }
        #expect(output.count == 2)
        #expect(output.first?.elapsedNS == 0)
        #expect(output.last?.elapsedNS == 400_000_000)
        #expect(output.first?.valueC == 10)
        #expect(output.last?.valueC == 15)
        #expect(output.reduce(Int64(0)) { $0 + $1.count } == 15)
        #expect(output.map { $0.minC ?? $0.valueC }.min() == -8)
        #expect(HistoryChartModel.peakMaxC(in: state) == 99)
    }

    @Test func onePointBudgetRejectsAContinuousRunWithTwoBoundaries() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000821")
        let points = (0..<3).map { point(seriesID: seriesID, index: $0, segment: 1) }
        guard case .failed = ready(points: points, seriesID: seriesID, pointLimit: 1) else {
            Issue.record("Must explain that one point cannot preserve the entire run"); return
        }
    }

    @Test func aggregateReductionRetainsWeightedMeanAndTotalCount() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000822")
        let temperatures: [Double] = [10, 20, 30, 40, 50]
        let points = temperatures.enumerated().map { index, value in
            HistoryPoint(seriesID: seriesID, segment: 1, elapsedNS: Int64(index) * 100_000_000,
                wallUnixNS: nil, valueC: value, minC: value - 1, maxC: value + 1, count: Int64(index + 1))
        }
        let state = HistoryChartModel.makeReadyState(
            from: HistoryResult(layer: .oneSecond, points: points, gaps: [],
                availableFromElapsedNS: 0, persistedThroughElapsedNS: 400_000_000),
            request: HistoryRequest(seriesIDs: [seriesID], range: .oneHour, asOfElapsedNS: 400_000_000, pointLimit: 2))
        guard case let .ready(series, _) = state, let output = series.first?.points else {
            Issue.record("Expected two weighted aggregate points"); return
        }
        let total = output.reduce(Int64(0)) { $0 + $1.count }
        let weightedSum = output.reduce(0.0) { $0 + $1.valueC * Double($1.count) }
        #expect(total == 15)
        #expect(abs(weightedSum / Double(total) - 550.0 / 15.0) < 0.000001)
        #expect(output.map { $0.minC ?? $0.valueC }.min() == 9)
        #expect(HistoryChartModel.peakMaxC(in: state) == 51)
    }

    @Test func sourceVersionsKeepTheirDefinitionsAndIndependentLines() throws {
        let oldID = try SeriesID(validating: "00000000-0000-4000-8000-000000000823")
        let currentID = try SeriesID(validating: "00000000-0000-4000-8000-000000000824")
        let metric = try MetricID(validating: "cpu.zone.max")
        let definitions = [oldID, currentID].enumerated().map { index, id in
            SeriesDefinition(seriesID: id, metricID: metric, definitionVersion: index + 1,
                kind: .cpuZone, displayName: "CPU热区最高温度", memberSourceIDs: [], formula: .maximum)
        }
        let points = [point(seriesID: oldID, index: 0, segment: 1),
            point(seriesID: oldID, index: 1, segment: 1),
            point(seriesID: currentID, index: 2, segment: 1),
            point(seriesID: currentID, index: 3, segment: 1)]
        let state = HistoryChartModel.makeReadyState(
            from: HistoryResult(layer: .ema, points: points, gaps: [], availableFromElapsedNS: 0, persistedThroughElapsedNS: nil),
            request: HistoryRequest(seriesIDs: [oldID, currentID], range: .fiveMinutes, asOfElapsedNS: 400_000_000, pointLimit: 2000),
            definitions: definitions)
        let segments = HistoryChartModel.plotSegments(from: state)
        #expect(segments.count == 2)
        #expect(Set(segments.map(\.seriesID)) == Set([oldID, currentID]))
        #expect(Set(segments.map(\.displayName)) == Set(["CPU热区最高温度 · 来源1", "CPU热区最高温度 · 来源2"]))
        #expect(Set(segments.map(\.id)).count == 2)
    }

    private func ready(points: [HistoryPoint], seriesID: SeriesID, pointLimit: Int, gaps: [Gap] = []) -> HistoryChartState {
        HistoryChartModel.makeReadyState(
            from: HistoryResult(layer: .ema, points: points, gaps: gaps,
                availableFromElapsedNS: 0, persistedThroughElapsedNS: nil),
            request: HistoryRequest(seriesIDs: [seriesID], range: .fiveMinutes,
                asOfElapsedNS: 300_000_000_000, pointLimit: pointLimit)
        )
    }

    private func point(seriesID: SeriesID, index: Int, segment: Int64) -> HistoryPoint {
        HistoryPoint(seriesID: seriesID, segment: segment, elapsedNS: Int64(index) * 100_000_000,
            wallUnixNS: nil, valueC: 50, minC: nil, maxC: nil, count: 1)
    }
}
