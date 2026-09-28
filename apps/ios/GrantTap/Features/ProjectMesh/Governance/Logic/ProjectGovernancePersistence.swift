import Foundation

enum ProjectGovernancePersistence {
    private static let maxProjects = 64
    private static let maxBytes = 1_024 * 1_024

    static func load(from url: URL? = nil) -> [String: ProjectGovernanceProjection] {
        let target = url ?? defaultURL
        guard let data = try? Data(contentsOf: target), data.count <= maxBytes,
              let decoded = try? JSONDecoder().decode(
                [String: ProjectGovernanceProjection].self, from: data
              ) else { return [:] }
        let valid = decoded.values.filter(validProjection).sorted {
            $0.updatedAt == $1.updatedAt ? $0.projectId < $1.projectId : $0.updatedAt > $1.updatedAt
        }.prefix(maxProjects)
        return Dictionary(uniqueKeysWithValues: valid.map { ($0.projectId, $0) })
    }

    static func save(
        _ values: [String: ProjectGovernanceProjection], to url: URL? = nil
    ) {
        let target = url ?? defaultURL
        let bounded = values.values.filter(validProjection).sorted {
            $0.updatedAt == $1.updatedAt ? $0.projectId < $1.projectId : $0.updatedAt > $1.updatedAt
        }.prefix(maxProjects)
        var selected = Array(bounded)
        var data: Data? = selected.isEmpty ? try? JSONEncoder().encode(
            [String: ProjectGovernanceProjection]()
        ) : nil
        while !selected.isEmpty {
            let dictionary = Dictionary(uniqueKeysWithValues: selected.map { ($0.projectId, $0) })
            if let encoded = try? JSONEncoder().encode(dictionary), encoded.count <= maxBytes {
                data = encoded
                break
            }
            selected.removeLast()
        }
        guard let data else { return }
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: target, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = target
            try mutable.setResourceValues(values)
        } catch {}
    }

    static func clear(at url: URL? = nil) {
        try? FileManager.default.removeItem(at: url ?? defaultURL)
    }

    private static func validProjection(_ value: ProjectGovernanceProjection) -> Bool {
        guard value.id == value.projectId,
              !value.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.projectId.count <= 128,
              value.rules.count <= 256, value.coverage.count <= 256 else { return false }
        guard let policy = value.policy else { return true }
        let emptyCoverage = ProjectPolicyCoverage(
            projectId: policy.projectId, policyRevision: policy.revision,
            enforcement: policy.enforcement,
            requiredCapabilities: value.requiredCapabilities ?? [], endpoints: [],
            strictReady: value.strictReady ?? true
        )
        return ProjectGovernanceWireValidator.validStatus(ProjectPolicyStatus(
            type: "project.policy.status", sessionId: value.projectId,
            projectId: value.projectId, policy: policy, coverage: emptyCoverage,
            generatedAt: value.updatedAt
        ))
    }

    private static var defaultURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("GrantTap", isDirectory: true)
            .appendingPathComponent("project-governance-cache.json")
    }
}
