import SwiftUI

/// Project → Auto-accept: the same ladder Claude-style permissions use, scoped
/// to this Project. Governance ASK and DENY still win on the Mac hook.
struct ProjectAutoAcceptView: View {
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel

    private var projectLevel: AutoAcceptLevel? {
        model.autoAcceptByProject[snapshot.projectId].map(AutoAcceptLevel.parse)
    }

    private var effective: AutoAcceptLevel {
        AutoAcceptPresentation.resolved(
            paused: model.autoAcceptPaused,
            session: nil,
            project: model.autoAcceptByProject[snapshot.projectId],
            machine: model.autoAcceptDefault
        )
    }

    private var chats: [SessionInfo] {
        var seen = Set<String>()
        return (model.sessions + model.allSessionHistory)
            .filter { $0.projectId == snapshot.projectId && seen.insert($0.sessionId).inserted }
    }

    var body: some View {
        List {
            Section {
                Toggle(L("Hold auto-accept"), isOn: pauseBinding)
                Toggle(L("GrantTap decides approvals"), isOn: gatingBinding)
            } footer: {
                Text(L("Auto-accept holds routine work on this computer. Governance ASK and DENY still win."))
            }

            Section {
                ForEach(AutoAcceptLevel.allCases) { level in
                    Button {
                        model.setAutoAcceptPaused(false)
                        if !model.gatingEnabled { model.setGating(true) }
                        model.setAutoAcceptDefault(level.rawValue)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(level.title)
                                Spacer()
                                if !model.autoAcceptPaused,
                                   AutoAcceptLevel.parse(model.autoAcceptDefault) == level {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.ok)
                                }
                            }
                            Text(level.blurb).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .foregroundStyle(Theme.ink)
                }
            } header: {
                Text(L("This computer"))
            } footer: {
                Text(L("This is the default when a Project does not set its own level."))
            }

            Section {
                Button {
                    model.setProjectAutoAccept(snapshot.projectId, nil)
                } label: {
                    HStack {
                        Text(L("Use this computer's default"))
                        Spacer()
                        if projectLevel == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.ok)
                        }
                    }
                }
                .foregroundStyle(Theme.ink)
                ForEach(AutoAcceptLevel.allCases) { level in
                    Button {
                        model.setProjectAutoAccept(snapshot.projectId, level.rawValue)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(level.title)
                                if level == .exceptPush {
                                    Text(L("Recommended"))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if projectLevel == level {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.ok)
                                }
                            }
                            Text(level.blurb)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .foregroundStyle(Theme.ink)
                }
            } header: {
                Text(L("This Project"))
            }

            Section(L("What this level allows")) {
                ForEach(AutoAcceptActionClass.allCases) { cls in
                    HStack {
                        Text(cls.title)
                        Spacer()
                        Text(AutoAcceptPresentation.verdict(effective, cls))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                AutoAcceptPresentation.allows(effective, cls) ? Theme.ok : Theme.riskMed
                            )
                    }
                    .accessibilityIdentifier("project.auto-accept.class.\(cls.rawValue)")
                }
            }

            if !chats.isEmpty {
                Section(L("Chats in this Project")) {
                    ForEach(chats) { session in
                        chatRow(session)
                    }
                }
            }
        }
        .navigationTitle(L("Auto-accept"))
    }

    private func chatRow(_ session: SessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.displayTitle)
                .font(.system(size: 15, weight: .semibold))
            Picker(L("Auto-accept"), selection: chatBinding(session)) {
                Text(L("Use Project level")).tag(String?.none)
                ForEach(AutoAcceptLevel.allCases) { level in
                    Text(level.title).tag(String?.some(level.rawValue))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func chatBinding(_ session: SessionInfo) -> Binding<String?> {
        Binding(
            get: { model.autoAcceptBySession[session.sessionId] },
            set: { next in
                if let next {
                    model.setSessionAutoAccept(session.sessionId, next)
                } else {
                    model.clearSessionAutoAccept(session.sessionId)
                }
            }
        )
    }

    private var pauseBinding: Binding<Bool> {
        Binding(
            get: { model.autoAcceptPaused },
            set: { model.setAutoAcceptPaused($0) }
        )
    }

    private var gatingBinding: Binding<Bool> {
        Binding(
            get: { model.gatingEnabled },
            set: { model.setGating($0) }
        )
    }
}

/// Computer-wide auto-accept, the same ladder the Project module uses.
struct AutoAcceptSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            Section {
                Toggle(L("Hold auto-accept"), isOn: Binding(
                    get: { model.autoAcceptPaused },
                    set: { model.setAutoAcceptPaused($0) }
                ))
                Toggle(L("GrantTap decides approvals"), isOn: Binding(
                    get: { model.gatingEnabled },
                    set: { model.setGating($0) }
                ))
            } footer: {
                Text(L("A Project can set its own level in Mesh. Governance ASK and DENY still win."))
            }

            Section(L("This computer")) {
                ForEach(AutoAcceptLevel.allCases) { level in
                    Button {
                        model.setAutoAcceptPaused(false)
                        if !model.gatingEnabled { model.setGating(true) }
                        model.setAutoAcceptDefault(level.rawValue)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(level.title)
                                Spacer()
                                if !model.autoAcceptPaused,
                                   AutoAcceptLevel.parse(model.autoAcceptDefault) == level {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.ok)
                                }
                            }
                            Text(level.blurb).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
        }
        .navigationTitle(L("Auto-accept"))
    }
}
