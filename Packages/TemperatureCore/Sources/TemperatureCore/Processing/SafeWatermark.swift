import Foundation

enum SafeWatermark {
    static func maximumClosureElapsedNS(
        nowElapsedNS: Int64,
        inFlightStartElapsedNS: [Int64]
    ) -> Int64 {
        guard let earliestStart = inFlightStartElapsedNS.min() else {
            return nowElapsedNS
        }
        let blockedWindowEndNS = ((earliestStart / AggregationWindow.oneSecondNS) + 1)
            * AggregationWindow.oneSecondNS
        return min(nowElapsedNS, blockedWindowEndNS - 1)
    }
}
