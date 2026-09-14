import SwiftUI
import UserNotifications

enum AppRuntime {
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

@main
struct GrantTapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppLocale.storageKey) private var language = "en"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppModel.shared)
                .environment(\.locale, Locale(identifier: language))
        }
    }
}
struct AppLifecycleDependencies {
    var isRunningUnitTests: () -> Bool
    var reconcileInstall: () -> Void
    var registerCategories: () -> Void
    var registerRemoteNotifications: (UIApplication) -> Void
    var startServices: () -> Void
    var didRegister: (Data) -> Void
    var didFail: (Error) -> Void
    var handleRemoteWake: (@escaping (UIBackgroundFetchResult) -> Void) -> Void
    var beginBackgroundTask: (
        UIApplication, @escaping () -> Void
    ) -> UIBackgroundTaskIdentifier
    var endBackgroundTask: (UIApplication, UIBackgroundTaskIdentifier) -> Void

    static let live = AppLifecycleDependencies(
        isRunningUnitTests: { AppRuntime.isRunningUnitTests },
        reconcileInstall: { _ = InstallIdentity.reconcile() },
        registerCategories: { NotificationManager.shared.registerCategories() },
        registerRemoteNotifications: { $0.registerForRemoteNotifications() },
        startServices: {
            Task { @MainActor in
                async let subscription: Void = SubscriptionStore.shared.start()
                AppModel.shared.start()
                _ = await subscription
            }
        },
        didRegister: { token in
            Task { @MainActor in PushRegistrationManager.shared.didRegister(deviceToken: token) }
        },
        didFail: { error in
            Task { @MainActor in PushRegistrationManager.shared.didFail(error) }
        },
        handleRemoteWake: { completion in
            Task { @MainActor in AppModel.shared.handleRemoteWake(completion: completion) }
        },
        beginBackgroundTask: { application, expiration in
            application.beginBackgroundTask(withName: "granttap.apns-wake", expirationHandler: expiration)
        },
        endBackgroundTask: { $0.endBackgroundTask($1) }
    )
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let dependencies: AppLifecycleDependencies

    override convenience init() { self.init(dependencies: .live) }

    init(dependencies: AppLifecycleDependencies) {
        self.dependencies = dependencies
        super.init()
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        guard !dependencies.isRunningUnitTests() else { return true }
        // Deleting the app wipes its container but leaves its Keychain items,
        // so a reinstall arrives with the previous install's paired computers.
        // Reconcile before startServices reads the connection registry.
        dependencies.reconcileInstall()
        dependencies.registerCategories()
        // Apple requires a fresh APNs registration request on every launch;
        // didRegister returns the current token for this app/device/profile.
        // Alert permission is intentionally requested later, after pairing, so
        // the first-run prompt has context instead of appearing at launch.
        dependencies.registerRemoteNotifications(application)
        dependencies.startServices()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        dependencies.didRegister(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        dependencies.didFail(error)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler:
                     @escaping (UIBackgroundFetchResult) -> Void) {
        // Silent or alert wake — both carry granttapWake and flush the E2EE queue.
        guard userInfo["granttapWake"] != nil
                || (userInfo["aps"] as? [String: Any])?["content-available"] != nil else {
            completionHandler(.noData)
            return
        }
        // Keep the process alive across WS reconnect + decrypt after an APNs wake.
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = dependencies.beginBackgroundTask(application) {
            if bgTask != .invalid {
                self.dependencies.endBackgroundTask(application, bgTask)
                bgTask = .invalid
            }
        }
        dependencies.handleRemoteWake { result in
            completionHandler(result)
            if bgTask != .invalid {
                self.dependencies.endBackgroundTask(application, bgTask)
                bgTask = .invalid
            }
        }
    }
}
