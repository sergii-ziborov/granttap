import SwiftUI
import UIKit

/// Downloads only the image formats MCP clients are required to support.
/// Requests are anonymous, bounded, and may not redirect off the origin the
/// MCP bridge validated. Server-provided icon bytes are always untrusted.
@MainActor
final class MCPServerIconLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()
    private let icon: McpIconInfo

    init(icon: McpIconInfo) {
        self.icon = icon
    }

    func load() {
        guard image == nil else { return }
        let key = icon.src as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }
        Task {
            let loaded: UIImage?
            if icon.src.lowercased().hasPrefix("data:") {
                loaded = Self.decodeDataURI(icon.src)
            } else if let url = URL(string: icon.src),
                      let origin = icon.sourceOrigin {
                loaded = await SafeMCPImageDownload(url: url, allowedOrigin: origin).run()
            } else {
                loaded = nil
            }
            guard let loaded else { return }
            Self.cache.setObject(loaded, forKey: key, cost: loaded.pngData()?.count ?? 0)
            image = loaded
        }
    }

    static func decodeDataURI(_ value: String) -> UIImage? {
        guard value.count <= SafeMCPImageDownload.maximumEncodedBytes,
              let comma = value.firstIndex(of: ",") else { return nil }
        let header = String(value[..<comma]).lowercased()
        guard header == "data:image/png;base64" ||
                header == "data:image/jpeg;base64" ||
                header == "data:image/jpg;base64",
              let data = Data(base64Encoded: String(value[value.index(after: comma)...]),
                              options: [.ignoreUnknownCharacters]) else { return nil }
        return SafeMCPImageDownload.validatedImage(data)
    }
}

final class SafeMCPImageDownload: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    static let maximumBytes = 128 * 1024
    static let maximumEncodedBytes = 180_000

    private let url: URL
    private let allowedOrigin: String
    private let configuration: URLSessionConfiguration
    private var bytes = Data()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var session: URLSession?
    private var finished = false

    init(
        url: URL, allowedOrigin: String,
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        self.url = url
        self.allowedOrigin = allowedOrigin
        self.configuration = configuration
    }

    func run() async -> UIImage? {
        guard Self.origin(of: url) == allowedOrigin else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 10
            let session = URLSession(configuration: configuration, delegate: self,
                                     delegateQueue: nil)
            self.session = session
            var request = URLRequest(url: url)
            request.setValue("image/png, image/jpeg", forHTTPHeaderField: "Accept")
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              response.expectedContentLength <= Int64(Self.maximumBytes),
              response.url.map({ Self.origin(of: $0) == allowedOrigin }) == true else {
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard bytes.count + data.count <= Self.maximumBytes else {
            dataTask.cancel()
            return
        }
        bytes.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let target = request.url, Self.origin(of: target) == allowedOrigin else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        let result = error == nil ? Self.validatedImage(bytes) : nil
        complete(result)
    }

    private func complete(_ image: UIImage?) {
        guard !finished else { return }
        finished = true
        continuation?.resume(returning: image)
        continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
    }

    static func validatedImage(_ data: Data) -> UIImage? {
        guard data.count <= maximumBytes else { return nil }
        let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let jpeg = data.starts(with: [0xFF, 0xD8, 0xFF])
        guard png || jpeg, let image = UIImage(data: data),
              image.size.width > 0, image.size.height > 0,
              image.size.width <= 1_024, image.size.height <= 1_024 else { return nil }
        return image
    }

    static func origin(of url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.user == nil,
              url.password == nil, let host = url.host?.lowercased() else { return nil }
        if let port = url.port { return "https://\(host):\(port)" }
        return "https://\(host)"
    }
}

struct MCPServerIcon: View {
    let icon: McpIconInfo
    let size: CGFloat
    @StateObject private var loader: MCPServerIconLoader

    init(icon: McpIconInfo, size: CGFloat) {
        self.icon = icon
        self.size = size
        _loader = StateObject(wrappedValue: MCPServerIconLoader(icon: icon))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .stroke(Theme.line, lineWidth: 1))
        .task(id: icon.src) { loader.load() }
    }
}
