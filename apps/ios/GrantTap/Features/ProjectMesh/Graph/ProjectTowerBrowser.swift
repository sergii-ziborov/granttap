import SwiftUI

struct ProjectTowerBrowser: View {
    let map: ProjectCodeMap
    let onSelect: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var groups: [ProjectTowerInspection.BrowserGroup] {
        ProjectTowerInspection.browserGroups(map: map, query: query)
    }

    var body: some View {
        CompatNavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField(L("Find a file or section"), text: $query)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("code-towers.browser.search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel(L("Clear search"))
                    }
                }
                .padding(12).background(Theme.surface)
                List {
                    Section {
                        Text("\(map.files.count) / \(map.totalFiles) \(L("reported files"))")
                            .font(.caption).foregroundStyle(Theme.muted)
                        if map.truncated { Text(L("Partial map")).foregroundStyle(Theme.riskMed) }
                    }
                    if groups.isEmpty {
                        Text(L("No matching files or sections.")).foregroundStyle(Theme.muted)
                    }
                    ForEach(groups) { group in
                        Section(group.name == "(root)" ? L("Repository root") : group.name) {
                            ForEach(group.files) { item in
                                fileRow(item.file)
                                ForEach(item.symbols) { symbol in
                                    Button { select(item.file.path, symbol.id) } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "curlybraces").foregroundStyle(Theme.muted)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(symbol.label).font(.subheadline.weight(.semibold))
                                                Text("\(symbol.kind) · \(L("Line")) \(symbol.startLine)")
                                                    .font(.caption).foregroundStyle(Theme.muted)
                                            }
                                            Spacer(minLength: 4)
                                            Image(systemName: "chevron.right").font(.caption)
                                        }
                                        .foregroundStyle(Theme.ink).padding(.leading, 16)
                                    }
                                    .accessibilityIdentifier("code-towers.browser.section.\(symbol.id)")
                                }
                            }
                        }
                    }
                }
            }
            .background(Theme.bg)
            .navigationBarTitleDisplayMode(.inline)
            .pageNavigationTitle(L("Files and sections"), showsBack: false,
                                 actionPlacement: .confirmationAction) {
                Button(L("Done")) { dismiss() }
            }
        }
    }

    private func fileRow(_ file: ProjectCodeMap.File) -> some View {
        Button { select(file.path, nil) } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                    Text(file.path).font(Theme.mono(10)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer(minLength: 4)
                Text(file.language ?? "—").font(.caption).foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.ink).padding(.vertical, 4)
        }
        .accessibilityIdentifier("code-towers.file.\(file.path)")
    }

    private func select(_ path: String, _ symbolId: String?) {
        onSelect(path, symbolId)
        dismiss()
    }
}
