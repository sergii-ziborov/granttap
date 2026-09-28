import Foundation

enum ProjectCatalogCodec {
    static func matches(_ result: [String: Any], afterProjectId: String?) -> Bool {
        guard let page = result["page"] as? [String: Any],
              let projects = page["projects"] as? [[String: Any]],
              projects.count <= 50 else { return false }
        var prior = afterProjectId ?? ""
        for project in projects {
            guard let id = project["project_id"] as? String,
                  !id.isEmpty, id.utf8.count <= 128,
                  !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  id > prior,
                  let name = project["name"] as? String, !name.isEmpty,
                  project["created_at"] is NSNumber else { return false }
            prior = id
        }
        if let next = page["next_after_project_id"] as? String {
            return projects.count == 50 && next == prior
        }
        return page["next_after_project_id"] is NSNull
    }
}
