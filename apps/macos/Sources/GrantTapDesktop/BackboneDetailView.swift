import DesktopInspectorCore
import SwiftUI

struct BackboneDetailView: View {
    let backbone: InspectorBackbone?
    @State private var search = ""
    @State private var selection: Detail = .relations

    private enum Detail: String, CaseIterable {
        case relations = "Relations"
        case components = "Components"
    }

    var body: some View {
        if let backbone {
            HStack {
                LabeledContent("Components", value: String(backbone.nodes.count))
                LabeledContent("Relations", value: String(backbone.relations.count))
                LabeledContent("Pending candidates", value: String(backbone.pending_candidate_count))
            }
            Picker("Graph detail", selection: $selection) {
                ForEach(Detail.allCases, id: \.self) { detail in
                    Text(detail.rawValue).tag(detail)
                }
            }
            .pickerStyle(.segmented)
            TextField("Filter by component or relation", text: $search)
                .textFieldStyle(.roundedBorder)
            if selection == .relations {
                List(filteredRelations(backbone)) { relation in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(name(relation.source, in: backbone)) → \(name(relation.target, in: backbone))")
                            .font(.headline)
                        Text("\(relation.relation.replacingOccurrences(of: "_", with: " ")) · \(relation.evidence_count) evidence records")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                List(filteredNodes(backbone)) { node in
                    LabeledContent(node.display_name,
                                   value: node.kind.replacingOccurrences(of: "_", with: " "))
                }
            }
        } else {
            ContentUnavailableView("Backbone unavailable",
                                   systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    private func name(_ identity: String, in backbone: InspectorBackbone) -> String {
        backbone.nodes.first { $0.identity == identity }?.display_name ?? identity
    }

    private func filteredRelations(_ backbone: InspectorBackbone) -> [InspectorBackbone.Relation] {
        guard !search.isEmpty else { return backbone.relations }
        return backbone.relations.filter { relation in
            [relation.source, relation.target, relation.relation,
             name(relation.source, in: backbone), name(relation.target, in: backbone)]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    private func filteredNodes(_ backbone: InspectorBackbone) -> [InspectorBackbone.Node] {
        guard !search.isEmpty else { return backbone.nodes }
        return backbone.nodes.filter {
            [$0.identity, $0.display_name, $0.kind]
                .contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }
}
