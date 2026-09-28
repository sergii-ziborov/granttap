import SwiftUI

/// A page keeps its native navigation on iPhone/iPad. Mac uses the chat's
/// compact chrome inside the main window, without an iPad navigation bar.
extension View {
    func pageNavigationTitle(_ title: String, showsBack: Bool = true,
                             onBack: (() -> Void)? = nil) -> some View {
        modifier(PageNavigation(title: title, showsBack: showsBack, onBack: onBack, actions: EmptyView()))
    }

    func pageNavigationTitle<Actions: View>(
        _ title: String, showsBack: Bool = true, onBack: (() -> Void)? = nil,
        actionPlacement: ToolbarItemPlacement = .primaryAction,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(PageNavigation(title: title, showsBack: showsBack, onBack: onBack, actions: actions()))
        #else
        navigationTitle(title)
            .toolbar { ToolbarItemGroup(placement: actionPlacement) { actions() } }
        #endif
    }
}

private struct PageNavigation<Actions: View>: ViewModifier {
    let title: String
    let showsBack: Bool
    let onBack: (() -> Void)?
    let actions: Actions
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                MacPageHeader(title: title, onBack: showsBack ? (onBack ?? { dismiss() }) : nil) { actions }
            }
            .navigationBarHidden(true)
        #else
        content.navigationTitle(title)
        #endif
    }
}

#if targetEnvironment(macCatalyst)
struct MacPageHeader<Actions: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 28)
                }
                .accessibilityLabel(L("Back"))
                .accessibilityIdentifier("page.back")
            }
            Spacer(minLength: 0)
            actions()
        }
        .overlay {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 104)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page.header")
    }
}
#endif
