#if targetEnvironment(macCatalyst)
import Foundation

private struct MacLocalImageChunk: Decodable {
    let operation: String
    let image_id: String
    let mime_type: String
    let total_bytes: Int
    let offset: Int
    let data_base64: String
}

extension MacLocalMCPClient {
    static func image(socketPath: String, projectId: String, taskId: String,
                      imageId: String, historyCursor: String? = nil) async throws -> Data {
        var image = Data()
        var expectedLength: Int?
        repeat {
            var input = ["project_id": projectId, "task_id": taskId,
                         "image_id": imageId, "offset": String(image.count)]
            if let historyCursor { input["history_cursor"] = historyCursor }
            let data = try await read(socketPath: socketPath, operation: "desktop.task_image",
                                      input: input)
            let chunk = try JSONDecoder().decode(MacLocalImageChunk.self, from: data)
            guard chunk.operation == "desktop.task_image", chunk.image_id == imageId,
                  ["image/png", "image/jpeg", "image/webp"].contains(chunk.mime_type),
                  chunk.offset == image.count, chunk.total_bytes > 0,
                  chunk.total_bytes <= 8 * 1_024 * 1_024,
                  expectedLength == nil || expectedLength == chunk.total_bytes,
                  let bytes = Data(base64Encoded: chunk.data_base64),
                  !bytes.isEmpty, bytes.count <= 64 * 1_024,
                  image.count + bytes.count <= chunk.total_bytes else {
                throw MacLocalMCPError.incompatible
            }
            expectedLength = chunk.total_bytes
            image.append(bytes)
        } while image.count < (expectedLength ?? 0)
        return image
    }
}
#endif
