import Foundation

struct CPUMaxDerivation {
    let maxBatchSpanNS: Int64

    init(maxBatchSpanMS: Int) {
        maxBatchSpanNS = Int64(maxBatchSpanMS) * 1_000_000
    }

    func derive(
        definition: SeriesDefinition,
        memberSamples: [SourceID: Sample],
        readings: [Reading],
        sessionID: SessionID,
        sampleSequence: inout Int64,
        segment: Int64,
        periodMS: Int
    ) -> Sample? {
        guard definition.formula == .maximum else {
            return nil
        }
        guard canDerive(definition: definition, memberSamples: memberSamples, readings: readings) else {
            return nil
        }

        let members = definition.memberSourceIDs.compactMap { memberSamples[$0] }
        guard let peak = members.max(by: { $0.valueC < $1.valueC }) else {
            return nil
        }
        let latest = members.max(by: { $0.timestamp.elapsedNS < $1.timestamp.elapsedNS }) ?? peak
        let sampleID = "\(sessionID.rawValue):\(sampleSequence)"
        sampleSequence += 1

        return Sample(
            sampleID: sampleID,
            seriesID: definition.seriesID,
            segment: segment,
            timestamp: latest.timestamp,
            periodMS: periodMS,
            valueC: peak.valueC,
            freshness: peak.freshness,
            sourceWallUnixNS: latest.sourceWallUnixNS,
            memberSampleIDs: members.map(\.sampleID).sorted()
        )
    }

    func canDerive(
        definition: SeriesDefinition,
        memberSamples: [SourceID: Sample],
        readings: [Reading]
    ) -> Bool {
        let expected = Set(definition.memberSourceIDs)
        guard expected.count == definition.memberSourceIDs.count else {
            return false
        }

        let memberReadings = readings.filter { expected.contains($0.sourceID) }
        guard memberReadings.count == expected.count else {
            return false
        }
        guard Set(memberReadings.map(\.sourceID)).count == expected.count else {
            return false
        }

        guard Set(memberSamples.keys) == expected else {
            return false
        }

        for reading in memberReadings {
            guard case .success = reading.outcome else {
                return false
            }
        }

        let elapsed = memberReadings.map(\.finished.elapsedNS)
        guard let minElapsed = elapsed.min(), let maxElapsed = elapsed.max() else {
            return false
        }
        return maxElapsed - minElapsed <= maxBatchSpanNS
    }
}
