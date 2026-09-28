import Foundation
import SwiftUI

struct DesktopLicenseView: View {
    private var license: AttributedString {
        guard let url = Bundle.main.url(forResource: "License", withExtension: "txt"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return AttributedString("The bundled Desktop license could not be loaded.")
        }
        return (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }

    var body: some View {
        ScrollView {
            Text(license)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(24)
        }
    }
}
