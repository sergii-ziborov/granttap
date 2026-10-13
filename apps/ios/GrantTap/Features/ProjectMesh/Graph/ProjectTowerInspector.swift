import SwiftUI

/// One expandable inspector keeps source sections, links and report health beside the scene.
struct ProjectTowerInspector: View {
    let report: ProjectRepositoryGraph
    let map: ProjectCodeMap
    let snapshot: ProjectTowerSnapshot
    @Binding var selectedPath: String?
    @Binding var selectedSymbol: String?
    let onFocus: () -> Void
    @State private var expanded = false
    @State private var tab = Tab.sections
    @State private var detail: Detail?
    @State private var lastDetailedSelection: Selection?

    private struct Selection: Equatable {
        let path: String?
        let symbol: String?
    }
    private struct Detail: Identifiable {
        let section: ProjectTowerInspection.SourceSection
        let report: ProjectRepositoryGraph
        let partialMap: Bool
        var id: String { "\(section.id)\u{0}\(report.revision)" }
    }
    private enum Tab: String, CaseIterable {
        case sections = "Sections", links = "Links", health = "Health"
    }
    private var file: ProjectCodeMap.File? { map.files.first { $0.path == selectedPath } }
    private var sections: [ProjectTowerInspection.SourceSection] {
        ProjectTowerInspection.sections(path: selectedPath ?? "", map: map)
    }

    private var selection: Selection { Selection(path: selectedPath, symbol: selectedSymbol) }
    private var segmentColors: [String: Color] {
        let tower = snapshot.towers.first { $0.id == selectedPath }
        return (tower?.segments ?? []).reduce(into: [:]) { result, segment in
            result[segment.id] = Color(red: Double(segment.color.x),
                green: Double(segment.color.y), blue: Double(segment.color.z))
        }
    }

    var body: some View {
        if let path = selectedPath {
            VStack(alignment: .leading, spacing: 10) {
                header(path)
                HStack(spacing: 6) {
                    ForEach(Tab.allCases, id: \.self) { value in
                        Button {
                            tab = value
                            expanded = true
                        } label: {
                            Text(L(value.rawValue)).font(.caption.weight(.semibold))
                                .foregroundStyle(expanded && tab == value ? Color.white : Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(expanded && tab == value ? Theme.actionFill : Theme.raised,
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                        .pointerButtonStyle()
                        .accessibilityIdentifier("code-towers.\(value.rawValue.lowercased())")
                    }
                }
                if expanded { content(path).frame(maxHeight: 260) }
            }
            .padding(12).foregroundStyle(Theme.ink)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
            .onAppear { synchronizeDetails() }
            .onChange(of: selection) { _ in synchronizeDetails() }
            .sheet(item: $detail) { value in
                ProjectTowerSectionDetails(report: value.report, section: value.section,
                                           partialMap: value.partialMap)
            }
        }
    }

    private func synchronizeDetails() {
        guard selection != lastDetailedSelection else { return }
        lastDetailedSelection = selection
        guard let id = selectedSymbol, let section = sections.first(where: { $0.symbol.id == id }) else {
            detail = nil
            return
        }
        tab = .sections
        expanded = true
        if detail?.section.id != section.id { present(section) }
    }

    private func present(_ section: ProjectTowerInspection.SourceSection) {
        detail = Detail(section: section, report: report, partialMap: map.truncated)
    }

    private func header(_ path: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ProjectTowerInspection.displayName(path: path, map: map))
                    .font(.subheadline.weight(.semibold)).lineLimit(2).textSelection(.enabled)
                    .accessibilityIdentifier(file == nil
                        ? "code-towers.inspector.external" : "code-towers.inspector.path")
                Text(summary).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            Button(action: onFocus) {
                Image(systemName: "scope").frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("Focus selected tower"))
            .accessibilityIdentifier("code-towers.inspector.focus")
            Button { expanded.toggle() } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(expanded ? L("Collapse tower details") : L("Expand tower details"))
            Button {
                selectedSymbol = nil
                selectedPath = nil
            } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("Close file details"))
        }
        .pointerButtonStyle()
    }

    private var summary: String {
        if let file {
            let loc = file.lineCount.map { "\($0) LOC" } ?? L("Line count unavailable")
            return "\(loc) · \(LPlural(file.symbols.count, one: "%d reported section", many: "%d reported sections"))"
        }
        return LPlural(sections.count, one: "%d reported section", many: "%d reported sections")
    }

    @ViewBuilder private func content(_ path: String) -> some View {
        switch tab {
        case .sections:
            ProjectTowerSectionsView(sections: sections, selectedSymbol: selectedSymbol,
                                     colors: segmentColors) { section in
                selectedSymbol = section.symbol.id
                onFocus()
                present(section)
            }
        case .links:
            ScrollView {
                ProjectTowerLinksView(path: path, map: map, roads: snapshot.roads) { neighbor in
                    selectedSymbol = nil
                    selectedPath = neighbor
                    onFocus()
                }
            }
        case .health:
            ScrollView {
                ProjectTowerHealthView(report: report, map: map, path: path, roads: snapshot.roads)
            }
            .accessibilityIdentifier("code-towers.health-scroll")
        }
    }
}
