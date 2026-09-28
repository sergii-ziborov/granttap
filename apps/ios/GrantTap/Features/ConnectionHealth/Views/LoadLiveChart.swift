import SwiftUI

/// The last two minutes as a line through every reading, placed by time.
///
/// The hour chart answers "what was it doing"; this one answers "what is it
/// doing", moving as readings arrive every few seconds. A number on its own
/// jumps; a line shows the jump was a spike, or was not.
struct LoadLiveChart: View {
    static let windowMs: Double = 2 * 60 * 1_000

    let points: [LoadHistoryPoint]
    let accent: Color
    var now: Double = Date().timeIntervalSince1970 * 1_000
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    let value: (LoadHistoryPoint) -> Double?

    /// Readings inside the window, oldest first, as time and value.
    var readings: [(at: Double, value: Double)] {
        LoadHistory.window(points, since: now - Self.windowMs, until: now, value: value)
    }

    var body: some View {
        let readings = readings
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(readings.last.map { format($0.value) } ?? L("No readings yet."))
                    .font(Theme.mono(13, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(L("last 2 minutes")).font(.caption2).foregroundStyle(Theme.muted)
            }
            GeometryReader { geometry in
                let size = geometry.size
                let ceiling = max(readings.map(\.value).max() ?? 0, 1)
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(Theme.line.opacity(0.35)).frame(height: 1)
                    Self.area(readings, in: size, since: now - Self.windowMs, until: now, ceiling: ceiling)
                        .fill(accent.opacity(0.16))
                    Self.line(readings, in: size, since: now - Self.windowMs, until: now, ceiling: ceiling)
                        .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    if let last = readings.last {
                        let point = Self.point(last, in: size, since: now - Self.windowMs, until: now, ceiling: ceiling)
                        Circle().fill(accent).frame(width: 6, height: 6).position(point)
                    }
                }
            }
            .frame(height: 48)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readings.last.map { format($0.value) } ?? L("No readings yet."))
    }

    static func point(
        _ reading: (at: Double, value: Double), in size: CGSize, since: Double, until: Double, ceiling: Double
    ) -> CGPoint {
        let span = max(until - since, 1)
        let x = CGFloat((reading.at - since) / span) * size.width
        let y = size.height - CGFloat(min(1, reading.value / ceiling)) * size.height
        return CGPoint(x: min(size.width, max(0, x)), y: y)
    }

    static func line(
        _ readings: [(at: Double, value: Double)], in size: CGSize, since: Double, until: Double, ceiling: Double
    ) -> Path {
        var path = Path()
        for (index, reading) in readings.enumerated() {
            let p = point(reading, in: size, since: since, until: until, ceiling: ceiling)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    static func area(
        _ readings: [(at: Double, value: Double)], in size: CGSize, since: Double, until: Double, ceiling: Double
    ) -> Path {
        var path = Path()
        guard readings.count > 1, let first = readings.first, let last = readings.last else { return path }
        path.move(to: CGPoint(x: point(first, in: size, since: since, until: until, ceiling: ceiling).x, y: size.height))
        for reading in readings {
            path.addLine(to: point(reading, in: size, since: since, until: until, ceiling: ceiling))
        }
        path.addLine(to: CGPoint(x: point(last, in: size, since: since, until: until, ceiling: ceiling).x, y: size.height))
        path.closeSubpath()
        return path
    }
}

extension LoadHistory {
    /// The readings inside a window, oldest first, as time and value.
    static func window(
        _ points: [LoadHistoryPoint], since: Double, until: Double, value: (LoadHistoryPoint) -> Double?
    ) -> [(at: Double, value: Double)] {
        points.compactMap { point in
            guard point.at >= since, point.at <= until, let reading = value(point) else { return nil }
            return (at: point.at, value: reading)
        }.sorted { $0.at < $1.at }
    }
}
