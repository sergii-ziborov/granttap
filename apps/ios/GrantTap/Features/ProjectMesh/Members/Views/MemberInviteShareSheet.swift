import SwiftUI

struct MemberInviteShareSheet: UIViewControllerRepresentable {
    let uri: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [uri], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
