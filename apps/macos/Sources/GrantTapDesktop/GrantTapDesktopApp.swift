import AppKit
import SwiftUI

@main
struct GrantTapDesktopApp: App {
    @StateObject private var model = DesktopModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            DesktopView(model: model)
                .onAppear {
                    guard let icon = Bundle.main.url(forResource: "GrantTap", withExtension: "icns"),
                          let image = NSImage(contentsOf: icon) else { return }
                    NSApplication.shared.applicationIconImage = image
                }
        }
            .defaultSize(width: 1000, height: 650)
            .commands {
                CommandGroup(after: .help) {
                    Button("License and Terms") { openWindow(id: "license") }
                }
            }
        Window("License and Terms", id: "license") { DesktopLicenseView() }
            .defaultSize(width: 680, height: 600)
    }
}
