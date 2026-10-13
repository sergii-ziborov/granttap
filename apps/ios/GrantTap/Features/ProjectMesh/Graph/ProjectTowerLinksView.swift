import SwiftUI

struct ProjectTowerLinksView: View {
    let path: String
    let map: ProjectCodeMap
    let roads: [ProjectCodeMap.Road]
    let onSelect: (String) -> Void

    private var links: [ProjectCodeMap.Road] { ProjectTowerInspection.links(path: path, roads: roads) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            Text("\(links.filter { $0.target == path }.count) \(L("incoming")) · \(links.filter { $0.source == path }.count) \(L("outgoing"))")
                .font(.caption).foregroundStyle(Theme.muted)
            if links.isEmpty {
                Text(L("No observed links in this report."))
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(links) { road in
                let incoming = road.target == path
                let neighbor = incoming ? road.source : road.target
                Button { onSelect(neighbor) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ProjectTowerInspection.displayName(path: neighbor, map: map))
                                .font(.subheadline).multilineTextAlignment(.leading)
                            Text(road.relation).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(Theme.ink).padding(10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
                }
                .pointerButtonStyle()
                .accessibilityIdentifier("code-towers.link.\(road.source).\(road.relation).\(road.target)")
            }
            if map.truncated {
                Text(L("Link counts describe the received map. Other repository connections may be missing."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}
