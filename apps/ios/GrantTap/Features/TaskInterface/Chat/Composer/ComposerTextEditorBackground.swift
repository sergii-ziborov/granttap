import SwiftUI
import UIKit

/// Keep the composer card's background visible behind its editable text.
struct ClearTextEditorBackground: ViewModifier {
    init() {
        UITextView.appearance().backgroundColor = .clear
    }

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
