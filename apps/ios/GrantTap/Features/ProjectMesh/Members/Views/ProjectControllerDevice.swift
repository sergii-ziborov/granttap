import UIKit

/// Presentation of the device showing Mesh membership, separate from its grants.
struct ProjectControllerDevice {
    let titleKey: String
    let symbol: String

    init(idiom: UIUserInterfaceIdiom) {
        switch idiom {
        case .mac:
            titleKey = "This Mac"
            symbol = "desktopcomputer"
        case .pad:
            titleKey = "This iPad"
            symbol = "ipad"
        case .phone:
            titleKey = "This iPhone"
            symbol = "iphone.gen3"
        default:
            titleKey = "This device"
            symbol = "rectangle"
        }
    }

    @MainActor static var current: Self {
        #if targetEnvironment(macCatalyst)
        return .init(idiom: .mac)
        #else
        return .init(idiom: UIDevice.current.userInterfaceIdiom)
        #endif
    }
}
