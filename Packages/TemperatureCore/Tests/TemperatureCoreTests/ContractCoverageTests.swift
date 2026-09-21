import Foundation
import Testing
@testable import TemperatureCore

@Suite struct ContractCoverageTests {
    @Test func taggedUUIDTypesEncodeAndDecode() throws {
        let raw = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let session = try SessionID(validating: raw)
        let source = try SourceID(validating: raw)
        let series = try SeriesID(validating: raw)
        let request = try RequestID(validating: raw)
        let batch = try BatchID(validating: raw)
        let gap = try GapID(validating: raw)
        let watermark = try WatermarkEventID(validating: raw)
        #expect(try JSONDecoder().decode(SessionID.self, from: JSONEncoder().encode(session)) == session)
        #expect(try JSONDecoder().decode(SourceID.self, from: JSONEncoder().encode(source)) == source)
        #expect(try JSONDecoder().decode(SeriesID.self, from: JSONEncoder().encode(series)) == series)
        #expect(try JSONDecoder().decode(RequestID.self, from: JSONEncoder().encode(request)) == request)
        #expect(try JSONDecoder().decode(BatchID.self, from: JSONEncoder().encode(batch)) == batch)
        #expect(try JSONDecoder().decode(GapID.self, from: JSONEncoder().encode(gap)) == gap)
        #expect(try JSONDecoder().decode(WatermarkEventID.self, from: JSONEncoder().encode(watermark)) == watermark)
    }

