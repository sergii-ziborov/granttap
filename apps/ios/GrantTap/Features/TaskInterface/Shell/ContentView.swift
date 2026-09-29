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
    case settings
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
    @State var showMeshJoin = false
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
    #if targetEnvironment(macCatalyst)
    @StateObject var macLocalMCP = MacLocalMCPModel()
    @ObservedObject var desktopLicense = DesktopLicenseStore.shared
    @State var macNavigationRevision = 0
    @State var macNavigationPath: [MacMainWindowRoute] = []
    @State var showNewMesh = false
    #endif

    @State var showCapabilityUsage = false
    @State var showChatHistory = false

    /// Debug launch tab, e.g. `GRANTTAP_TAB=projects`.
    static var launchTab: PersonalTab? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["GRANTTAP_TAB"]?.lowercased() {
        case "now": return .now
        case "tasks": return .tasks
        case "projects": return .projects
        case "usage": return .usage
        #if targetEnvironment(macCatalyst)
        case "settings": return .settings
        #endif
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
        #if targetEnvironment(macCatalyst)
        _selectedTab = State(initialValue: showSettings ? .settings : (Self.launchTab ?? selectedTab))
        #else
        _selectedTab = State(initialValue: Self.launchTab ?? selectedTab)
        #endif
        _showPairing = State(initialValue: showPairing)
        #if targetEnvironment(macCatalyst)
        _showSettings = State(initialValue: false)
        #else
        _showSettings = State(initialValue: showSettings)
        #endif
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
        #if targetEnvironment(macCatalyst)
        _macNavigationPath = State(initialValue: openedSession.map { [.chat($0.id)] } ?? [])
        #endif
        _pendingPairing = State(initialValue: pendingPairing)
        _pairingLinkError = State(initialValue: pairingLinkError)
    }

    var body: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            ZStack {
                HStack(spacing: 0) {
                    if macLocalMCP.isReady || model.pairing != nil || model.demoMode || selectedTab == .settings {
                        macSidebar
                        Divider()
                    }
                    VStack(spacing: 0) {
                        MacBrandHeader()
                            .allowsHitTesting(false)
                        navigationRoot
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .ignoresSafeArea(.container, edges: .top)
                }
                privacyLayers
            }
            #else
            navigationRoot
            #endif
        }
        .sheet(isPresented: $showPairing) { PairingSheet().environmentObject(model) }
        .sheet(isPresented: $showMeshJoin) {
            PairingSheet(purpose: .joinProject).environmentObject(model)
        }
        #if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(model)
        }
        #endif
        #if targetEnvironment(macCatalyst)
        .sheet(isPresented: $showNewMesh) {
            MacNewMeshView(reader: macLocalMCP) { await refreshMacLocal() }
        }
        #endif
        .sheet(isPresented: $showConnectionDetail) {
            ConnectionDetailSheet().environmentObject(model)
        }
        #if targetEnvironment(macCatalyst)
        .sheet(isPresented: $showNewTask) { newTaskSheet }
        #else
        .fullScreenCover(isPresented: $showNewTask) { newTaskSheet }
        #endif
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
        .onReceive(SubscriptionStore.shared.$entitlement) { _ in
            #if !DEBUG
            for client in model.relaysByRoom.values { client.forceReconnect() }
            #endif
        }
        #if targetEnvironment(macCatalyst)
        .onReceive(NotificationCenter.default.publisher(for: ProductInformation.requested)) { notification in
            guard let information = notification.object as? ProductInformation else { return }
            selectMacTab(.settings)
            macNavigationPath = [.information(information)]
        }
        .onChange(of: openedSession) { destination in
            navigateMacChat(destination)
            loadMacLocalActivity(destination)
        }
        .onChange(of: macNavigationPath) { path in
            if let session = openedSession, !path.contains(.chat(session.id)) {
                openedSession = nil
            }
        }
        #endif
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
            #if targetEnvironment(macCatalyst)
            await desktopLicense.start()
            await refreshMacLocal()
            #endif
            if model.sessions.isEmpty {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await model.refreshSessions()
            }
            while !Task.isCancelled {
                #if targetEnvironment(macCatalyst)
                let refreshDelay: UInt64 = macLocalMCP.isReady
                    ? 5_000_000_000 : 3_000_000_000
                #else
                let refreshDelay: UInt64 = 30_000_000_000
                #endif
                try? await Task.sleep(nanoseconds: refreshDelay)
                guard !Task.isCancelled else { return }
                if model.connectionSnapshot.phase == .macOffline { await model.refreshSessions() }
                #if targetEnvironment(macCatalyst)
                await refreshMacLocal()
                #endif
            }
        }
        .preferredColorScheme(nil)
    }

}
