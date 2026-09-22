import SwiftUI
import TemperatureCore
import TemperaturePresentation

struct TemperatureSourceRow: View {
    let row: TemperatureRowState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(TemperatureFormatting.rowText(row.value))
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityIdentifier("source.list")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.title)
        .accessibilityValue(TemperatureFormatting.rowText(row.value))
    }
}
