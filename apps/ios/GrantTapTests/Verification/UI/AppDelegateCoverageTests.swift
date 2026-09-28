import UIKit
import XCTest
@testable import GrantTap

final class AppDelegateCoverageTests: XCTestCase {
    func testLaunchGuardAndEveryLifecycleCallbackUseInjectedBoundaries() {
        var runningTests = true
        var categories = 0
        var reconciles = 0
        var lifecycleOrder: [String] = []
        var registrations = 0
        var starts = 0
        var token = Data()
        var failed = false
        var wakeCompletions: [(UIBackgroundFetchResult) -> Void] = []
        var expiration: (() -> Void)?
        var ended: [UIBackgroundTaskIdentifier] = []
        let task = UIBackgroundTaskIdentifier(rawValue: 17)
        let dependencies = AppLifecycleDependencies(
            isRunningUnitTests: { runningTests },
            reconcileInstall: { reconciles += 1; lifecycleOrder.append("reconcile") },
            registerCategories: { categories += 1 },
            registerRemoteNotifications: { _ in registrations += 1 },
            startServices: { starts += 1; lifecycleOrder.append("start") },
            didRegister: { token = $0 },
            didFail: { _ in failed = true },
            handleRemoteWake: { wakeCompletions.append($0) },
            beginBackgroundTask: { _, callback in expiration = callback; return task },
            endBackgroundTask: { _, identifier in ended.append(identifier) }
        )
        let delegate = AppDelegate(dependencies: dependencies)
        let application = UIApplication.shared

        XCTAssertTrue(delegate.application(application, didFinishLaunchingWithOptions: nil))
        XCTAssertEqual(categories, 0)
        XCTAssertEqual(reconciles, 0)
        runningTests = false
        XCTAssertTrue(delegate.application(application, didFinishLaunchingWithOptions: nil))
        XCTAssertEqual(categories, 1)
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(reconciles, 1)
        // The purge has to happen before anything reads the registry.
        XCTAssertEqual(lifecycleOrder, ["reconcile", "start"])

        delegate.application(
            application, didRegisterForRemoteNotificationsWithDeviceToken: Data([1, 2, 3])
        )
        delegate.application(
            application,
            didFailToRegisterForRemoteNotificationsWithError: LifecycleFixtureError.failed
        )
        XCTAssertEqual(token, Data([1, 2, 3]))
        XCTAssertTrue(failed)

        var results: [UIBackgroundFetchResult] = []
        delegate.application(application, didReceiveRemoteNotification: [:]) {
            results.append($0)
        }
        XCTAssertEqual(results, [.noData])
        delegate.application(
            application, didReceiveRemoteNotification: ["granttapWake": true]
        ) { results.append($0) }
        XCTAssertEqual(wakeCompletions.count, 1)
        wakeCompletions.removeFirst()(.newData)
        XCTAssertEqual(results.last, .newData)
        XCTAssertEqual(ended, [task])

        delegate.application(
            application,
            didReceiveRemoteNotification: ["aps": ["content-available": 1]]
        ) { results.append($0) }
        expiration?()
        XCTAssertEqual(ended, [task, task])
        wakeCompletions.removeFirst()(.noData)
        XCTAssertEqual(ended, [task, task])
    }

    func testLiveDependencyFactoryAndRuntimeDetectionRemainAvailable() {
        _ = AppLifecycleDependencies.live
        XCTAssertTrue(AppRuntime.isRunningUnitTests)
        _ = AppDelegate()
    }
}

private enum LifecycleFixtureError: Error { case failed }
