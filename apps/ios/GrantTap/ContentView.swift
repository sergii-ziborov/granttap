import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct OpenSession: Identifiable, Hashable {
    let id: String
}

enum PersonalTab: Hashable {
    case now
    case tasks
    case projects
    case usage
}

struct ContentView: View {
    @EnvironmentObject private var environmentModel: AppModel
    var modelOverride: AppModel?
    let securePairingFetcher: PairingSheet.SecurePairingFetcher
    var model: AppModel { modelOverride ?? environmentModel }
    @Environment(\.scenePhase) var scenePhase
    @ObservedObject var security: SecurityGate
    @State var selectedTab: PersonalTab = .now
    @State var showPairing = false
    @State var showSettings = false
    @State var showConnectionDetail = false
    @State var showNewTask = false
    @State var showNewTaskRoute = false
    @State var messageText = ""
    @State var openedSession: OpenSession?
    /// What was in front when the screen went dark or the lock came down.
    @State var lockedAway: LockedAway?
    @State var openedTaskRoute: TaskRoute?
    @StateObject var dictator: Dictator
    @FocusState var composeFocused: Bool
    @State var replyRequestId: String?
    @State var pendingPairing: Pairing?
    @State var pairingLinkError: String?
    @State var composeSessionId: String?
    @State var composeAgent: String = {
        #if DEBUG
        AgentIdentity.normalize(ProcessInfo.processInfo.environment["GRANTTAP_AGENT_PAGE"] ?? "codex")
        #else
        "codex"
        #endif
    }()
    @AppStorage("granttap.new-task.provider") var savedComposeAgent = ""
    @State var newTaskCwd = ""
    @State var composeRoomId: String?
    @State var attachments: [AttachmentDraft] = []
    @State var attachmentError: String?
    @State var sessionSearch = ""
    @State var showArchivedSessions = false
    @State var revealedSessionAction: String?

    @State var showCapabilityUsage = false
    @State var showChatHistory = false

