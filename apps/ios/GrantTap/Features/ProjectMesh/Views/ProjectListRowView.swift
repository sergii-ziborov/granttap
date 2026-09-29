import SwiftUI

struct ProjectListRowView: View {
    let row: ProjectListRow
    var repositorySummary: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.hidden ? "eye.slash" : "point.3.connected.trianglepath.dotted")
                .frame(width: 24)
                .foregroundColor(row.hidden ? Theme.muted : row.working > 0 ? Theme.ok : Theme.codex)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name).foregroundColor(Theme.ink).lineLimit(1)
                    if row.working > 0 {
                        Text(L("ACTIVE"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.ok)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.ok.opacity(0.14), in: Capsule())
                            .accessibilityLabel(L("Active Mesh"))
                    }
                    if !row.holdsKey {
                        Image(systemName: "key.slash").font(.caption2).foregroundColor(Theme.muted)
                            .accessibilityLabel(L("Has not received this Mesh key"))
                    }
                }
                if let repositorySummary {
                    Label(repositorySummary, systemImage: "folder")
                        .font(.caption).foregroundStyle(Theme.codex).lineLimit(2)
                        .accessibilityIdentifier("project.repositories.\(row.projectId)")
                }
                Text(row.detail).font(.caption).foregroundColor(Theme.muted).lineLimit(2)
                if let sharedBy = row.sharedBy {
                    Label(String(format: L("Shared by %@"), sharedBy), systemImage: "person.crop.circle")
                        .font(.caption).foregroundColor(Theme.codex).lineLimit(1)
                        .accessibilityIdentifier("project.shared-by.\(row.projectId)")
                }
                HStack(spacing: 8) {
                    if row.working > 0 {
                        Text(LPlural(row.working, one: "%d working", many: "%d working")).foregroundColor(Theme.ok)
                    }
                    if row.needsYou > 0 {
                        Text(LPlural(row.needsYou, one: "%d needs you", many: "%d need you")).foregroundColor(Theme.riskMed)
                    }
                    if row.lastActiveAt > 0 {
                        let seconds = Int(max(0, Date().timeIntervalSince1970 - row.lastActiveAt / 1_000))
                        Text("\(L("Last active")) \(ConnectionLoadFormat.age(seconds: seconds))").foregroundColor(Theme.muted)
                    }
                }
                .font(.caption2.weight(.semibold))
            }
        }
        .padding(.vertical, 3)
    }
}
