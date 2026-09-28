import SwiftUI

/// An hour of one number, one bar per slice of it.
///
/// Each bar is the highest reading in its two minutes, so a spike survives
/// and a lull is short. A slice the computer reported nothing for stays
/// empty rather than being drawn across, and the peak is labelled, because
/// the peak is what the person came to find.
struct LoadHistoryChart: View {
    let values: [Double?]
    let accent: Color
    let startLabel: String
    let endLabel: String
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    private var peak: Double { values.compactMap { $0 }.max() ?? 0 }
    private var hasReadings: Bool { values.contains { $0 != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(hasReadings ? String(format: L("peak %@"), format(peak)) : L("No readings yet."))
                    .font(.caption).foregroundStyle(Theme.muted)
                Spacer()
            }
            GeometryReader { geometry in
                let size = geometry.size
                let ceiling = max(peak, 1)
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(Theme.line.opacity(0.35)).frame(height: 1)
                    bars(in: size, ceiling: ceiling).fill(accent)
                }
            }
            .frame(height: 64)
            HStack {
                Text(startLabel)
                Spacer()
                Text(endLabel)
            }
            .font(.caption2).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasReadings ? String(format: L("peak %@"), format(peak)) : L("No readings yet."))
    }

    /// One rounded bar per slot, scaled to the peak; an empty slot draws nothing.
    private func bars(in size: CGSize, ceiling: Double) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        let step = size.width / CGFloat(values.count)
        let width = max(1.5, step * 0.62)
        for (index, value) in values.enumerated() {
            guard let value else { continue }
            let height = max(2, CGFloat(min(1, value / ceiling)) * size.height)
            let rect = CGRect(
                x: CGFloat(index) * step + (step - width) / 2, y: size.height - height,
                width: width, height: height
            )
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: width / 2, height: width / 2))
        }
        return path
    }
}
