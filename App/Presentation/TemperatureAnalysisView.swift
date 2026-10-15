import SwiftUI
import TemperatureCore
import TemperaturePresentation

struct TemperatureAnalysisView: View {
    let analysis: TemperatureAnalysisSnapshot
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            Text("温度分析").font(.headline)
            Text(TemperatureAnalysisFormatting.systemText(analysis.systemThermalState))
                .accessibilityIdentifier("analysis.systemThermalState")
            Text(TemperatureAnalysisFormatting.rawText(analysis.cpu))
                .monospacedDigit()
                .accessibilityIdentifier("analysis.raw")
            Text(TemperatureAnalysisFormatting.assessmentText(analysis.cpu))
                .accessibilityIdentifier("analysis.cpuAssessment")
            Text(TemperatureAnalysisFormatting.trendText(analysis.cpu))
                .monospacedDigit()
                .accessibilityIdentifier("analysis.trend")
            Text("建议：" + TemperatureAnalysisFormatting.adviceText(analysis.advice))
                .accessibilityIdentifier("analysis.advice")
            if !compact {
                Text("Raw用于CPU阈值判断；主温度与曲线显示EMA。系统热状态反映整机，参考阈值不代表硬件安全上限。")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
