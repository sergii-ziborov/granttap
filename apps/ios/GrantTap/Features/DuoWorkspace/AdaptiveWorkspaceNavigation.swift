import SwiftUI

/// The compact phone keeps its tab bar; an expanded workspace gains a sidebar.
struct AdaptiveWorkspaceNavigation: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}
