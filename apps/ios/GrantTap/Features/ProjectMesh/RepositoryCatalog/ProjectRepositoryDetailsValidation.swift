import Foundation

/// The same bounded Git observation contract as the computer publisher.
enum ProjectRepositoryDetailsValidation {
    static func valid(_ reports: [ProjectRepositoryDetails]?, projectId: String, publisher: String?) -> Bool {
        guard let reports else { return true }
        guard reports.count <= 64, Set(reports.map(\.id)).count == reports.count else { return false }
        return reports.allSatisfy { report in
            report.projectId == projectId && bounded(report.repositoryId, 512)
                && bounded(report.endpointId, 128)
                && (publisher == nil || publisher == report.endpointId)
                && ["ready", "not_git", "unavailable"].contains(report.status)
                && (report.canonicalRepositoryId.map { bounded($0, 512) } ?? true)
                && (report.branch?.utf16.count ?? 0) <= 512
                && (report.revision?.utf16.count ?? 0) <= 64
                && (report.commitCount ?? 0) >= 0 && (report.contributorCount ?? 0) >= 0
                && report.observedAt.isFinite && report.observedAt >= 0
                && report.commits.count <= 8 && report.commits.allSatisfy(validCommit)
                && report.contributors.count <= 12 && report.contributors.allSatisfy {
                    $0.name.utf16.count <= 160 && $0.commits >= 0
                }
        }
    }

    private static func bounded(_ value: String, _ limit: Int) -> Bool {
        !value.isEmpty && value.utf16.count <= limit
    }

    private static func validCommit(_ commit: ProjectRepositoryDetails.Commit) -> Bool {
        commit.sha.range(of: "^[a-f0-9]{40,64}$", options: .regularExpression) != nil
            && commit.subject.utf16.count <= 240 && commit.author.utf16.count <= 160
            && commit.committedAt.isFinite && commit.committedAt >= 0
    }
}
