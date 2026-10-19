import SwiftUI

struct ChatAgentGlyph: View {
    var body: some View {
        VStack(spacing: 0) {
            Circle().frame(width: 3, height: 3)
            Rectangle().frame(width: 1, height: 3)
            RoundedRectangle(cornerRadius: 3)
                .stroke(lineWidth: 1.4)
                .frame(width: 14, height: 10)
                .overlay {
                    HStack(spacing: 4) {
                        Circle().frame(width: 2, height: 2)
                        Circle().frame(width: 2, height: 2)
                    }
                }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
