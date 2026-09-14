import UIKit
import SwiftUI
import XCTest
@testable import GrantTap

@MainActor
final class MCPServerIconCoverageTests: XCTestCase {
    func testDataUriLoaderAcceptsBoundedImagesCachesAndRejectsInvalidInputs() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let png = try XCTUnwrap(image.pngData())
        let source = "data:image/png;base64,\(png.base64EncodedString())"
        XCTAssertNotNil(MCPServerIconLoader.decodeDataURI(source))
        XCTAssertNil(MCPServerIconLoader.decodeDataURI("data:text/plain;base64,SGVsbG8="))
        XCTAssertNil(MCPServerIconLoader.decodeDataURI("data:image/png;base64,not-image"))
        XCTAssertNil(MCPServerIconLoader.decodeDataURI(String(
            repeating: "x", count: SafeMCPImageDownload.maximumEncodedBytes + 1
        )))

        let icon = McpIconInfo(
            src: source, mimeType: "image/png", sizes: ["8x8"],
            theme: "light", sourceOrigin: nil
        )
        let loader = MCPServerIconLoader(icon: icon)
        loader.load()
        await waitUntil { loader.image != nil }
        XCTAssertGreaterThan(loader.image?.size.width ?? 0, 0)
        loader.load()

        let cached = MCPServerIconLoader(icon: icon)
        cached.load()
        XCTAssertNotNil(cached.image)
        let remote = MCPServerIconLoader(icon: McpIconInfo(
            src: "https://example.com/icon.png", mimeType: "image/png",
            sizes: nil, theme: nil, sourceOrigin: nil
        ))
        remote.load()
        await Task.yield()
        XCTAssertNil(remote.image)
    }

    func testSafeImageValidationAndOriginRules() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 6, height: 6)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 6, height: 6))
        }
        let png = try XCTUnwrap(image.pngData())
        XCTAssertNotNil(SafeMCPImageDownload.validatedImage(png))
        XCTAssertNil(SafeMCPImageDownload.validatedImage(Data("plain".utf8)))
        XCTAssertNil(SafeMCPImageDownload.validatedImage(Data(
            repeating: 0, count: SafeMCPImageDownload.maximumBytes + 1
        )))
        XCTAssertEqual(
            SafeMCPImageDownload.origin(of: URL(string: "https://EXAMPLE.com/path")!),
            "https://example.com"
        )
        XCTAssertEqual(
            SafeMCPImageDownload.origin(of: URL(string: "https://example.com:8443/path")!),
            "https://example.com:8443"
        )
        XCTAssertNil(SafeMCPImageDownload.origin(of: URL(string: "http://example.com")!))
        XCTAssertNil(SafeMCPImageDownload.origin(of: URL(string: "https://u:p@example.com")!))
    }

    func testSafeDownloadRejectsWrongOriginAndExercisesDelegateGuards() async throws {
        let url = URL(string: "https://example.com/icon.png")!
        let rejected = SafeMCPImageDownload(url: url, allowedOrigin: "https://other.test")
        let rejectedImage = await rejected.run()
        XCTAssertNil(rejectedImage)

        let download = SafeMCPImageDownload(url: url, allowedOrigin: "https://example.com")
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: url)
        var disposition: URLSession.ResponseDisposition?
        let valid = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Length": "20"]
        ))
        download.urlSession(session, dataTask: task, didReceive: valid) {
            disposition = $0
        }
        XCTAssertEqual(disposition, .allow)

        let redirect = URLRequest(url: URL(string: "https://other.test/icon.png")!)
        var redirected: URLRequest?
        download.urlSession(
            session, task: task, willPerformHTTPRedirection: valid,
            newRequest: redirect
        ) { redirected = $0 }
        XCTAssertNil(redirected)

        let oversized = Data(
            repeating: 1, count: SafeMCPImageDownload.maximumBytes + 1
        )
        download.urlSession(session, dataTask: task, didReceive: oversized)
        download.urlSession(session, task: task, didCompleteWithError: URLError(.cancelled))
        download.urlSession(session, task: task, didCompleteWithError: nil)
        session.invalidateAndCancel()
    }

    func testSafeDownloadAcceptsSameOriginRedirectAndBoundedData() throws {
        let url = URL(string: "https://example.com/icon.png")!
        let download = SafeMCPImageDownload(url: url, allowedOrigin: "https://example.com")
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Length": "20"]
        ))
        var redirect: URLRequest?
        let sameOrigin = URLRequest(url: URL(string: "https://example.com/next.png")!)
        download.urlSession(
            session, task: task, willPerformHTTPRedirection: response,
            newRequest: sameOrigin
        ) { redirect = $0 }
        XCTAssertEqual(redirect?.url, sameOrigin.url)
        download.urlSession(session, dataTask: task, didReceive: Data([0x89, 0x50]))

        var disposition: URLSession.ResponseDisposition?
        let rejected = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: 500, httpVersion: nil, headerFields: nil
        ))
        download.urlSession(session, dataTask: task, didReceive: rejected) {
            disposition = $0
        }
        XCTAssertEqual(disposition, .cancel)
        session.invalidateAndCancel()
    }

    func testLoaderTakesBoundedRemoteBranchAndIconRendersCachedImage() async throws {
        let remote = MCPServerIconLoader(icon: McpIconInfo(
            src: "http://example.com/icon.png", mimeType: "image/png",
            sizes: nil, theme: nil, sourceOrigin: "https://example.com"
        ))
        remote.load()
        await Task.yield()
        XCTAssertNil(remote.image)

        let image = UIGraphicsImageRenderer(size: CGSize(width: 5, height: 5)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 5, height: 5))
        }
        let source = "data:image/png;base64,\(try XCTUnwrap(image.pngData()).base64EncodedString())"
        let icon = McpIconInfo(
            src: source, mimeType: "image/png", sizes: nil,
            theme: nil, sourceOrigin: nil
        )
        let loader = MCPServerIconLoader(icon: icon)
        loader.load()
        await waitUntil { loader.image != nil }
        let controller = UIHostingController(rootView: MCPServerIcon(icon: icon, size: 40))
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        await Task.yield()
        XCTAssertNotNil(loader.image)
    }

    func testSafeDownloadRunsToAValidatedImageThroughInjectedEphemeralTransport() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedImageURLProtocol.self]
        let download = SafeMCPImageDownload(
            url: URL(string: "https://example.com/icon.png")!,
            allowedOrigin: "https://example.com",
            configuration: configuration
        )
        let image = await download.run()
        XCTAssertEqual(image?.size, CGSize(width: 1, height: 1))
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class BoundedImageURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let encoded = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        let data = Data(base64Encoded: encoded)!
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png", "Content-Length": "\(data.count)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
