import Foundation

extension ProjectMeshLogic {
    /// An unavailable old computer name is hidden when an available binding
    /// offers the same repository under the computer's current identity.
    static func visibleBindings(_ bindings: [ProjectBindingSummary]) -> [ProjectBindingSummary] {
        let offered = Set(bindings.filter(\.available).map(\.repositoryId))
        return bindings.filter { $0.available || !offered.contains($0.repositoryId) }
    }
}
