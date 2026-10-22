import SwiftUI

struct MessageImageContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.messageImageSessionId) private var imageSessionId
    let entry: ActivityEntry
    let compact: Bool

    var body: some View {
        if compact || (entry.images ?? []).isEmpty {
            RichMessageText(text: entry.text, compact: compact)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(MessageImageContent.parts(entry.text, images: entry.images ?? [])
                    .enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let text): RichMessageText(text: text, compact: false)
                    case .images(let images): MessageImageGallery(images: images,
                        cacheRevision: model.replicaImagesRevision, connected: model.connected, load: imageData)
                    }
                }
            }
        }
    }

    private func imageData(_ attachment: MessageImageAttachment) async throws -> Data {
        #if DEBUG
        if let data = DemoMessageImages.data(for: attachment.id) { return data }
        #endif
        guard let sessionId = model.imageConversation(forEntryId: attachment.id,
                                                      preferredSessionId: imageSessionId) else {
            throw MessageImageLoader.ImageError.unavailable
        }
        return try await model.messageImageData(sessionId: sessionId, imageId: attachment.id)
    }
}

struct MessageImageGallery: View {
    let images: [MessageImageAttachment]
    var cacheRevision = 0
    var connected = false
    let load: (MessageImageAttachment) async throws -> Data
    @StateObject private var loader = MessageImageLoader()
    @State private var preview: ImagePreview?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 12)],
                  alignment: .leading, spacing: 12) {
            ForEach(images) { attachment in
                Button {
                    if let image = loader.images[attachment.id] {
                        preview = ImagePreview(image: image)
                    } else {
                        Task { await loader.load([attachment], data: load) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let image = loader.images[attachment.id] {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 240)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12).fill(Theme.raised)
                                if loader.failed.contains(attachment.id) {
                                    Label(L("Retry"), systemImage: "arrow.clockwise")
                                        .font(.system(size: 13))
                                } else { ProgressView() }
                            }.frame(height: 160)
                        }
                        Text(attachment.name).font(.system(size: 11)).foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    .padding(8)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                }
                .pointerButtonStyle()
                .accessibilityLabel(attachment.name)
                .accessibilityIdentifier("chat.image.\(attachment.id)")
                .disabled(loader.images[attachment.id] == nil && !loader.failed.contains(attachment.id))
            }
        }
        .frame(maxWidth: 1_200, alignment: .leading)
        .task(id: "\(images.map(\.id)):\(cacheRevision):\(connected):\(scenePhase)") {
            for attempt in 0..<3 {
                await loader.load(images, data: load)
                guard !loader.failed.isEmpty, connected, scenePhase == .active, attempt < 2 else { return }
                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                catch { return }
            }
        }
        .fullScreenCover(item: $preview) { item in
            ImagePreviewScreen(image: item.image) { preview = nil }
        }
    }
}
