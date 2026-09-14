import SwiftUI

/// NavigationStack-compatible container for iOS 15. Stack style is explicit:
/// the default NavigationView split presentation otherwise opens an empty
/// detail column on iPad and in Stage Manager.
struct CompatNavigationStack<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationView { content }
            .navigationViewStyle(StackNavigationViewStyle())
    }
}

/// Lightweight iOS 15 replacement for ContentUnavailableView (iOS 17+).
struct CompatEmptyState: View {
    let title: String
    let systemImage: String
    var description: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(Theme.muted)
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.ink)
                .multilineTextAlignment(.center)
            if let description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// iOS 15-compatible equivalent of LabeledContent (iOS 16+).
struct CompatLabeledContent<Content: View>: View {
    let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundColor(Theme.ink)
            Spacer(minLength: 12)
            content
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.trailing)
        }
    }
}

extension CompatLabeledContent where Content == Text {
    init(_ label: String, value: String) {
        self.label = label
        self.content = Text(value)
    }
}
