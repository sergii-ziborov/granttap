import SwiftUI

/// Explicit Task actions shared by Now and Tasks on iPhone, iPad and Mac.
struct TaskSwipeCard<Content: View>: View {
    let id: String
    @Binding var revealed: String?
    let open: () -> Void
    let archive: () -> Void
    let send: () -> Void
    let content: Content

    init(id: String, revealed: Binding<String?>, open: @escaping () -> Void,
         archive: @escaping () -> Void, send: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.id = id
        _revealed = revealed
        self.open = open
        self.archive = archive
        self.send = send
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                action(L("Send"), icon: "arrowshape.turn.up.right", color: Theme.codex) {
                    revealed = nil
                    send()
                }
                action(L("Archive"), icon: "archivebox", color: Theme.muted) {
                    revealed = nil
                    archive()
                }
            }
            .frame(width: 176)
            .accessibilityHidden(revealed != id)
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    if revealed == id { revealed = nil }
                    else { open() }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("task.\(id)")
                .offset(x: revealed == id ? -176 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > 32,
                      abs(horizontal) > abs(value.translation.height) * 1.3 else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    revealed = horizontal < 0 ? id : nil
                }
            }
        )
        .contextMenu {
            Button { send() } label: { Label(L("Send"), systemImage: "arrowshape.turn.up.right") }
            Button { archive() } label: { Label(L("Archive"), systemImage: "archivebox") }
        }
    }

    private func action(_ title: String, icon: String, color: Color,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color)
        }
        .buttonStyle(.plain)
    }
}
