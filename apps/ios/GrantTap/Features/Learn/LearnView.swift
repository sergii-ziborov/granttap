import SwiftUI

/// The app explaining itself, in the app.
///
/// Everything here is also true of the product; nothing on this screen is a
/// promise about a version that does not exist yet. It is grouped the way a
/// person meets GrantTap: connect a computer, work with an agent, share a
/// Project, understand the numbers, and know what leaves the device.
struct LearnView: View {
    @State private var search = ""

    private var chapters: [(chapter: LearnChapter, topics: [LearnTopic])] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return LearnChapter.all.compactMap { chapter in
            let topics = query.isEmpty ? chapter.topics : chapter.topics.filter { matches($0, query) }
            return topics.isEmpty ? nil : (chapter, topics)
        }
    }

    private func matches(_ topic: LearnTopic, _ query: String) -> Bool {
        [L(topic.title), L(topic.summary)].contains { $0.lowercased().contains(query) }
    }

    var body: some View {
        List {
            Section {
                Text(L("GrantTap is the yes, the no, the answer, and the next message — for coding agents that run on your own computers. These pages say how each part of that works, and what it deliberately does not do."))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(chapters, id: \.chapter.id) { entry in
                Section(L(entry.chapter.title)) {
                    ForEach(entry.topics) { topic in
                        NavigationLink {
                            LearnTopicView(topic: topic)
                        } label: {
                            row(topic)
                        }
                        .accessibilityIdentifier("learn.topic.\(topic.id)")
                    }
                }
            }
            if chapters.isEmpty {
                CompatEmptyState(title: "Nothing here matches that", systemImage: "magnifyingglass")
            }
        }
        .searchable(text: $search, prompt: Text(L("Search")))
        .navigationTitle(L("Learn"))
    }

    private func row(_ topic: LearnTopic) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: topic.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.claude)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(L(topic.title)).font(.system(size: 15, weight: .semibold))
                Text(L(topic.summary))
                    .font(.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One topic, read top to bottom.
struct LearnTopicView: View {
    let topic: LearnTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L(topic.summary))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(topic.body.enumerated()), id: \.offset) { _, piece in
                    view(for: piece)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
        .navigationTitle(L(topic.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func view(for piece: LearnBlock) -> some View {
        switch piece {
        case .heading(let text):
            Text(L(text))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
                .padding(.top, 4)
        case .text(let text):
            Text(L(text))
                .font(.system(size: 16))
                .lineSpacing(3)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .points(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(Theme.claude).frame(width: 5, height: 5).padding(.top, 8)
                        Text(L(item))
                            .font(.system(size: 15))
                            .lineSpacing(2)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .command(let command):
            Text(command)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
        }
    }
}
