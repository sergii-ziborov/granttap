import SwiftUI

struct ProjectGraphInspector: View {
    let node: ProjectGraphNode
    let graph: ProjectGraphModel
    let onClose: () -> Void

    var body: some View {
        let relations = graph.edges.filter { $0.source == node.id || $0.target == node.id }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(node.name).font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .accessibilityLabel(L("Close"))
            }
            Text(node.isOwn ? L("This Mesh") : node.available ? L("Bound on a computer") : L("Not currently bound"))
                .font(.caption)
            if node.openTasks > 0 {
                Text(LPlural(node.openTasks, one: "%d open task", many: "%d open tasks"))
                    .font(.caption)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(node.layers) { layer in
                        HStack(spacing: 7) {
                            Image(systemName: layer.kind == .task ? "square.stack.3d.up"
                                  : layer.kind == .computer ? "desktopcomputer" : "folder")
                                .frame(width: 18)
                            Text(layer.label).lineLimit(1)
                        }
                        .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            ForEach(relations) { edge in
                let otherID = edge.source == node.id ? edge.target : edge.source
                let other = graph.nodes.first { $0.id == otherID }?.name ?? otherID
                Text("\(edge.relation) · \(other)")
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityIdentifier("project.graph.inspector")
    }
}
