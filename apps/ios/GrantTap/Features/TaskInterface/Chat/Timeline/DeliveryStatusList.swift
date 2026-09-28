import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - delivery history

struct DeliveryStatusList: View {
    @EnvironmentObject private var model: AppModel
    let deliveries: [OutgoingDelivery]

    /// Every outbound row that is still in flight (or just delivered) — never
    /// only `.first`, or a second send visually overwrites the previous bubble.
    private var visible: [OutgoingDelivery] {
        let now = Date().timeIntervalSince1970 * 1000
        return deliveries
            .filter { d in
                // Delivered rows are removed on receipt — never flash ghosts.
                if d.state == .delivered { return false }
                if let deadline = DeliveryOutboxPolicy.terminalDeadline(for: d) {
                    return now <= deadline
                }
                let ageAnchor = d.state == .failed ? d.updatedAt : d.createdAt
                return now - ageAnchor < DeliveryOutboxPolicy.failedVisibilityMs
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ForEach(visible) { delivery in
            VStack(alignment: .trailing, spacing: 5) {
                Text(delivery.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 5) {
                    Image(systemName: icon(delivery.state))
                    Text(TaskRoutePresentation.deliveryStatus(
                        delivery,
                        route: model.chatComputerRoute(forRoomId: delivery.roomId),
                        chatIsBusy: delivery.sessionId.map { id in
                            model.sessions.first { $0.sessionId == id }?.state == "working"
                        } ?? false
                    )).lineLimit(2)
                    if delivery.state == .failed, delivery.admissionRejected != true {
                        Button(L("Retry")) { model.retryDelivery(delivery.id) }
                            .font(.body.weight(.bold))
                    }
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint(delivery.state))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .id(delivery.id)
        }
    }

    private func icon(_ state: DeliveryState) -> String {
        switch state {
        case .queued: return "clock"
        case .sending: return "arrow.up.circle"
        case .delivered: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private func tint(_ state: DeliveryState) -> Color {
        switch state {
        case .delivered: return Theme.ok
        case .failed: return Theme.riskHigh
        default: return Theme.muted
        }
    }

}
