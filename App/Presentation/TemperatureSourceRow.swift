import SwiftUI
import TemperatureCore
import TemperaturePresentation

struct TemperatureSourceRow: View {
    let row: TemperatureRowState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.title)
                Spacer(minLength: 8)
                Text(TemperatureFormatting.rowText(row.value))
                    .font(.system(.body, design: .monospaced))
            }
            Text(TemperatureFormatting.stateDescription(row.value))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("temperature.state.\(row.metricID.rawValue)")
        }
        .accessibilityIdentifier("source.list")
        .help(sourceDetails)
        .accessibilityElement(children: .contain)
    }

    private var sourceDetails: String {
        let identity = row.sourceID?.rawValue ?? "无合格来源"
        return "来源身份：\(identity)\n指标：\(row.metricID.rawValue)\n映射依据：\(row.evidence.rawValue)\n温度来源不等同于物理核心。"
    }
}
