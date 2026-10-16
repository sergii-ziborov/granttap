import SwiftUI

struct ProductHelpIllustration: View {
    let illustration: ProductDocument.Illustration

    var body: some View {
        NavigationLink {
            ScrollView {
                Image(illustration.name).resizable().scaledToFit()
                    .accessibilityLabel(illustration.caption)
                    .padding()
            }
            .pageNavigationTitle(L("Connection guide"))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(illustration.name).resizable().scaledToFit()
                    .frame(maxWidth: 300)
                    .accessibilityLabel(illustration.caption)
                Text(illustration.caption).font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 8)
        }
    }
}