    @Test func sessionMetadataRoundTrip() throws {
        let original = SessionMetadata(
            sessionID: try SessionID(validating: "00000000-0000-4000-8000-000000000099"),
            startedWallUnixNS: 1_700_000_000_000_000_000,
            model: "Mac16,13",
            osBuild: "24G419",
            appVersion: "0.1.0"
        )
        let decoded = try JSONDecoder().decode(
            SessionMetadata.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }

    @Test func sensorTransportAndQualifiedCatalogRoundTrip() throws {
        let discovered = DiscoveredCatalog(
            generation: 2,
            sources: [
                DiscoveredSource(
                    transportHandle: "smc:Tp01",
                    provider: .smc,
                    rawKey: "Tp01",
                    registryID: "reg-1",
                    encoding: "flt ",
                    byteCount: 4
                )
            ]
        )
        let catalog = QualifiedSourceCatalog(
            generation: 2,
            available: [Fixtures.source()],
            unavailable: [
                SourceCapabilityRecord(
                    provider: .nvme,
                    rawKey: nil,
                    registryID: nil,
                    intendedKind: .ssd,
                    capability: .unsupported,
                    reason: "fixture"
                )
            ]
        )
        let transportRequest = TransportReadRequest(
            requestID: RequestID(Fixtures.uuid(201)),
            generation: 2,
            transportHandles: ["smc:Tp01"],
            requestedPeriodMS: 200
        )
        let transportBatch = TransportReadBatch(
            requestID: RequestID(Fixtures.uuid(201)),
            generation: 2,
            readings: [
                TransportReading(
                    transportHandle: "smc:Tp01",
                    started: Fixtures.timestamp(ms: 0),
                    finished: Fixtures.timestamp(ms: 1),
                    outcome: .success(valueC: 25.5, sourceWallUnixNS: nil, freshness: .unknown)
                )
            ]
        )
        for value: any Encodable in [discovered, catalog, transportRequest, transportBatch] {
            let data = try JSONEncoder().encode(value)
            #expect(!data.isEmpty)
        }
    }

    @Test func readAndPersistenceBatchRoundTrip() throws {
        let read = Fixtures.read(id: RequestID(Fixtures.uuid(301)), ms: 100, values: [80, 81])
        let batch = try Fixtures.persistence(id: BatchID(Fixtures.uuid(302)), value: 80, ms: 100)
        let readDecoded = try JSONDecoder().decode(ReadBatch.self, from: JSONEncoder().encode(read))
        let batchDecoded = try JSONDecoder().decode(PersistenceBatch.self, from: JSONEncoder().encode(batch))
        #expect(readDecoded == read)
        #expect(batchDecoded.batchID == batch.batchID)
        #expect(batchDecoded.raw.count == 1)
    }

    @Test func processingReceiptAndPersistenceOwnerRoundTrip() throws {
        let receipt = ProcessingReceipt(
            batchID: BatchID(Fixtures.uuid(401)),
            acceptedRecords: 3,
            snapshotGeneration: 7
        )
        let owners: [PersistenceOwner] = [
            .request(RequestID(Fixtures.uuid(402))),
            .gap(GapID(Fixtures.uuid(403))),
            .watermark(WatermarkEventID(Fixtures.uuid(404))),
        ]
        let receiptDecoded = try JSONDecoder().decode(
            ProcessingReceipt.self,
            from: JSONEncoder().encode(receipt)
        )
        #expect(receiptDecoded == receipt)
        for owner in owners {
            let decoded = try JSONDecoder().decode(PersistenceOwner.self, from: JSONEncoder().encode(owner))
            #expect(decoded == owner)
        }
    }

    @Test func historyAndGapRoundTrip() throws {
        let gap = Gap(
            gapID: GapID(Fixtures.uuid(501)),
            seriesID: SeriesID(Fixtures.uuid(101)),
            startedElapsedNS: 0,
            endedElapsedNS: 1_000_000_000,
            reason: .sleep
        )
        let point = HistoryPoint(
            seriesID: SeriesID(Fixtures.uuid(101)),
            segment: 1,
            elapsedNS: 500_000_000,
            wallUnixNS: nil,
            valueC: 70,
            minC: 68,
            maxC: 72,
            count: 5
        )
        let result = HistoryResult(
            layer: .oneSecond,
            points: [point],
            gaps: [gap],
            availableFromElapsedNS: 0,
            persistedThroughElapsedNS: 1_000_000_000
        )
        let gapDecoded = try JSONDecoder().decode(Gap.self, from: JSONEncoder().encode(gap))
        #expect(gapDecoded == gap)
        #expect(result.layer == .oneSecond)
        #expect(result.points.count == 1)
    }

    @Test func bucketTrendAndSampleRoundTrip() throws {
        let sample = Sample(
            sampleID: "s:1",
            seriesID: SeriesID(Fixtures.uuid(101)),
            segment: 1,
            timestamp: Fixtures.timestamp(ms: 10),
            periodMS: 200,
            valueC: 55.5,
            freshness: .sourceTimestamp,
            sourceWallUnixNS: 1_700_000_000_000_000_000,
            memberSampleIDs: ["m:1"]
        )
        let bucket = Bucket(
            seriesID: SeriesID(Fixtures.uuid(101)),
            segment: 1,
            widthSeconds: 1,
            startElapsedNS: 0,
            endElapsedNS: 1_000_000_000,
            minC: 50,
            maxC: 60,
            sumC: 220,
            count: 4,
            latestC: 55,
            latestElapsedNS: 900_000_000,
            latestSampleID: "s:1",
            isPartial: false,
            coverageNS: 1_000_000_000
        )
        let trend = TrendValue(
            seriesID: SeriesID(Fixtures.uuid(101)),
            segment: 1,
            at: Fixtures.timestamp(ms: 10),
            slopeCPerSecond: 0.02,
            direction: .stable,
            pointCount: 3
        )
        let sampleDecoded = try JSONDecoder().decode(Sample.self, from: JSONEncoder().encode(sample))
        let bucketDecoded = try JSONDecoder().decode(Bucket.self, from: JSONEncoder().encode(bucket))
        let trendDecoded = try JSONDecoder().decode(TrendValue.self, from: JSONEncoder().encode(trend))
        #expect(sampleDecoded == sample)
        #expect(bucketDecoded == bucket)
        #expect(trendDecoded == trend)
    }

    @Test func presentationAndMonitorFailureRoundTrip() throws {
        let failure = MonitorFailure(
            code: .databaseWrite,
            severity: .fatal,
            component: "storage",
            operation: "commit",
            retryCount: 5,
            sourceID: SourceID(Fixtures.uuid(1)),
            underlyingCode: "SQLITE_BUSY"
        )
        let row = TemperatureRowState(
            sourceID: SourceID(Fixtures.uuid(1)),
            metricID: try MetricID(validating: "cpu.zone.max"),
            title: "CPU热区最高温度",
            evidence: .referenceClassified,
            value: .live(valueC: 42.0, observedAt: Fixtures.timestamp(ms: 0))
        )
        let section = TemperatureSectionState(id: .cpu, title: "CPU", rows: [row])
        let chart = HistoryChartState.ready(
            series: [
                HistorySeriesState(
                    seriesID: SeriesID(Fixtures.uuid(101)),
                    displayName: "CPU",
                    colorToken: "cpu",
                    layer: .ema,
                    points: []
                )
            ],
            gaps: []
        )
        let running = PresentationState.running(
            RunningPresentationState(
                asOf: Fixtures.timestamp(ms: 0),
                cpuPeriodMS: 200,
                primaryCPU: .live(valueC: 42.0, observedAt: Fixtures.timestamp(ms: 0)),
                sections: [section],
                chart: chart
            )
        )
        let failureDecoded = try JSONDecoder().decode(MonitorFailure.self, from: JSONEncoder().encode(failure))
        #expect(failureDecoded == failure)
        if case .running(let state) = running {
            #expect(state.cpuPeriodMS == 200)
            #expect(state.sections.count == 1)
        } else {
            Issue.record("expected running presentation")
        }
    }

    @Test func machBasisAndSystemClockSleepPastDeadline() async throws {
        let basis = MachClockBasis.current()
        let elapsed = basis.elapsedNanoseconds(at: mach_continuous_time())
        #expect(elapsed >= 0)
        let clock = SystemClock(basis: basis)
        try await clock.sleep(untilElapsedNS: clock.now().elapsedNS - 1)
    }

    @Test func configurationLoadsFromTemporaryFiles() throws {
        let defaultsURL = Fixtures.packageRoot.appendingPathComponent("Sources/TemperatureCore/Resources/defaults-v1.json")
        let profileURL = Fixtures.packageRoot.appendingPathComponent("Sources/TemperatureCore/Resources/first-profile-v1.json")
        let configuration = try Configuration.load(from: defaultsURL)
        let profile = try Configuration.loadProfile(from: profileURL)
        #expect(configuration.contractVersion == 2)
        #expect(profile.cpuKeys.count == 12)
    }

    @Test func configurationUnreadableFileThrows() {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).json")
        #expect(throws: ConfigurationError.unreadable(missing.path)) {
            _ = try Configuration.load(from: missing)
        }
    }
}
