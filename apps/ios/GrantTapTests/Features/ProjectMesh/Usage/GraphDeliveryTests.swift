import XCTest
@testable import GrantTap

@MainActor
final class GraphDeliveryTests: XCTestCase {
    func testMissingTransportCallbackTimesOutAndLateCallbackCannotResumeAgain() async throws {
        let delivery = ProjectGraphDelivery()
        var callback: ((Error?) -> Void)?
        do {
            try await delivery.send(timeoutNanoseconds: 1_000_000) { callback = $0 }
            XCTFail("Missing transport receipt must not leave a graph request pending")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        callback?(nil)
        await Task.yield()
        try await delivery.send { $0(nil) }
    }

    func testFailedAndCancelledSendsFinishWithoutAReport() async {
        let delivery = ProjectGraphDelivery()
        do {
            try await delivery.send { $0(URLError(.notConnectedToInternet)) }
            XCTFail("Transport failure must remain a failure")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        let job = Task { try await ProjectGraphDelivery().send { _ in } }
        await Task.yield()
        job.cancel()
        do { try await job.value; XCTFail("Cancelled graph send succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
