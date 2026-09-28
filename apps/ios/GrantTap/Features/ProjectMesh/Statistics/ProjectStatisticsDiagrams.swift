import SwiftUI

struct ProjectStatisticValue: Identifiable {
    let label: String
    let count: Int
    let color: Color
    var id: String { label }
}

struct ProjectStatisticBars: View {
    let values: [ProjectStatisticValue]

    private var maximum: Int { max(values.map(\.count).max() ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(values) { value in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(value.label)
                        Spacer()
                        Text(value.count.formatted()).fontWeight(.semibold)
                    }
                    .font(.caption)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(value.color.opacity(0.12))
                            if value.count > 0 {
                                Capsule().fill(value.color)
                                    .frame(width: max(4, geometry.size.width
                                        * CGFloat(value.count) / CGFloat(maximum)))
                            }
                        }
                    }
                    .frame(height: 12)
                    .accessibilityLabel("\(value.label): \(value.count)")
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct ProjectTaskStateDiagram: View {
    let tasks: [ProjectMeshTask]

    private var slices: [ProjectStatisticValue] {
        let states = Dictionary(grouping: tasks, by: \.state).mapValues(\.count)
        return [
            .init(label: L("Planned"), count: states["planned"] ?? 0, color: .gray),
            .init(label: L("Working"), count: states["working"] ?? 0, color: .green),
            .init(label: L("Blocked"), count: states["blocked"] ?? 0, color: .orange),
            .init(label: L("Needs You"), count: states["needs_user"] ?? 0, color: .red),
            .init(label: L("Handoff"), count: states["handoff"] ?? 0, color: .purple),
            .init(label: L("Completed"), count: states["completed"] ?? 0, color: .blue),
            .init(label: L("Failed"), count: states["failed"] ?? 0, color: .brown),
        ].filter { $0.count > 0 }
    }

    var body: some View {
        let values = slices
        if values.isEmpty {
            Text(L("No tasks in this snapshot."))
                .foregroundStyle(Theme.muted)
        } else {
            HStack(spacing: 22) {
                ring(values)
                    .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(values) { value in
                        HStack(spacing: 6) {
                            Circle().fill(value.color).frame(width: 8, height: 8)
                            Text(value.label).lineLimit(1)
                            Spacer(minLength: 3)
                            Text(value.count.formatted()).fontWeight(.semibold)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }

    private func ring(_ values: [ProjectStatisticValue]) -> some View {
        let total = CGFloat(max(tasks.count, 1))
        return ZStack {
            Circle().stroke(Theme.muted.opacity(0.16), lineWidth: 15)
            ForEach(values.indices, id: \.self) { index in
                let before = CGFloat(values.prefix(index).reduce(0) { $0 + $1.count }) / total
                let after = before + CGFloat(values[index].count) / total
                Circle().trim(from: before, to: after)
                    .stroke(values[index].color, style: StrokeStyle(lineWidth: 15, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Text(tasks.count.formatted()).font(.title2.weight(.bold))
        }
    }
}
