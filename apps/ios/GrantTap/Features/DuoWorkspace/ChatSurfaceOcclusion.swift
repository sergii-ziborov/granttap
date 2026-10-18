import Foundation
import CoreGraphics

/// Space hidden by a bottom reply surface when native arrangement overlays it.
/// Separate fold panes never need this inset.
enum ChatSurfaceOcclusion {
    static func bottomInset(conversation: CGRect, reply: CGRect) -> CGFloat {
        guard !conversation.isEmpty, !reply.isEmpty,
              !conversation.isInfinite, !reply.isInfinite,
              conversation.width.isFinite, conversation.height.isFinite,
              reply.width.isFinite, reply.height.isFinite else { return 0 }
        let overlap = conversation.intersection(reply)
        guard !overlap.isNull, !overlap.isEmpty,
              reply.maxY >= conversation.maxY - 1,
              overlap.width >= conversation.width - 1 else { return 0 }
        return min(conversation.height, overlap.height)
    }
}
