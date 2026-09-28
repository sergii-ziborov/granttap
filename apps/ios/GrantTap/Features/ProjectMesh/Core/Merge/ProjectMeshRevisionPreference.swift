import Foundation

enum ProjectMeshRevisionPreference {
    static func newest<T>(_ left: T?, _ right: T?, revision: KeyPath<T, Int>) -> T? {
        guard let left else { return right }
        guard let right else { return left }
        return right[keyPath: revision] >= left[keyPath: revision] ? right : left
    }
}
