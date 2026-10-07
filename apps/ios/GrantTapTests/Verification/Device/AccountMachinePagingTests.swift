import Foundation
import XCTest
@testable import GrantTap

final class AccountMachinePagingTests: XCTestCase {
    func testAccountLoadsMoreThanOneHundredMachinesWithoutAnUnboundedResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PageURLProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let session = GrantTapAccountSession(accountId: UUID().uuidString,
                                             token: String(repeating: "t", count: 43))
        let computers = try await AccountRecovery.computers(session: session, transport: transport)
        XCTAssertEqual(computers.count, 105)
        XCTAssertEqual(Set(computers.map(\.id)).count, 105)
        XCTAssertEqual(PageURLProtocol.requestedCursors, [nil, "next"])
    }

    private final class PageURLProtocol: URLProtocol {
        static var requestedCursors: [String?] = []
        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == "granttap.com"
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            do {
                let url = try XCTUnwrap(request.url)
                let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
                let query = Dictionary(uniqueKeysWithValues:
                    (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                XCTAssertEqual(query["pageSize"], "100")
                let cursor = query["cursor"]
                if cursor == nil { Self.requestedCursors = [] }
                Self.requestedCursors.append(cursor)
                let range = cursor == nil ? 0..<100 : 100..<105
                let rows = range.map { index -> [String: Any] in
                    ["id": String(format: "%036d", index), "name": "Mac \(index)",
                     "createdAt": 1_000.0, "lastSeenAt": 1_000.0]
                }
                let payload: [String: Any] = ["machines": rows,
                                              "nextCursor": cursor == nil ? "next" : NSNull()]
                let data = try JSONSerialization.data(withJSONObject: payload)
                let response = try XCTUnwrap(HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
        override func stopLoading() { }
    }
}
