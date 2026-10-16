import Foundation
import Combine

@MainActor
final class TaskFileEditDraft: ObservableObject {
    let snapshot: TaskWorkspaceSnapshot
    var original: String { snapshot.text ?? "" }
    @Published var text: String
    @Published var deliveryId: String? = nil
    @Published var failure: String? = nil

    init(snapshot: TaskWorkspaceSnapshot) {
        self.snapshot = snapshot
        text = snapshot.text ?? ""
    }

    func requestClose(_ finish: @escaping () -> Void) {
        if changed && deliveryId == nil {
            if !TaskFileEditClose.confirmDiscard(finish) {
                failure = L("Could not open the confirmation. Your draft has been kept.")
            }
        } else { finish() }
    }

    var changed: Bool { !original.utf8.elementsEqual(text.utf8) }
}

@MainActor
final class TaskFileEditSession: ObservableObject {
    @Published var draft: TaskFileEditDraft? = nil
}
