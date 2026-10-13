import SwiftUI

/// File and symbol matches have separate actions, preserving the meaning of each row.
struct ProjectTowerSearchResults: View {
    let map: ProjectCodeMap
    let query: String
    let onSelect: (String, String?) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(ProjectTowerInspection.browserGroups(map: map, query: query)) { group in
                    ForEach(group.files) { value in
                        Button { onSelect(value.file.path, nil) } label: {
                            Text(value.file.path).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                        .accessibilityIdentifier("code-towers.file.\(value.file.path)")
                        ForEach(value.symbols) { symbol in
                            Button { onSelect(value.file.path, symbol.id) } label: {
                                HStack {
                                    Image(systemName: "curlybraces")
                                    Text("\(symbol.label) · \(L("Line")) \(symbol.startLine)").lineLimit(2)
                                    Spacer(minLength: 4)
                                }.padding(8)
                            }
                            .accessibilityIdentifier("code-towers.search.section.\(symbol.id)")
                        }
                    }
                }
                ForEach((map.externals ?? []).filter { $0.label.localizedStandardContains(query) }) { value in
                    Button { onSelect(value.id, nil) } label: { Text(value.label).padding(8) }
                        .accessibilityIdentifier("code-towers.external.\(value.id)")
                }
            }
        }.frame(maxHeight: 170)
    }
}
