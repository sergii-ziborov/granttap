import Foundation

/// The phone's durable desired Project level. Endpoint reports remain the
/// source for actual state, so an offline computer is never shown as applied.
enum ProjectAutoAcceptStore {
    private static let key = "granttap.project-auto-accept.v1"
    private static let levels = Set(["ask", "safe", "except_push", "except_destructive", "full"])

    static func load() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return values.filter { project, level in
            !project.isEmpty && project.count <= 128 && levels.contains(level)
        }
    }

    static func save(_ values: [String: String]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
