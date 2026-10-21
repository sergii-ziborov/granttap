import SwiftUI

struct ProjectTowerHealthView: View {
    let report: ProjectRepositoryGraph
    let map: ProjectCodeMap
    let path: String
    let roads: [ProjectCodeMap.Road]

    private var file: ProjectCodeMap.File? { map.files.first { $0.path == path } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label(L("Observed source"), systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                if let file {
                    fact(L("Reported LOC"), file.lineCount.map(String.init) ?? L("Not reported"))
                    fact(L("Language"), file.language ?? L("Not reported"))
                }
                fact(L("Reported sections"), "\(ProjectTowerInspection.sections(path: path, map: map).count)")
                fact(L("Observed links"), "\(ProjectTowerInspection.links(path: path, roads: roads).count)")
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label(L("Health assessment"), systemImage: "heart.text.square")
                    .font(.subheadline.weight(.semibold))
                Text(L("No structural health score was reported."))
                    .font(.subheadline)
                Text(L("Test coverage and runtime performance were not measured."))
                    .font(.caption).foregroundStyle(Theme.muted)
                if ProjectTowerInspection.links(path: path, roads: roads).isEmpty {
                    Text(L("No links were observed for this item. Unused-code status remains unknown."))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Report provenance")).font(.subheadline.weight(.semibold))
                fact(L("Analysis status"), report.analysisStatus ?? L("Not reported"))
                fact(L("Git revision"), report.sourceRevision ?? L("Not reported"))
                fact(L("Analysis fingerprint"), report.revision)
                fact("Weavatrix", report.weavatrixVersion)
                if let error = report.analysisErrorCode { fact(L("Analysis diagnostic"), error) }
                if report.truncated || map.truncated {
                    Label(L("Partial evidence"), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Theme.riskMed)
                }
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(Theme.muted)
            Text(value).font(.subheadline).textSelection(.enabled)
        }
    }
}
