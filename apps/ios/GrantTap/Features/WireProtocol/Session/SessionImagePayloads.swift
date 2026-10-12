import Foundation

struct SessionImageRequest: Codable {
    var type = "session.image.query"
    let sessionId: String
    let requestId: String
    let imageId: String
    let offset: Int
    let historyCursor: String?
    let createdAt: Double
}

struct SessionImageChunk: Codable {
    let type: String
    let sessionId: String
    let requestId: String
    let imageId: String
    let offset: Int
    let mimeType: String?
    let totalBytes: Int?
    let dataBase64: String?
    let unavailable: Bool?

    var isWellFormed: Bool {
        guard type == "session.image.chunk", !sessionId.isEmpty, sessionId.count <= 512,
              !requestId.isEmpty, requestId.count <= 128, !imageId.isEmpty, imageId.count <= 512,
              offset >= 0, offset <= 8 * 1_024 * 1_024 else { return false }
        if unavailable == true { return dataBase64 == nil }
        guard let totalBytes, totalBytes > 0, totalBytes <= 8 * 1_024 * 1_024,
              offset < totalBytes, let mimeType,
              ["image/png", "image/jpeg", "image/webp"].contains(mimeType),
              let dataBase64, dataBase64.utf8.count <= 90_000,
              let data = Data(base64Encoded: dataBase64), !data.isEmpty,
              data.count <= 64 * 1_024, offset + data.count <= totalBytes else { return false }
        return true
    }
}
