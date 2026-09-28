import Foundation

extension AppModel {
    /// Usage attribution is separate from relay routing: the Mac's own feed has no paired room.
    var projectUsageRooms: [String: String] {
        var rooms = meshComputerRoomByEndpointId
        #if targetEnvironment(macCatalyst)
        if let reader = localMCPReader, reader.isReady, let endpoint = reader.status?.endpointId {
            rooms[endpoint] = "local-mac"
        }
        #endif
        return rooms
    }
}