    /// A tab to open on launch, for a screenshot or a check on a simulator
    /// nobody can tap: `GRANTTAP_TAB=projects`. Debug builds only.
    static var launchTab: PersonalTab? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["GRANTTAP_TAB"]?.lowercased() {
        case "now": return .now
        case "tasks": return .tasks
        case "projects": return .projects
        case "usage": return .usage
        default: return nil
        }
        #else
        return nil
        #endif
    }

    init(selectedTab: PersonalTab = .now,
         showPairing: Bool = false,
         showSettings: Bool = false,
         showConnectionDetail: Bool = false,
         showNewTask: Bool = false,
         showNewTaskRoute: Bool = false,
         composeSessionId: String? = nil,
         messageText: String = "",
         attachments: [AttachmentDraft] = [],
         attachmentError: String? = nil,
         sessionSearch: String = "",
         showArchivedSessions: Bool = false,
         replyRequestId: String? = nil,
         composeAgent: String = "codex",
         newTaskCwd: String = "",
         composeRoomId: String? = nil,
         modelOverride: AppModel? = nil,
         security: SecurityGate? = nil,
         openedSession: OpenSession? = nil,
         pendingPairing: Pairing? = nil,
         pairingLinkError: String? = nil,
         dictator: Dictator? = nil,
         securePairingFetcher: @escaping PairingSheet.SecurePairingFetcher = { link in
             await Pairing.fetchSecurePairing(
                 relayBase: link.relayBase, mailboxId: link.mailboxId,
                 transferKey: link.transferKey
             )
         }) {
        self.modelOverride = modelOverride
        self.securePairingFetcher = securePairingFetcher
        self.security = security ?? .shared
        _selectedTab = State(initialValue: Self.launchTab ?? selectedTab)
        _showPairing = State(initialValue: showPairing)
        _showSettings = State(initialValue: showSettings)
        _showConnectionDetail = State(initialValue: showConnectionDetail)
        _showNewTask = State(initialValue: showNewTask)
        _showNewTaskRoute = State(initialValue: showNewTaskRoute)
        _composeSessionId = State(initialValue: composeSessionId)
        _messageText = State(initialValue: messageText)
        _attachments = State(initialValue: attachments)
        _attachmentError = State(initialValue: attachmentError)
        _sessionSearch = State(initialValue: sessionSearch)
        _showArchivedSessions = State(initialValue: showArchivedSessions)
        _dictator = StateObject(wrappedValue: dictator ?? Dictator())
        _replyRequestId = State(initialValue: replyRequestId)
        _composeAgent = State(initialValue: AgentIdentity.normalize(composeAgent))
        _newTaskCwd = State(initialValue: newTaskCwd)
        _composeRoomId = State(initialValue: composeRoomId)
        _openedSession = State(initialValue: openedSession)
        _pendingPairing = State(initialValue: pendingPairing)
        _pairingLinkError = State(initialValue: pairingLinkError)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if model.pairing == nil && !model.demoMode {
                    onboarding
                } else {
                    personalTabs
                }
                privacyLayers
            }
            .background(
                NavigationLink(destination: openedSessionDestination,
                               isActive: chatNavigationActive) { EmptyView() }
                    .hidden()
            )
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(security.showsLockUI)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !security.showsLockUI,
                       model.pairing != nil || model.demoMode { connectionBadge }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !security.showsLockUI,
                       model.pairing != nil || model.demoMode {
                        if selectedTab == .now || selectedTab == .tasks {
                            Button { prepareNewTask() } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(L("New Task"))
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(L("Settings"))
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showPairing) { PairingSheet().environmentObject(model) }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(model) }
        .sheet(isPresented: $showConnectionDetail) {
            ConnectionDetailSheet().environmentObject(model)
        }
        .fullScreenCover(isPresented: $showNewTask) { newTaskSheet }
        .sheet(item: $openedTaskRoute) { route in
            TaskRouteView(route: route, model: model) { session in open(session) }
        }
        .onChange(of: model.sessions) { sessions in
            openRequestedSession(from: sessions)
            if let selected = composeSessionId, replyRequestId == nil,
               !sessions.contains(where: { $0.sessionId == selected }) {
                composeSessionId = nil
            }
            #if DEBUG
            autoOpenDebugSessionIfNeeded(from: sessions)
            #endif
        }
        .onChange(of: security.launching) { launching in
            guard !launching else { return }
            openRequestedSession(from: model.sessions)
            #if DEBUG
            autoOpenDebugSessionIfNeeded(from: model.sessions)
            #endif
        }
        .onChange(of: model.sessionToOpen) { _ in openRequestedSession(from: model.sessions) }
        .onOpenURL(perform: handlePairingURL)
        .alert(L("Add this computer?"), isPresented: pairingPrompt,
               presenting: pendingPairing) { pairing in
            Button(L("Add link")) {
                if !model.setPairing(pairing) {
                    pairingLinkError = AppModel.pairingStorageFailureMessage
                }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: { pairing in
            Text(String(format: L("Relay %@ · room %@\n\nContinue only if you started this on your own computer."),
                        Self.relayHost(pairing.relayUrl), pairing.room))
        }
        .alert(L("Could not pair"), isPresented: pairingErrorPrompt) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(pairingLinkError ?? L("Unknown pairing error.")) }
        .onAppear(perform: handleAppear)
        .onChange(of: scenePhase, perform: handleScenePhase)
        .onChange(of: security.locked, perform: handleLockChange)
        .task {
            if model.sessions.isEmpty {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await model.refreshSessions()
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                if model.connectionSnapshot.phase == .macOffline { await model.refreshSessions() }
            }
        }
        .preferredColorScheme(nil)
    }

    private var navigationTitle: String {
        switch selectedTab {
        case .now: return "GrantTap"
        case .tasks: return L("Tasks")
        case .projects: return L("Projects")
        case .usage: return L("Usage")
        }
    }

    func prepareNewTask() {
        composeSessionId = nil
        replyRequestId = nil
        composeAgent = TaskComposerRoutePresentation.defaultProvider(
            saved: savedComposeAgent, sessions: model.sessions,
            enabledProviders: model.agentMeshPreferences.enabledProviders
        )
        showNewTask = true
        DispatchQueue.main.async { composeFocused = true }
    }

    func handlePairingURL(_ url: URL) {
        if let pairing = Pairing.fromURI(url.absoluteString) {
            showPairing = false
            showSettings = false
            openedSession = nil
            pendingPairing = pairing
        } else if let link = Pairing.secureLink(fromURI: url.absoluteString) {
            fetchPairing(link)
        }
    }
}
