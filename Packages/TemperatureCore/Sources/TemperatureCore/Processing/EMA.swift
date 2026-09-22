import Foundation

enum EMAError: Error, Sendable, Equatable {
    case nonPositiveDeltaTime
}

struct EMAProcessor {
    let tauSeconds: KindSeconds

    func tau(for kind: SensorKind) -> Double {
        switch kind {
        case .cpuMain, .cpuZone:
            tauSeconds.cpuZone
        case .ssd:
            tauSeconds.ssd
        case .battery:
            tauSeconds.battery
        }
    }

    func nextEMA(raw: Sample, previous: EMAValue?, kind: SensorKind) throws -> EMAValue {
        guard let previous else {
            return EMAValue(
                sampleID: raw.sampleID,
                seriesID: raw.seriesID,
                segment: raw.segment,
                timestamp: raw.timestamp,
                valueC: raw.valueC
            )
        }

        let dt = Double(raw.timestamp.elapsedNS - previous.timestamp.elapsedNS) / 1_000_000_000
        guard dt > 0 else {
            throw EMAError.nonPositiveDeltaTime
        }

        let alpha = -expm1(-dt / tau(for: kind))
        let valueC = previous.valueC + alpha * (raw.valueC - previous.valueC)
        return EMAValue(
            sampleID: raw.sampleID,
            seriesID: raw.seriesID,
            segment: raw.segment,
            timestamp: raw.timestamp,
            valueC: valueC
        )
    }
}
