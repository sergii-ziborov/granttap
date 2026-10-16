import UIKit

@MainActor
enum TaskFileEditClose {
    /// Present from the visible file controller; nested SwiftUI navigation can replace its alert host.
    static func confirmDiscard(_ onDiscard: @escaping () -> Void) -> Bool {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        guard var presenter = window?.rootViewController else { return false }
        while let next = presenter.presentedViewController { presenter = next }
        if presenter is UIAlertController { return true }
        guard !presenter.isBeingDismissed else { return false }
        let alert = UIAlertController(title: L("Discard unsent edits?"),
            message: L("These edits have not been sent to the agent."), preferredStyle: .alert)
        let keep = UIAlertAction(title: L("Keep editing"), style: .cancel)
        alert.addAction(keep)
        alert.addAction(UIAlertAction(title: L("Discard draft"), style: .destructive) { _ in
            onDiscard()
        })
        alert.preferredAction = keep
        presenter.present(alert, animated: true)
        return true
    }

}
