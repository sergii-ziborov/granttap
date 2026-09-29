import SwiftUI

enum MacGraphMode: String, CaseIterable, Identifiable {
    case components, code, repositories
    var id: Self { self }
    var title: String {
        switch self {
        case .components: return L("Components")
        case .code: return L("Code city")
        case .repositories: return L("Repositories")
        }
    }
}

/// Positions come from the repository identity order, never from task titles.
enum ProjectRepositoryNetworkLayout {
    static func positions(_ nodes: [ProjectGraphNode], size: CGSize) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        let ordered = nodes.sorted { $0.id < $1.id }
        let columns = max(1, Int(ceil(sqrt(Double(ordered.count)))))
        let rows = Int(ceil(Double(ordered.count) / Double(columns)))
        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { index, node in
            let column = index % columns
            let row = index / columns
            let point = CGPoint(x: size.width * CGFloat(column + 1) / CGFloat(columns + 1),
                                y: size.height * CGFloat(row + 1) / CGFloat(rows + 1))
            return (node.id, point)
        })
    }
}

struct ProjectRepositoryNetworkView: View {
    let snapshot: ProjectMeshSnapshot
    @State private var selectedId: String?

    private var graph: ProjectGraphModel { .make(from: snapshot) }
    private var height: CGFloat {
        let columns = max(1, Int(ceil(sqrt(Double(graph.nodes.count)))))
        return max(440, CGFloat(Int(ceil(Double(graph.nodes.count) / Double(columns))) * 130))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Repository connections")).font(.headline)
                Text(L("Only verified Mesh relations are drawn. Select a repository for its computers, tasks and components."))
                    .font(.caption).foregroundStyle(Theme.muted)
                GeometryReader { geometry in
                    let positions = ProjectRepositoryNetworkLayout.positions(graph.nodes,
                        size: geometry.size)
                    ZStack {
                        Canvas { context, _ in
                            for edge in graph.edges {
                                guard let source = positions[edge.source],
                                      let target = positions[edge.target] else { continue }
                                var path = Path()
                                path.move(to: source)
                                path.addLine(to: target)
                                context.stroke(path, with: .color(Theme.codex.opacity(0.75)),
                                    lineWidth: 2)
                            }
                        }
                        ForEach(graph.nodes) { node in
                            Button { selectedId = node.id } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "folder.badge.gearshape")
                                    Text(node.name).lineLimit(2)
                                    if node.openTasks > 0 {
                                        Text(LPlural(node.openTasks, one: "%d open task",
                                            many: "%d open tasks")).font(.caption2)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .frame(width: 140, height: 72)
                                .foregroundStyle(Theme.ink)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(node.isOwn ? Theme.codex : Theme.line, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .position(positions[node.id] ?? .zero)
                            .accessibilityIdentifier("project.graph.repository.\(node.id)")
                        }
                    }
                }
                .frame(height: height)
                if let selectedId, let node = graph.nodes.first(where: { $0.id == selectedId }) {
                    ProjectGraphInspector(node: node, graph: graph) { self.selectedId = nil }
                }
                if graph.edges.isEmpty {
                    Text(L("No verified cross-repository relation is reported for this Mesh."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }.padding()
        }
        .accessibilityIdentifier("project.graph.repositories")
    }
}
