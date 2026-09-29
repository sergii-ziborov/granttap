import SwiftUI

struct RepositoryGitSections: View {
    let entry: RepositoryCatalog.Entry
    @ObservedObject var model: AppModel

    private var reports: [ProjectRepositoryDetails] {
        let snapshots = entry.memberships.compactMap { model.meshSnapshots[$0.projectId] }
        let all = snapshots.flatMap { snapshot in
            (snapshot.repositoryDetails ?? []).filter { report in
                report.projectId == snapshot.projectId &&
                    RepositoryIdentityIndex.canonical(report.repositoryId, snapshots: snapshots) == entry.id
            }
        }
        return Dictionary(grouping: all, by: \.endpointId).values.compactMap {
            $0.max { $0.observedAt < $1.observedAt }
        }.sorted { $0.endpointId < $1.endpointId }
    }

    var body: some View {
        if reports.isEmpty {
            Section(L("Git history")) {
                Text(L("Waiting for repository details from the computer."))
                    .foregroundStyle(Theme.muted)
            }
        }
        ForEach(reports) { report in
            Section {
                if report.status == "ready" {
                    if let branch = report.branch { CompatLabeledContent(L("Branch"), value: branch) }
                    if let sha = report.revision { CompatLabeledContent(L("HEAD"), value: String(sha.prefix(12))) }
                    if let dirty = report.dirty {
                        CompatLabeledContent(L("Working tree"), value: L(dirty ? "Uncommitted changes" : "Clean"))
                    }
                    if let count = report.commitCount { CompatLabeledContent(L("Commits on this branch"), value: "\(count)") }
                } else {
                    Text(L(report.status == "not_git" ? "No Git repository confirmed here." : "The checkout is unavailable on this computer."))
                        .foregroundStyle(Theme.muted)
                }
            } header: {
                Text(L("Git history") + " · " + ProjectHealthDiagnostics.computerName(
                    report.endpointId, connections: model.connectionRegistry.connections))
            } footer: {
                Text(Date(timeIntervalSince1970: report.observedAt / 1_000), style: .relative)
            }
            if report.status == "ready" {
                history(report)
            }
        }
    }

    @ViewBuilder private func history(_ report: ProjectRepositoryDetails) -> some View {
        if !report.commits.isEmpty {
            Section(L("Recent commits")) {
                ForEach(report.commits) { commit in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(commit.subject).foregroundStyle(Theme.ink)
                        HStack {
                            Text(String(commit.sha.prefix(8)) + " · " + commit.author)
                            Text(Date(timeIntervalSince1970: commit.committedAt / 1_000), style: .date)
                        }.font(.caption).foregroundStyle(Theme.muted)
                    }
                    .accessibilityIdentifier("repository.commit.\(commit.sha)")
                }
            }
        }
        if !report.contributors.isEmpty {
            Section {
                ForEach(report.contributors) { contributor in
                    CompatLabeledContent(contributor.name, value: "\(contributor.commits)")
                }
            } header: {
                Text(L("Contributors"))
            } footer: {
                if let count = report.contributorCount {
                    Text(String(format: L("%d contributors on this branch"), count))
                }
            }
        }
    }
}
