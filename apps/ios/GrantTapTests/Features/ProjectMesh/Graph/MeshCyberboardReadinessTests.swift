import XCTest
import SwiftUI
import WebKit
@testable import GrantTap

@MainActor
final class MeshCyberboardReadinessTests: XCTestCase {
    func testAReportWaitsForTheBundledDocumentBeforeDelivery() async throws {
        var failed = false
        var report = ProjectTowerViewFixtures.report()
        report.codeMap = ProjectTowerViewFixtures.map()
        let bridge = MeshCyberboardView(reports: [report], failed: Binding(
            get: { failed }, set: { failed = $0 })).makeCoordinator()
        let web = WKWebView()
        // SwiftUI can update while a newly created WebView still has no document.
        bridge.deliver(to: web)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(failed, "A not-yet-loaded document must not select the old native renderer")
        let directory = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("RepoLensGraph"))
        web.navigationDelegate = bridge
        web.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("typeof window.graphViewSnapshot === 'function'")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(failed)
        let path = try await web.evaluateJavaScript("window.meshReports[0].codeMap.files[0].path") as? String
        XCTAssertEqual(path, ProjectTowerViewFixtures.path)
        web.reload()
        for _ in 0..<100 {
            if !web.isLoading,
               (try? await web.evaluateJavaScript("typeof window.graphViewSnapshot === 'function'")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let count = try await web.evaluateJavaScript("window.meshReports[0].codeMap.files.length") as? Int
        XCTAssertEqual(count, 2, "A reloaded document must receive the same report again")
        XCTAssertFalse(failed)
        web.navigationDelegate = nil
    }
}
