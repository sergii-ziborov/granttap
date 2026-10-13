import SwiftUI

struct ProjectTowerSectionsView: View {
    let sections: [ProjectTowerInspection.SourceSection]
    let selectedSymbol: String?
    let colors: [String: Color]
    let onSelect: (ProjectTowerInspection.SourceSection) -> Void

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if sections.isEmpty {
                        Text(L("No source sections were reported for this item."))
                            .foregroundStyle(Theme.muted).font(.subheadline)
                    }
                    ForEach(sections) { section in
                        Button { onSelect(section) } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(colors[section.symbol.id] ?? Theme.muted)
                                    .frame(width: 8, height: 34).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(section.symbol.label).font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.leading)
                                    Text("\(section.symbol.kind) · \(L("Line")) \(section.symbol.startLine) · \(section.symbol.lineCount) LOC")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption)
                            }
                            .foregroundStyle(Theme.ink).padding(10)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                section.symbol.id == selectedSymbol ? Theme.ink : Theme.line,
                                lineWidth: section.symbol.id == selectedSymbol ? 2 : 1))
                        }
                        .pointerButtonStyle()
                        .accessibilityIdentifier("code-towers.section.\(section.symbol.id)")
                        .accessibilityAddTraits(section.symbol.id == selectedSymbol ? .isSelected : [])
                        .id(section.symbol.id)
                    }
                }
            }
            .accessibilityIdentifier("code-towers.section-list")
            .onAppear {
                if let selectedSymbol { reader.scrollTo(selectedSymbol, anchor: .center) }
            }
            .onChange(of: selectedSymbol) { id in
                if let id { reader.scrollTo(id, anchor: .center) }
            }
        }
    }
}

struct ProjectTowerSectionDetails: View {
    let report: ProjectRepositoryGraph
    let section: ProjectTowerInspection.SourceSection
    var partialMap = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CompatNavigationStack {
            List {
                Section {
                    Text(section.symbol.label).font(.headline).textSelection(.enabled)
                        .accessibilityIdentifier("code-towers.section-details")
                    Text(section.path).font(Theme.mono(11)).textSelection(.enabled)
                }
                Section(L("Observed source")) {
                    fact(L("Kind"), section.symbol.kind)
                    fact(L("Start line"), "\(section.symbol.startLine)")
                    fact(L("Reported LOC"), "\(section.symbol.lineCount)")
                    Text(L("Source text was not included in this report."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Section(L("Report provenance")) {
                    fact(L("Repository"), report.repositoryId)
                    fact(L("Git revision"), report.sourceRevision ?? L("Not reported"))
                    fact(L("Analysis fingerprint"), report.revision)
                    fact("Weavatrix", report.weavatrixVersion)
                    fact(L("Analysis status"), report.analysisStatus ?? L("Not reported"))
                    if let id = report.analysisId { fact(L("Analysis ID"), id) }
                    if report.truncated || partialMap { Text(L("Partial evidence")).foregroundStyle(Theme.riskMed) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .pageNavigationTitle(L("Section details"), showsBack: false,
                                 actionPlacement: .confirmationAction) {
                Button(L("Done")) { dismiss() }
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.muted)
            Text(value).font(.subheadline).textSelection(.enabled)
        }
    }
}
