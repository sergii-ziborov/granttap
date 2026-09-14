import SwiftUI
import UIKit

/// The delivery state of your own message, shown the way a messenger shows it:
/// a small mark on the bubble itself.
///
/// It used to be a separate card below the chat that repeated the message text,
/// so every message you sent appeared twice while it was in flight.
enum DeliveryTick: Equatable {
    case queued
    case sending
    case delivered
    case failed

    static func forState(_ state: DeliveryState) -> DeliveryTick {
        switch state {
        case .queued: return .queued
        case .sending: return .sending
        case .delivered: return .delivered
        case .failed: return .failed
        }
    }

    var systemImage: String {
        switch self {
        case .queued: return "clock"
        case .sending: return "checkmark"
        // Two marks for "the computer confirmed it", one for "it left the phone".
        case .delivered: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .queued: return L("Queued")
        case .sending: return L("Sent")
        case .delivered: return L("Delivered")
        case .failed: return L("Not delivered")
        }
    }

    /// Only a failure earns colour; the rest must not shout on every message.
    var isAlarming: Bool { self == .failed }
}

struct DeliveryTicksView: View {
    let tick: DeliveryTick
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tick.systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tick.isAlarming ? Theme.riskHigh : Theme.muted)
                .accessibilityLabel(tick.accessibilityLabel)
            if let onRetry {
                Button(L("Retry"), action: onRetry)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.riskHigh)
            }
        }
    }
}

@MainActor
extension AppModel {
    /// The mark for a chat bubble the phone itself created, or nil when the row
    /// came from the provider transcript and is no longer ours to track.
    func deliveryTick(forEntryId entryId: String) -> DeliveryTick? {
        guard entryId.hasPrefix("local-user-") else { return nil }
        let id = String(entryId.dropFirst("local-user-".count))
        guard let delivery = deliveries.first(where: {
            $0.id == id || id.hasPrefix("\($0.id)-")
        }) else { return nil }
        return DeliveryTick.forState(delivery.state)
    }

    /// Sends that have no bubble of their own yet — a brand-new chat whose
    /// transcript has not arrived. Those still need somewhere to be seen; every
    /// other send is already marked on its own message.
    func orphanDeliveries(for sessionId: String) -> [OutgoingDelivery] {
        let entries = activities[sessionId]?.entries ?? []
        let shown = Set(entries.map(\.id))
        return deliveries(for: sessionId).filter { delivery in
            !shown.contains("local-user-\(delivery.id)")
                && !entries.contains { $0.id.hasPrefix("local-user-\(delivery.id)-") }
        }
    }

    /// Only a failed send offers a retry; anything else is still on its way.
    func deliveryRetryId(forEntryId entryId: String) -> String? {
        guard entryId.hasPrefix("local-user-") else { return nil }
        let id = String(entryId.dropFirst("local-user-".count))
        guard let delivery = deliveries.first(where: { $0.id == id }),
              delivery.state == .failed,
              delivery.admissionRejected != true else { return nil }
        return delivery.id
    }
}

@MainActor
extension AppModel {
    /// The image the phone itself just sent, for a tap-to-preview of your own
    /// attachment. The bridge relays only filenames, so a photo from the
    /// transcript has no bytes here — only a message you sent does, and only
    /// until its delivery is pruned.
    func sentAttachmentImage(forEntryId entryId: String, name: String) -> UIImage? {
        guard entryId.hasPrefix("local-user-") else { return nil }
        let id = String(entryId.dropFirst("local-user-".count))
        guard let delivery = deliveries.first(where: {
            $0.id == id || id.hasPrefix("\($0.id)-")
        }) else { return nil }
        guard let attachment = delivery.attachments.first(where: { $0.name == name }),
              attachment.mimeType.hasPrefix("image/"),
              let data = Data(base64Encoded: attachment.data),
              let image = UIImage(data: data) else { return nil }
        return image
    }
}
