import Foundation

/// A bounded projection of one durable Engine memory record, with provenance.
struct ProjectKnowledgeRecord: Codable, Equatable, Identifiable {
    let projectId: String
    let taskId: String
    let recordId: String
    let category: String
    let content: String
    let source: String
    let sourceRef: String
    let visibility: String
    let repositoryId: String?
    let commitSha: String?
    var supersedesRecordId: String? = nil
    let recordedAt: Double
    let streamVersion: Int

    var id: String { "\(projectId)\u{1f}\(recordId)" }
}
