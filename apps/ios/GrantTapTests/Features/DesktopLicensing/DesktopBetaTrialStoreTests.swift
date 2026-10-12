import XCTest
@testable import GrantTap

final class DesktopBetaTrialStoreTests: XCTestCase {
    func testVerifiedTestFlightWeekPersistsForBuildAndRenewsWithNextBuild() {
        let suite = "granttap.beta-trial.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let week = TimeInterval(7 * 24 * 60 * 60)

        func expiry(build: String, now: Date, verified: Bool = true,
                    account: String = "account") -> Date? {
            DesktopBetaTrialStore.expiry(verifiedSandbox: verified,
                bundleID: "com.ziborov.granttap", accountID: account,
                build: build, now: now, defaults: defaults)
        }

        XCTAssertNil(expiry(build: "171", now: start, verified: false))
        XCTAssertEqual(expiry(build: "171", now: start), start.addingTimeInterval(week))
        XCTAssertEqual(expiry(build: "171", now: start.addingTimeInterval(3 * 24 * 60 * 60)),
                       start.addingTimeInterval(week))
        XCTAssertNil(expiry(build: "171", now: start.addingTimeInterval(week)))
        XCTAssertEqual(expiry(build: "172", now: start.addingTimeInterval(week)),
                       start.addingTimeInterval(2 * week))
        XCTAssertEqual(expiry(build: "171", now: start, account: "another"),
                       start.addingTimeInterval(week))
        XCTAssertNil(expiry(build: "173", now: start, verified: false))
    }
}
