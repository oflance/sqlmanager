//
//  ContentView.swift
//  sqlmanager
//
//  Created by Oflance on 15.03.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum DetailScreen {
        case workspace
        case settings
    }

    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    @AppStorage("appTheme") private var appThemeRaw = AppTheme.auto.rawValue
    @AppStorage("settingsAccentColor") private var accentColorRaw = AppAccent.system.rawValue
    @AppStorage("settingsShowColoredIcons") private var showColoredIcons = true
    @AppStorage("settingsCompactSidebar") private var compactSidebar = false
    @AppStorage("settingsConfirmDelete") private var confirmDelete = true
    @AppStorage("settingsShowWelcome") private var showWelcomeOnStart = true
    @AppStorage("settingsAutoConnect") private var autoConnect = false
    @AppStorage("settingsRunQueryShortcut") private var runQueryShortcut = true
    @AppStorage("settingsUseSSL") private var defaultUseSSL = true
    @AppStorage("settingsTimeoutSeconds") private var defaultTimeoutSeconds = 15
    @State private var tree: [ConnectionNode] = []
    @State private var selectedNodeID: UUID?
    @State private var openTabs: [ConnectionTab] = []
    @State private var selectedRootTab: RootTab = .profiles
    @State private var isShowingConnectionsHub = false
    @State private var pendingDeleteNodeID: UUID?
    @State private var detailScreen: DetailScreen = .workspace
    @State private var hasLoadedPersistence = false
    @State private var persistenceSaveTask: DispatchWorkItem?
    @State private var dismissWelcomeForSession = false
    @State private var lastQueryExecutionByTab: [UUID: Date] = [:]
    @State private var queryTextByTab: [UUID: String] = [:]
    @State private var queryResultSummaryByTab: [UUID: String] = [:]
    @State private var queryResultByTab: [UUID: QueryExecutionResult] = [:]
    @State private var connectionDiagnosticByTab: [UUID: String] = [:]
    @State private var schemaSnapshotByTab: [UUID: SchemaSnapshot] = [:]
    @State private var schemaLoadingByTab: [UUID: Bool] = [:]
    @State private var selectedSchemaObjectPathByTab: [UUID: String] = [:]
    @State private var pendingManualImportSource: ProfileImportSource?
    @State private var isShowingManualImportPicker = false
    @State private var importFeedbackMessage = ""
    @State private var isShowingImportFeedback = false
    @State private var runtimeErrorMessage = ""
    @State private var isShowingRuntimeError = false
    private let persistence = SQLitePersistence()
    private let connectionManager = ConnectionManager(adapterRegistry: .default)

    private var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: appLanguageRaw) ?? .system }
        set { appLanguageRaw = newValue.rawValue }
    }

    private var appTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRaw) ?? .auto }
        set { appThemeRaw = newValue.rawValue }
    }

    private var appAccent: AppAccent {
        AppAccent(rawValue: accentColorRaw) ?? .system
    }

    private func t(_ key: String) -> String {
        L10n.tr(key, language: appLanguage)
    }

    var body: some View {
        rootBody
    }

    private var rootBody: some View {
        contentWithImportUI
            .preferredColorScheme(appTheme.colorScheme)
            .tint(appAccent.color)
    }

    private var contentWithImportUI: some View {
        contentWithPersistenceObservers
            .onReceive(NotificationCenter.default.publisher(for: .importProfilesRequested)) { notification in
                handleImportNotification(notification)
            }
            .fileImporter(
                isPresented: $isShowingManualImportPicker,
                allowedContentTypes: manualImportContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleManualImportSelection(result)
            }
            .alert("Import Profiles", isPresented: $isShowingImportFeedback) {
                Button(t("action.close"), role: .cancel) {}
            } message: {
                Text(importFeedbackMessage)
            }
            .alert("Connection Error", isPresented: $isShowingRuntimeError) {
                Button(t("action.close"), role: .cancel) {}
            } message: {
                Text(runtimeErrorMessage)
            }
    }

    private var contentWithPersistenceObservers: some View {
        contentWithConnectionSheet
            .onChange(of: selectedNodeID) { _, newValue in
                if newValue != nil {
                    detailScreen = .workspace
                    dismissWelcomeForSession = true
                }
                schedulePersistence()
            }
            .onChange(of: tree) { _, _ in
                schedulePersistence()
            }
            .onChange(of: openTabs) { _, _ in
                schedulePersistence()
            }
            .onChange(of: selectedRootTab) { _, _ in
                schedulePersistence()
            }
            .onChange(of: detailScreen) { _, _ in
                schedulePersistence()
            }
            .onAppear {
                loadPersistenceIfNeeded()
            }
            .onDisappear {
                persistenceSaveTask?.cancel()
                persistNow()
                Task {
                    await connectionManager.disconnectAll()
                }
            }
    }

    private var contentWithConnectionSheet: some View {
        contentSwitcher
            .sheet(isPresented: $isShowingConnectionsHub) {
                openedConnectionsScreen
            }
    }

    private var contentSwitcher: AnyView {
        if openTabs.isEmpty {
            return AnyView(profilesRootView)
        }
        return AnyView(tabbedRootView)
    }

    private var tabbedRootView: some View {
        TabView(selection: $selectedRootTab) {
            profilesRootView
                .tag(RootTab.profiles)
                .tabItem { Label(t("nav.profiles"), systemImage: "folder") }

            ForEach(openTabs) { tab in
                connectionTabView(for: tab.id)
                    .tag(RootTab.connection(tab.id))
                    .tabItem {
                        Label(tab.title, systemImage: tabStatusIcon(tab.status))
                    }
            }
        }
    }

    private var manualImportContentTypes: [UTType] {
        pendingManualImportSource?.allowedContentTypes ?? [.data]
    }

    private var profilesRootView: some View {
        NavigationSplitView {
            ProfilesSidebarView(
                tree: tree,
                selectedNodeID: $selectedNodeID,
                showColoredIcons: showColoredIcons,
                compactSidebar: compactSidebar,
                onAddFolder: { addFolder(parentID: $0) },
                onAddProfile: { addProfile(parentID: $0) },
                onOpenInTab: openTab(for:),
                onDeleteNode: requestDeleteNode,
                onOpenSettings: {
                    selectedNodeID = nil
                    detailScreen = .settings
                },
                t: t
            )
                .navigationTitle(t("nav.profiles"))
                .navigationSplitViewColumnWidth(min: compactSidebar ? 200 : 260, ideal: compactSidebar ? 220 : 280, max: compactSidebar ? 260 : 340)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            addFolder()
                        } label: {
                            Label(t("action.add_folder"), systemImage: "folder.badge.plus")
                        }

                        Button {
                            addProfile()
                        } label: {
                            Label(t("action.add_profile"), systemImage: "plus.rectangle.on.folder")
                        }

                        Button {
                            isShowingConnectionsHub = true
                        } label: {
                            Label(t("action.opened_connections"), systemImage: "square.grid.2x2")
                        }
                    }
                }
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .alert(t("action.delete"), isPresented: isShowingDeleteAlert) {
            Button(t("action.close"), role: .cancel) {
                pendingDeleteNodeID = nil
            }
            Button(t("action.delete"), role: .destructive) {
                confirmDeletePendingNode()
            }
        } message: {
            Text(deleteConfirmationMessage())
        }
    }

    private var workspace: some View {
        editorPane
            .frame(minWidth: 520)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch detailScreen {
        case .workspace:
            workspace
        case .settings:
            SettingsView(t: t)
                .frame(minWidth: 520)
        }
    }

    private var editorPane: some View {
        Group {
            if let selectedNodeID, let nodeBinding = bindingForNode(selectedNodeID) {
                ProfileNodeEditorContainerView(
                    node: nodeBinding,
                    folderDestinations: folderDestinations(for: selectedNodeID),
                    currentParentID: findParentID(of: selectedNodeID),
                    onMoveToParent: { moveSelectedNode(selectedNodeID, toParentID: $0) },
                    onOpenConnection: {
                        openTab(for: nodeBinding.wrappedValue)
                    },
                    onTestProfileConnection: { profile, credential in
                        try await connectionManager.testConnection(profile: profile, credential: credential)
                    }
                )
            } else {
                if showWelcomeOnStart && dismissWelcomeForSession == false {
                    welcomePane
                } else {
                    ContentUnavailableView(
                        t("empty.select_profile_or_folder"),
                        systemImage: "sidebar.left",
                        description: Text(t("empty.create_in_tree"))
                    )
                }
            }
        }
        .padding()
    }

    private var welcomePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(t("empty.welcome.title"), systemImage: "hand.wave")
                .font(.title2.weight(.semibold))
            Text(t("empty.welcome.description"))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(t("action.add_folder")) {
                    addFolder(parentID: nil)
                }
                .buttonStyle(.bordered)
                Button(t("action.add_profile")) {
                    addProfile(parentID: nil)
                }
                .buttonStyle(.borderedProminent)
                Button(t("action.dismiss")) {
                    dismissWelcomeForSession = true
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var openedConnectionsScreen: some View {
        OpenedHubView(
            openTabs: openTabs,
            appLanguage: appLanguage,
            onCloseSheet: { isShowingConnectionsHub = false },
            onCloseTab: close(tabID:),
            onOpenTab: { tabID in
                selectedRootTab = .connection(tabID)
                isShowingConnectionsHub = false
            },
            onToggleConnection: toggleConnection(tabID:),
            t: t
        )
    }

    private func connectionTabView(for tabID: UUID) -> some View {
        Group {
            if let tabBinding = bindingForTab(tabID) {
                ConnectionWorkspaceView(
                    tab: tabBinding.wrappedValue,
                    appLanguage: appLanguage,
                    runQueryShortcut: runQueryShortcut,
                    diagnosticMessage: connectionDiagnosticByTab[tabID],
                    querySummary: lastQueryExecutionByTab[tabID] == nil ? nil : (queryResultSummaryByTab[tabID] ?? t("action.query_executed")),
                    schemaLoading: schemaLoadingByTab[tabID] == true,
                    schemaObjects: schemaObjectsForBrowser(tabID: tabID),
                    selectedSchemaPath: selectedSchemaObjectPathByTab[tabID],
                    queryResult: queryResultByTab[tabID],
                    suggestions: sqlSuggestions(for: tabID),
                    t: t,
                    queryText: queryBinding(for: tabID, databaseType: tabBinding.wrappedValue.databaseType),
                    onClose: {
                        close(tabID: tabID)
                    },
                    onToggleConnection: {
                        toggleConnection(tabID: tabID)
                    },
                    onTestTCP: {
                        testTCP(tabID: tabID)
                    },
                    onRunQuery: {
                        runQuery(tabID: tabID)
                    },
                    onRefreshSchema: {
                        refreshSchema(tabID: tabID)
                    },
                    onSelectSchemaObject: { objectPath in
                        selectedSchemaObjectPathByTab[tabID] = objectPath
                        if tabBinding.wrappedValue.status == .connected {
                            previewRows(for: objectPath, tabID: tabID)
                        }
                    },
                    onPreviewRows: { objectPath in
                        previewRows(for: objectPath, tabID: tabID)
                    },
                    onApplySuggestion: { suggestion in
                        applySuggestion(suggestion, tabID: tabID)
                    }
                )
            } else {
                ContentUnavailableView(t("tab.connection_not_found"), systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func addFolder() {
        addFolder(parentID: selectedNodeID)
    }

    private func addFolder(parentID: UUID?) {
        let newNode = ConnectionNode(
            name: t("name.new_folder"),
            kind: .folder,
            icon: "folder",
            color: .blue
        )
        insert(newNode, parentID: parentID)
    }

    private func addProfile() {
        addProfile(parentID: selectedNodeID)
    }

    private func addProfile(parentID: UUID?) {
        let newNode = ConnectionNode(
            name: t("name.new_connection"),
            kind: .profile,
            icon: "cylinder",
            color: .green,
            useSSL: defaultUseSSL,
            timeoutSeconds: defaultTimeoutSeconds
        )
        insert(newNode, parentID: parentID)
    }

    private func insert(_ node: ConnectionNode, parentID: UUID?) {
        guard let parentID else {
            tree.append(node)
            return
        }
        if appendAsChild(selectedNodeID: parentID, node: node, in: &tree) == false {
            tree.append(node)
        }
    }

    private func appendAsChild(selectedNodeID: UUID, node: ConnectionNode, in nodes: inout [ConnectionNode]) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == selectedNodeID {
                if nodes[index].kind == .folder {
                    nodes[index].children.append(node)
                } else {
                    nodes.append(node)
                }
                return true
            }
            if appendAsChild(selectedNodeID: selectedNodeID, node: node, in: &nodes[index].children) {
                return true
            }
        }
        return false
    }

    private func folderDestinations(for selectedNodeID: UUID) -> [NodeEditor.FolderDestination] {
        var destinations = [NodeEditor.FolderDestination(parentID: nil, title: t("action.move_to_root"))]
        let blockedIDs = blockedDestinationIDs(for: selectedNodeID)
        collectFolderDestinations(in: tree, blockedIDs: blockedIDs, result: &destinations)
        return destinations
    }

    private func moveSelectedNode(_ nodeID: UUID, toParentID parentID: UUID?) {
        _ = moveNode(draggedID: nodeID, targetParentID: parentID, childIndex: -1)
    }

    private func blockedDestinationIDs(for selectedID: UUID) -> Set<UUID> {
        guard let selectedNode = findNode(selectedID, in: tree) else { return [selectedID] }
        var blocked = Set<UUID>([selectedID])
        collectNodeIDs(in: selectedNode.children, result: &blocked)
        return blocked
    }

    private func collectNodeIDs(in nodes: [ConnectionNode], result: inout Set<UUID>) {
        for node in nodes {
            result.insert(node.id)
            collectNodeIDs(in: node.children, result: &result)
        }
    }

    private func collectFolderDestinations(
        in nodes: [ConnectionNode],
        blockedIDs: Set<UUID>,
        result: inout [NodeEditor.FolderDestination]
    ) {
        for node in nodes where node.kind == .folder {
            if blockedIDs.contains(node.id) == false {
                result.append(NodeEditor.FolderDestination(parentID: node.id, title: node.name))
            }
            collectFolderDestinations(in: node.children, blockedIDs: blockedIDs, result: &result)
        }
    }

    private func moveNode(draggedID: UUID, targetParentID: UUID?, childIndex: Int) -> Bool {
        guard let draggedNode = findNode(draggedID, in: tree) else { return false }

        if let targetParentID {
            if draggedID == targetParentID { return false }
            if containsNode(withID: targetParentID, in: draggedNode.children) { return false }
        }

        let sourceParentID = findParentID(of: draggedID)
        let sourceIndex = indexInParent(of: draggedID, parentID: sourceParentID)

        guard let detached = detachNode(withID: draggedID, from: &tree) else { return false }

        var adjustedIndex = childIndex
        if adjustedIndex >= 0, sourceParentID == targetParentID,
           let si = sourceIndex, si < adjustedIndex {
            adjustedIndex -= 1
        }

        if let targetParentID {
            if adjustedIndex < 0 {
                if !appendToFolder(parentID: targetParentID, node: detached, in: &tree) {
                    tree.append(detached)
                }
            } else {
                if !insertAtIndex(node: detached, parentID: targetParentID, index: adjustedIndex, in: &tree) {
                    tree.append(detached)
                }
            }
        } else {
            if adjustedIndex < 0 || adjustedIndex > tree.count {
                tree.append(detached)
            } else {
                tree.insert(detached, at: adjustedIndex)
            }
        }

        selectedNodeID = detached.id
        return true
    }

    private func containsNode(withID id: UUID, in nodes: [ConnectionNode]) -> Bool {
        for node in nodes {
            if node.id == id || containsNode(withID: id, in: node.children) {
                return true
            }
        }
        return false
    }

    private func detachNode(withID id: UUID, from nodes: inout [ConnectionNode]) -> ConnectionNode? {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            return nodes.remove(at: index)
        }
        for index in nodes.indices {
            if let detached = detachNode(withID: id, from: &nodes[index].children) {
                return detached
            }
        }
        return nil
    }

    private func findParentID(of nodeID: UUID) -> UUID? {
        return findParentID(of: nodeID, in: tree, parentID: nil)
    }

    private func findParentID(of nodeID: UUID, in nodes: [ConnectionNode], parentID: UUID?) -> UUID? {
        for node in nodes {
            if node.id == nodeID { return parentID }
            if let found = findParentID(of: nodeID, in: node.children, parentID: node.id) {
                return found
            }
        }
        return nil
    }

    private func indexInParent(of nodeID: UUID, parentID: UUID?) -> Int? {
        let siblings: [ConnectionNode]
        if let parentID, let parent = findNode(parentID, in: tree) {
            siblings = parent.children
        } else {
            siblings = tree
        }
        return siblings.firstIndex(where: { $0.id == nodeID })
    }

    private func appendToFolder(parentID: UUID, node: ConnectionNode, in nodes: inout [ConnectionNode]) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == parentID {
                nodes[i].children.append(node)
                return true
            }
            if appendToFolder(parentID: parentID, node: node, in: &nodes[i].children) {
                return true
            }
        }
        return false
    }

    private func insertAtIndex(node: ConnectionNode, parentID: UUID, index: Int, in nodes: inout [ConnectionNode]) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == parentID {
                let clampedIndex = min(index, nodes[i].children.count)
                nodes[i].children.insert(node, at: clampedIndex)
                return true
            }
            if insertAtIndex(node: node, parentID: parentID, index: index, in: &nodes[i].children) {
                return true
            }
        }
        return false
    }

    private var isShowingDeleteAlert: Binding<Bool> {
        Binding(
            get: { pendingDeleteNodeID != nil },
            set: { isPresented in
                if isPresented == false {
                    pendingDeleteNodeID = nil
                }
            }
        )
    }

    private func deleteConfirmationMessage() -> String {
        guard
            let pendingDeleteNodeID,
            let node = findNode(pendingDeleteNodeID, in: tree)
        else {
            return t("action.delete")
        }
        return "\(t("action.delete")) \"\(node.name)\"?"
    }

    private func requestDeleteSelectedNode() {
        guard let selectedNodeID else { return }
        requestDeleteNode(selectedNodeID)
    }

    private func requestDeleteNode(_ nodeID: UUID) {
        if confirmDelete {
            pendingDeleteNodeID = nodeID
        } else {
            deleteNode(nodeID)
        }
    }

    private func confirmDeletePendingNode() {
        guard let nodeID = pendingDeleteNodeID else { return }
        pendingDeleteNodeID = nil
        deleteNode(nodeID)
    }

    private func deleteNode(_ nodeID: UUID) {
        let tabIDs = openTabs.filter { $0.profileID == nodeID }.map(\.id)
        for tabID in tabIDs {
            Task {
                await connectionManager.disconnect(tabID: tabID)
            }
        }
        remove(nodeID, from: &tree)
        openTabs.removeAll(where: { $0.profileID == nodeID })
        for tabID in tabIDs {
            lastQueryExecutionByTab.removeValue(forKey: tabID)
            queryTextByTab.removeValue(forKey: tabID)
            queryResultSummaryByTab.removeValue(forKey: tabID)
        }
        if case .connection(let activeID) = selectedRootTab, openTabs.contains(where: { $0.id == activeID }) == false {
            selectedRootTab = .profiles
        }
        if selectedNodeID == nodeID {
            selectedNodeID = nil
        }
    }

    @discardableResult
    private func remove(_ id: UUID, from nodes: inout [ConnectionNode]) -> Bool {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes.remove(at: index)
            return true
        }
        for index in nodes.indices {
            if remove(id, from: &nodes[index].children) {
                return true
            }
        }
        return false
    }

    private func openTab(for node: ConnectionNode) {
        guard node.kind == .profile else { return }
        if let existing = openTabs.first(where: { $0.profileID == node.id }) {
            selectedRootTab = .connection(existing.id)
            return
        }
        let tab = ConnectionTab(
            profileID: node.id,
            title: node.name,
            databaseType: node.databaseType,
            connectionMethod: node.connectionMethod,
            useSSL: node.useSSL,
            timeoutSeconds: node.timeoutSeconds,
            status: autoConnect ? .connected : .disconnected
        )
        openTabs.append(tab)
        selectedRootTab = .connection(tab.id)
    }

    private func close(tabID: UUID) {
        Task {
            await connectionManager.disconnect(tabID: tabID)
        }
        openTabs.removeAll(where: { $0.id == tabID })
        lastQueryExecutionByTab.removeValue(forKey: tabID)
        queryTextByTab.removeValue(forKey: tabID)
        queryResultSummaryByTab.removeValue(forKey: tabID)
        queryResultByTab.removeValue(forKey: tabID)
        connectionDiagnosticByTab.removeValue(forKey: tabID)
        schemaSnapshotByTab.removeValue(forKey: tabID)
        schemaLoadingByTab.removeValue(forKey: tabID)
        selectedSchemaObjectPathByTab.removeValue(forKey: tabID)
        if case .connection(let selectedID) = selectedRootTab, selectedID == tabID {
            selectedRootTab = .profiles
        }
    }

    private func toggleConnection(tabID: UUID) {
        guard let index = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        switch openTabs[index].status {
        case .connected:
            openTabs[index].status = .disconnected
            Task {
                await connectionManager.disconnect(tabID: tabID)
                schemaSnapshotByTab[tabID] = nil
                schemaLoadingByTab[tabID] = nil
                selectedSchemaObjectPathByTab[tabID] = nil
            }
        case .disconnected:
            guard let profile = findNode(openTabs[index].profileID, in: tree) else {
                presentRuntimeError(DatabaseAdapterError.configurationInvalid(reason: "Profile not found"))
                return
            }
            openTabs[index].status = .connecting
            Task {
                do {
                    let credential: DatabaseCredential
                    if let password = PasswordKeychain.loadPassword(forProfileID: profile.id),
                       password.isEmpty == false
                    {
                        credential = .password(password)
                    } else {
                        credential = .none
                    }

                    try await connectionManager.connect(tabID: tabID, profile: profile, credential: credential)
                    guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
                    if openTabs[idx].status == .connecting {
                        openTabs[idx].status = .connected
                        connectionDiagnosticByTab[tabID] = nil
                    }
                    await loadSchema(tabID: tabID)
                } catch {
                    guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
                    openTabs[idx].status = .disconnected
                    presentRuntimeError(error)
                }
            }
        case .connecting:
            openTabs[index].status = .disconnected
            Task {
                await connectionManager.disconnect(tabID: tabID)
                schemaSnapshotByTab[tabID] = nil
                schemaLoadingByTab[tabID] = nil
                selectedSchemaObjectPathByTab[tabID] = nil
            }
        }
    }

    private func testTCP(tabID: UUID) {
        guard let tab = openTabs.first(where: { $0.id == tabID }) else { return }
        guard let profile = findNode(tab.profileID, in: tree) else {
            presentRuntimeError(DatabaseAdapterError.configurationInvalid(reason: "Profile not found"))
            return
        }

        connectionDiagnosticByTab[tabID] = t("status.testing_tcp")
        Task {
            do {
                let endpoint = try await connectionManager.testTCP(profile: profile)
                connectionDiagnosticByTab[tabID] = "\(t("status.tcp_ok")) \(endpoint)"
            } catch {
                let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                connectionDiagnosticByTab[tabID] = text
            }
        }
    }

    private func bindingForNode(_ id: UUID) -> Binding<ConnectionNode>? {
        guard findNode(id, in: tree) != nil else { return nil }
        return Binding(
            get: { findNode(id, in: tree) ?? ConnectionNode.empty },
            set: { updated in
                updateNode(updated, in: &tree)
                if let tabIndex = openTabs.firstIndex(where: { $0.profileID == updated.id }) {
                    openTabs[tabIndex].title = updated.name
                    openTabs[tabIndex].databaseType = updated.databaseType
                    openTabs[tabIndex].connectionMethod = updated.connectionMethod
                    openTabs[tabIndex].useSSL = updated.useSSL
                    openTabs[tabIndex].timeoutSeconds = updated.timeoutSeconds
                }
            }
        )
    }

    private func bindingForTab(_ id: UUID) -> Binding<ConnectionTab>? {
        guard openTabs.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { openTabs.first(where: { $0.id == id }) ?? ConnectionTab.empty },
            set: { updated in
                guard let index = openTabs.firstIndex(where: { $0.id == id }) else { return }
                openTabs[index] = updated
            }
        )
    }

    private func findNode(_ id: UUID, in nodes: [ConnectionNode]) -> ConnectionNode? {
        for node in nodes {
            if node.id == id { return node }
            if let child = findNode(id, in: node.children) { return child }
        }
        return nil
    }

    @discardableResult
    private func updateNode(_ updated: ConnectionNode, in nodes: inout [ConnectionNode]) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == updated.id {
                nodes[index] = updated
                return true
            }
            if updateNode(updated, in: &nodes[index].children) {
                return true
            }
        }
        return false
    }

    private func runQuery(tabID: UUID) {
        guard let tab = openTabs.first(where: { $0.id == tabID }), tab.status == .connected else { return }
        let sql = queryTextByTab[tabID]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (queryTextByTab[tabID] ?? "")
            : defaultQuery(for: tab.databaseType)
        Task {
            do {
                let result = try await connectionManager.execute(tabID: tabID, sql: sql)
                lastQueryExecutionByTab[tabID] = Date()
                queryResultByTab[tabID] = result
                queryResultSummaryByTab[tabID] = summarize(result: result)
            } catch {
                presentRuntimeError(error)
            }
        }
    }

    private func refreshSchema(tabID: UUID) {
        Task {
            await loadSchema(tabID: tabID)
        }
    }

    private func loadSchema(tabID: UUID) async {
        schemaLoadingByTab[tabID] = true
        defer { schemaLoadingByTab[tabID] = false }
        do {
            let snapshot = try await connectionManager.introspect(tabID: tabID)
            schemaSnapshotByTab[tabID] = snapshot
            if let existing = selectedSchemaObjectPathByTab[tabID],
               snapshot.objects.contains(where: { $0.path == existing }) == false
            {
                selectedSchemaObjectPathByTab[tabID] = nil
            }
        } catch {
            connectionDiagnosticByTab[tabID] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func schemaObjectsForBrowser(tabID: UUID) -> [SchemaObject] {
        guard let snapshot = schemaSnapshotByTab[tabID] else { return [] }
        return snapshot.objects
            .filter { $0.kind == .table || $0.kind == .view }
            .sorted { $0.path < $1.path }
    }

    private func previewRows(for objectPath: String, tabID: UUID) {
        queryTextByTab[tabID] = "SELECT * FROM \(objectPath) LIMIT 100;"
        runQuery(tabID: tabID)
    }

    private func queryBinding(for tabID: UUID, databaseType: DatabaseType) -> Binding<String> {
        Binding(
            get: {
                queryTextByTab[tabID] ?? defaultQuery(for: databaseType)
            },
            set: { newValue in
                queryTextByTab[tabID] = newValue
            }
        )
    }

    private func sqlSuggestions(for tabID: UUID) -> [String] {
        let text = queryTextByTab[tabID] ?? ""
        let keywords = [
            "SELECT", "FROM", "WHERE", "JOIN", "ORDER BY", "GROUP BY", "LIMIT",
            "INSERT INTO", "UPDATE", "DELETE FROM", "CREATE TABLE"
        ]
        let tableNames = schemaObjectsForBrowser(tabID: tabID).map(\.path)

        let source = text.isEmpty ? keywords + tableNames : tableNames + keywords
        var unique: [String] = []
        var seen = Set<String>()
        for item in source {
            if seen.insert(item).inserted {
                unique.append(item)
            }
            if unique.count >= 8 {
                break
            }
        }
        return unique
    }

    private func applySuggestion(_ suggestion: String, tabID: UUID) {
        let current = queryTextByTab[tabID] ?? ""
        if current.isEmpty {
            queryTextByTab[tabID] = "\(suggestion) "
        } else if current.hasSuffix(" ") || current.hasSuffix("\n") {
            queryTextByTab[tabID] = current + suggestion + " "
        } else {
            queryTextByTab[tabID] = current + " " + suggestion + " "
        }
    }

    private func defaultQuery(for databaseType: DatabaseType) -> String {
        switch databaseType {
        case .sqlite:
            return "SELECT name, type FROM sqlite_master ORDER BY type, name LIMIT 25;"
        case .postgresql:
            return "SELECT NOW() AS current_time;"
        case .mysql:
            return "SELECT NOW() AS current_time;"
        case .mssql:
            return "SELECT GETDATE() AS current_time;"
        case .oracle:
            return "SELECT CURRENT_TIMESTAMP AS current_time FROM dual"
        }
    }

    private func summarize(result: QueryExecutionResult) -> String {
        if let affectedRows = result.affectedRows {
            return "\(t("query.result.affected")): \(affectedRows), \(t("query.result.duration")): \(result.durationMs) ms"
        }
        return "\(t("query.result.rows")): \(result.rows.count), \(t("query.result.duration")): \(result.durationMs) ms"
    }

    private func tabStatusIcon(_ status: ConnectionStatus) -> String {
        switch status {
        case .connected:
            return "bolt.horizontal.circle.fill"
        case .connecting:
            return "hourglass.circle"
        case .disconnected:
            return "bolt.horizontal.circle"
        }
    }

    private func presentRuntimeError(_ error: Error) {
        if let localized = (error as? LocalizedError)?.errorDescription, localized.isEmpty == false {
            runtimeErrorMessage = localized
        } else {
            runtimeErrorMessage = error.localizedDescription
        }
        isShowingRuntimeError = true
    }

    private func loadPersistenceIfNeeded() {
        guard hasLoadedPersistence == false else { return }
        hasLoadedPersistence = true

        if let savedTree = persistence.loadTree() {
            tree = savedTree
        }

        guard let snapshot = persistence.loadWorkspace() else { return }
        openTabs = snapshot.openTabs
        selectedRootTab = snapshot.selectedRootTab
        selectedNodeID = snapshot.selectedNodeID
        detailScreen = snapshot.isSettingsOpen ? .settings : .workspace
    }

    private func schedulePersistence() {
        persistenceSaveTask?.cancel()
        let task = DispatchWorkItem {
            persistNow()
        }
        persistenceSaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func persistNow() {
        do {
            try persistence.saveTree(tree)
            let snapshot = WorkspaceSnapshot(
                openTabs: openTabs,
                selectedRootTab: selectedRootTab,
                selectedNodeID: selectedNodeID,
                isSettingsOpen: detailScreen == .settings
            )
            try persistence.saveWorkspace(snapshot)
        } catch {
            return
        }
    }

    private func handleImportRequest(from source: ProfileImportSource) {
        let result = ExternalProfileImporter.importFromDefaultLocations(for: source)
        if result.discoveredFiles.isEmpty {
            pendingManualImportSource = source
            isShowingManualImportPicker = true
            return
        }
        applyImportResult(result)
    }

    private func handleImportNotification(_ notification: Notification) {
        guard
            let rawValue = notification.object as? String,
            let source = ProfileImportSource(rawValue: rawValue)
        else {
            return
        }
        handleImportRequest(from: source)
    }

    private func handleManualImportSelection(_ result: Result<[URL], Error>) {
        guard let source = pendingManualImportSource else { return }
        pendingManualImportSource = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importFeedbackMessage = "No file selected."
                isShowingImportFeedback = true
                return
            }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let importResult = ExternalProfileImporter.importFromFile(url, source: source)
            applyImportResult(importResult)
        case .failure(let error):
            importFeedbackMessage = "Import cancelled or failed: \(error.localizedDescription)"
            isShowingImportFeedback = true
        }
    }

    private struct ImportApplyReport {
        var importedProfiles = 0
        var skippedExistingDuplicates = 0
        var createdFolders = 0
        var savedPasswords = 0
        var failedPasswordSaves = 0
    }

    private func applyImportResult(_ result: ProfileImportBatchResult) {
        if result.importedItems.isEmpty {
            if result.errors.isEmpty {
                importFeedbackMessage = "No profiles found for \(result.source.displayName)."
            } else {
                importFeedbackMessage = "Could not import \(result.source.displayName):\n" + result.errors.joined(separator: "\n")
            }
            isShowingImportFeedback = true
            return
        }

        let report = appendImportedProfiles(result.importedItems, source: result.source)

        var lines: [String] = []
        lines.append("Import source: \(result.source.displayName)")
        lines.append("Scanned files: \(result.processedFileCount)")
        lines.append("Imported profiles: \(report.importedProfiles)")
        lines.append("Skipped existing duplicates: \(report.skippedExistingDuplicates)")
        lines.append("Skipped duplicates in source file(s): \(result.duplicateItemsInSource)")
        lines.append("Created folders: \(report.createdFolders)")
        lines.append("Password candidates: \(result.plaintextPasswordCandidates)")
        lines.append("Passwords saved to Keychain: \(report.savedPasswords)")
        if report.failedPasswordSaves > 0 {
            lines.append("Password save failures: \(report.failedPasswordSaves)")
        }
        if result.encryptedPasswordCount > 0 {
            lines.append("Encrypted/unsupported passwords: \(result.encryptedPasswordCount)")
        }

        var message = lines.joined(separator: "\n")
        if result.errors.isEmpty == false {
            message += "\n\nSome files failed:\n" + result.errors.joined(separator: "\n")
        }
        importFeedbackMessage = message
        isShowingImportFeedback = true
    }

    private func appendImportedProfiles(_ items: [ImportedProfileItem], source: ProfileImportSource) -> ImportApplyReport {
        let rootFolderIndex = ensureImportRootFolderIndex(for: source)
        var report = ImportApplyReport()

        var existingSignatures = Set<String>()
        collectExistingImportSignatures(in: tree[rootFolderIndex].children, currentFolderPath: [], result: &existingSignatures)

        for item in items {
            let signature = importSignature(for: item.node, folderPath: item.folderPath)
            if existingSignatures.contains(signature) {
                report.skippedExistingDuplicates += 1
                continue
            }

            report.createdFolders += insertImportedNode(item.node, folderPath: item.folderPath, into: &tree[rootFolderIndex].children)
            existingSignatures.insert(signature)
            report.importedProfiles += 1

            if let password = item.plaintextPassword, password.isEmpty == false {
                if PasswordKeychain.save(password: password, forProfileID: item.node.id) {
                    report.savedPasswords += 1
                } else {
                    report.failedPasswordSaves += 1
                }
            }
        }
        selectedNodeID = tree[rootFolderIndex].id
        return report
    }

    private func ensureImportRootFolderIndex(for source: ProfileImportSource) -> Int {
        if let existingIndex = tree.firstIndex(where: { $0.kind == .folder && $0.name == source.importFolderName }) {
            return existingIndex
        }

        let folder = ConnectionNode(
            name: source.importFolderName,
            kind: .folder,
            icon: "tray.and.arrow.down",
            color: .indigo,
            children: []
        )
        tree.append(folder)
        return tree.count - 1
    }

    private func insertImportedNode(_ node: ConnectionNode, folderPath: [String], into nodes: inout [ConnectionNode]) -> Int {
        guard let currentFolder = folderPath.first else {
            nodes.append(node)
            return 0
        }

        let remainingPath = Array(folderPath.dropFirst())
        let folderIndex: Int
        let createdFolders: Int
        if let existingFolderIndex = nodes.firstIndex(where: { $0.kind == .folder && $0.name == currentFolder }) {
            folderIndex = existingFolderIndex
            createdFolders = 0
        } else {
            nodes.append(
                ConnectionNode(
                    name: currentFolder,
                    kind: .folder,
                    icon: "folder",
                    color: .blue
                )
            )
            folderIndex = nodes.count - 1
            createdFolders = 1
        }

        return createdFolders + insertImportedNode(node, folderPath: remainingPath, into: &nodes[folderIndex].children)
    }

    private func collectExistingImportSignatures(
        in nodes: [ConnectionNode],
        currentFolderPath: [String],
        result: inout Set<String>
    ) {
        for node in nodes {
            if node.kind == .folder {
                collectExistingImportSignatures(in: node.children, currentFolderPath: currentFolderPath + [node.name], result: &result)
            } else {
                result.insert(importSignature(for: node, folderPath: currentFolderPath))
            }
        }
    }

    private func importSignature(for node: ConnectionNode, folderPath: [String]) -> String {
        [
            folderPath.joined(separator: "/"),
            node.name,
            node.databaseType.rawValue,
            node.connectionMethod.rawValue,
            node.host,
            node.port,
            node.database,
            node.username
        ].joined(separator: "|")
    }
}

#Preview {
    ContentView()
}
