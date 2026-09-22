import Foundation
import Testing
@testable import TemperatureCore
@testable import TemperaturePresentation

@Suite struct HistoryChartModelTests {
    @Test func chartStatesAreMutuallyExclusive() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000101")
        let previous = [try sampleSeries(seriesID: seriesID, segment: 1, values: [50, 60])]

        let loading = HistoryChartModel.beginLoading(previous: previous)
        if case let .loading(storedPrevious) = loading {
            #expect(storedPrevious == previous)
        } else {
            Issue.record("expected loading state")
        }

        let ready = HistoryChartModel.makeReadyState(
            from: try sampleHistory(seriesID: seriesID, segment: 1, values: [70, 80]),
            request: try sampleRequest(seriesID: seriesID, range: .oneHour)
        )
        if case let .ready(series, gaps) = ready {
            #expect(series.count == 1)
            #expect(gaps.isEmpty)
        } else {
            Issue.record("expected ready state")
        }

        let failed = HistoryChartModel.makeFailedState(
            MonitorFailure(
                code: .databaseRead,
                severity: .fatal,
                component: "test",
                operation: "history",
                retryCount: 0,
                sourceID: nil,
                underlyingCode: nil
            ),
            previous: previous
        )
        if case let .failed(_, storedPrevious) = failed {
            #expect(storedPrevious == previous)
        } else {
            Issue.record("expected failed state")
        }
    }

    @Test func failedStateDoesNotPromotePreviousToReady() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000101")
        let previous = [try sampleSeries(seriesID: seriesID, segment: 1, values: [50, 60])]
        let failed = HistoryChartModel.makeFailedState(
            MonitorFailure(
                code: .databaseRead,
                severity: .fatal,
                component: "test",
                operation: "history",
                retryCount: 0,
                sourceID: nil,
                underlyingCode: nil
            ),
            previous: previous
        )
        #expect(HistoryChartModel.plotSegments(from: failed).isEmpty)
        if case let .failed(_, storedPrevious) = failed {
            #expect(storedPrevious == previous)
        } else {
            Issue.record("expected failed state")
        }
    }

    @Test func plotSegmentsBreakOnSegmentBoundaries() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000101")
        let points = [
            try historyPoint(seriesID: seriesID, segment: 1, elapsedMS: 100, valueC: 50, maxC: nil),
            try historyPoint(seriesID: seriesID, segment: 1, elapsedMS: 200, valueC: 55, maxC: nil),
            try historyPoint(seriesID: seriesID, segment: 2, elapsedMS: 300, valueC: 60, maxC: nil),
        ]
        let ready: HistoryChartState = .ready(
            series: [
                HistorySeriesState(
                    seriesID: seriesID,
                    displayName: "CPU Max",
                    colorToken: "cpu",
                    layer: .oneSecond,
                    points: points
                )
            ],
            gaps: []
        )
        let segments = HistoryChartModel.plotSegments(from: ready)
        #expect(segments.count == 2)
        #expect(segments.map(\.segment) == [1, 2])
    }

    @Test func peakMaxIsPreservedFromEnvelope() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000101")
        let ready = HistoryChartModel.makeReadyState(
            from: HistoryResult(
                layer: .tenSeconds,
                points: [
                    try historyPoint(seriesID: seriesID, segment: 1, elapsedMS: 100, valueC: 50, maxC: 50),
                    try historyPoint(seriesID: seriesID, segment: 1, elapsedMS: 200, valueC: 70, maxC: 99),
                    try historyPoint(seriesID: seriesID, segment: 1, elapsedMS: 300, valueC: 55, maxC: 55),
                ],
                gaps: [],
                availableFromElapsedNS: 100_000_000,
                persistedThroughElapsedNS: 300_000_000
            ),
            request: try sampleRequest(seriesID: seriesID, range: .oneDay)
        )
        #expect(HistoryChartModel.peakMaxC(in: ready) == 99)
    }

    @Test func multipleSeriesAreRetainedUpToLimit() throws {
        var seriesIDs: [SeriesID] = []
        var points: [HistoryPoint] = []
        for index in 0 ..< 9 {
            let uuid = String(format: "00000000-0000-4000-8000-%012d", 101 + index)
            let seriesID = try SeriesID(validating: uuid)
            seriesIDs.append(seriesID)
            points.append(
                try historyPoint(
                    seriesID: seriesID,
                    segment: 1,
                    elapsedMS: Int64(100 + index),
                    valueC: Double(40 + index),
                    maxC: nil
                )
            )
        }
        let ready = HistoryChartModel.makeReadyState(
            from: HistoryResult(
                layer: .oneSecond,
                points: points,
                gaps: [],
                availableFromElapsedNS: 100_000_000,
                persistedThroughElapsedNS: 900_000_000
            ),
            request: HistoryRequest(
                seriesIDs: seriesIDs,
                range: .oneHour,
                asOfElapsedNS: 900_000_000,
                pointLimit: 2000
            )
        )
        if case let .ready(series, _) = ready {
            #expect(series.count == HistoryChartModel.maxSeries)
        } else {
            Issue.record("expected ready state")
        }
    }

    @Test func gapsAreIncludedInReadyState() throws {
        let seriesID = try SeriesID(validating: "00000000-0000-4000-8000-000000000101")
        let gap = Gap(
            gapID: try GapID(validating: "00000000-0000-4000-8000-000000000901"),
            seriesID: seriesID,
            startedElapsedNS: 150_000_000,
            endedElapsedNS: 250_000_000,
            reason: .readFailure
        )
        let ready = HistoryChartModel.makeReadyState(
            from: HistoryResult(
                layer: .ema,
                points: [
                    try historyPoint(seriesID: seriesID, segment: 1, elapsedMS: 100, valueC: 50, maxC: nil),
                    try historyPoint(seriesID: seriesID, segment: 1, elapsedMS: 300, valueC: 60, maxC: nil),
                ],
                gaps: [gap],
                availableFromElapsedNS: 100_000_000,
                persistedThroughElapsedNS: 300_000_000
            ),
            request: try sampleRequest(seriesID: seriesID, range: .fiveMinutes)
        )
        if case let .ready(_, gaps) = ready {
            #expect(gaps.count == 1)
            #expect(gaps[0].reason == .readFailure)
        } else {
            Issue.record("expected ready state")
        }
    }
}

