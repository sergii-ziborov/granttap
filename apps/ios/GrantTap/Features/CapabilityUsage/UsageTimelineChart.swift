import SwiftUI

/// When the work happened, not just how much of it there was.
struct UsageTimelineChart: View {
    let buckets: [UsageTimelineBucket]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(buckets) { bucket in
                        // A slice with calls always draws something: a bar of no
                        // height reads as a slice where nothing happened.
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bucket.failures > 0 ? Theme.riskHigh : accent)
                            .opacity(bucket.calls == 0 ? 0.12 : 1)
                            .frame(
                                height: bucket.calls == 0
                                    ? 2
                                    : max(3, geometry.size.height * bucket.fraction)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 44)

            if !buckets.isEmpty {
                // A day's window starts and ends at the same clock time, so
                // clock labels read as one moment; the distance is the point.
                HStack {
                    Text(L("a day ago"))
                    Spacer()
                    Text(L("now"))
                }
                .font(.caption2)
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 2)
    }

}
