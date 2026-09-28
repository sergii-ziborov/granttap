import SwiftUI

struct MemberInviteLinkSection: View {
    let uri: String
    let expiresAt: Double
    @State private var showShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Pending invite"))
                .font(.subheadline.weight(.semibold))
            HStack {
                Spacer()
                QRCodeImage(text: uri)
                Spacer()
            }
            Text(uri).font(.caption2.monospaced()).lineLimit(2)
                .textSelection(.enabled)
            HStack {
                Button(L("Copy link")) { UIPasteboard.general.string = uri }
                Spacer()
                Button { showShare = true } label: {
                    Label(L("Share link"), systemImage: "square.and.arrow.up")
                }
            }
            Text(String(format: L("Expires %@"),
                        Date(timeIntervalSince1970: expiresAt / 1_000).formatted(date: .abbreviated, time: .shortened)))
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .accessibilityIdentifier("members.pending-invite")
        .sheet(isPresented: $showShare) { MemberInviteShareSheet(uri: uri) }
    }
}