private func sampleRequest(seriesID: SeriesID, range: HistoryRange) throws -> HistoryRequest {
    HistoryRequest(
        seriesIDs: [seriesID],
        range: range,
        asOfElapsedNS: 300_000_000,
        pointLimit: 2000
    )
}

private func sampleHistory(seriesID: SeriesID, segment: Int64, values: [Double]) throws -> HistoryResult {
    HistoryResult(
        layer: .oneSecond,
        points: try values.enumerated().map { index, value in
            try historyPoint(
                seriesID: seriesID,
                segment: segment,
                elapsedMS: Int64(100 + index * 100),
                valueC: value,
                maxC: nil
            )
        },
        gaps: [],
        availableFromElapsedNS: 100_000_000,
        persistedThroughElapsedNS: Int64(100 + values.count * 100) * 1_000_000
    )
}

private func sampleSeries(seriesID: SeriesID, segment: Int64, values: [Double]) throws -> HistorySeriesState {
    HistorySeriesState(
        seriesID: seriesID,
        displayName: "CPU Max",
        colorToken: "cpu",
        layer: .oneSecond,
        points: try values.enumerated().map { index, value in
            try historyPoint(
                seriesID: seriesID,
                segment: segment,
                elapsedMS: Int64(100 + index * 100),
                valueC: value,
                maxC: nil
            )
        }
    )
}

private func historyPoint(
    seriesID: SeriesID,
    segment: Int64,
    elapsedMS: Int64,
    valueC: Double,
    maxC: Double?
) throws -> HistoryPoint {
    HistoryPoint(
        seriesID: seriesID,
        segment: segment,
        elapsedNS: elapsedMS * 1_000_000,
        wallUnixNS: nil,
        valueC: valueC,
        minC: maxC.map { min($0, valueC) },
        maxC: maxC,
        count: 1
    )
}
