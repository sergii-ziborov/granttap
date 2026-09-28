import Foundation

@MainActor
extension AppModel {
    func requestProjectGraphAnalysis(projectId: String) -> Bool {
        guard meshSnapshots[projectId] != nil else { return false }
        let rooms = meshProjectSourceRooms[projectId] ?? []
        var sent = false
        for room in rooms.sorted() {
            guard let relay = relaysByRoom[room] else { continue }
            relay.requestProjectGraphAnalysis(projectId)
            sent = true
        }
        return sent
    }
}
