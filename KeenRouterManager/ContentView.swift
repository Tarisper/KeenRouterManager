import SwiftUI
import UniformTypeIdentifiers

private enum LayoutMetrics {
    static let sidebarWidth: CGFloat = 280
    static let inspectorWidth: CGFloat = 320
    static let statusColumnWidth: CGFloat = 60
    static let statusIndicatorSize: CGFloat = 8
    static let clientColumnIdealWidth: CGFloat = 180
    static let clientColumnMinimumWidth: CGFloat = 180
    static let ipColumnWidth: CGFloat = 100
    static let segmentColumnIdealWidth: CGFloat = 130
    static let segmentColumnMinimumWidth: CGFloat = 130
    static let connectionColumnWidth: CGFloat = 150
    static let policyColumnWidth: CGFloat = 150
    static let minimumWindowWidth: CGFloat = 1240
    static let minimumWindowHeight: CGFloat = 760
}

private enum ClientStatusFilter: String, CaseIterable, Identifiable {
    case all
    case online
    case offline
    case blocked

    var id: String { rawValue }
}

private enum ClientSortMode: String, CaseIterable, Identifiable {
    case smart
    case name
    case ip
    case segment
    case policy

    var id: String { rawValue }
}

private enum ClientPolicyFilter: Equatable {
    case all
    case defaultPolicy
    case blocked
    case policy(String)
}

/**
 * Main application window with router sidebar, searchable client table,
 * and a sheet-based client details panel.
 */
struct ContentView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var viewModel: MainViewModel
    @EnvironmentObject private var appUI: AppUIState

    @State private var editorPayload: RouterEditorPayload?
    @State private var isDeleteConfirmationShown = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var searchText = ""
    @State private var statusFilter: ClientStatusFilter = .all
    @State private var sortMode: ClientSortMode = .smart
    @State private var policyFilter: ClientPolicyFilter = .all
    @State private var segmentFilter: String?
    @State private var isConnectActionPending = false
    @SceneStorage("mainWindow.isInspectorPresented") private var isInspectorPresented = false

    private var visibleClients: [RouterClient] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return viewModel.filteredClients
            .filter { client in
                matchesSearch(client, query: query) &&
                    matchesStatusFilter(client) &&
                    matchesPolicyFilter(client) &&
                    matchesSegmentFilter(client)
            }
            .sorted(by: clientComparator)
    }

    private var availableSegments: [String] {
        viewModel.filteredClients
            .map { viewModel.displaySegmentSummary(for: $0) }
            .filter { $0 != localization.text("common.notAvailable") }
            .uniqued()
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var activeFilterCount: Int {
        var count = 0
        if viewModel.showOnlyMyDevices { count += 1 }
        if statusFilter != .all { count += 1 }
        if policyFilter != .all { count += 1 }
        if segmentFilter != nil { count += 1 }
        return count
    }

    private var searchSuggestions: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let pool = viewModel.filteredClients.flatMap { client in
            [
                client.name,
                client.ip,
                client.mac,
                viewModel.displayPolicyName(for: client),
                viewModel.displaySegmentSummary(for: client)
            ]
        }

        return pool
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.localizedCaseInsensitiveContains(query) }
            .uniqued()
            .prefix(6)
            .map { $0 }
    }

    /**
     * Chooses the client shown in the details sheet.
     *
     * Priority:
     * - selected client from the currently visible filtered list;
     * - otherwise the first client from the current visible list.
     */
    private var effectiveInspectorClient: RouterClient? {
        if let selectedClientID = viewModel.selectedClientID,
           let selectedVisibleClient = visibleClients.first(where: { $0.id == selectedClientID }) {
            return selectedVisibleClient
        }

        return visibleClients.first
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: Text(localization.text("search.clients.prompt"))
        )
        .frame(
            minWidth: LayoutMetrics.minimumWindowWidth,
            minHeight: LayoutMetrics.minimumWindowHeight
        )
        .searchSuggestions {
            ForEach(searchSuggestions, id: \.self) { suggestion in
                Text(suggestion)
                    .searchCompletion(suggestion)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    editorPayload = viewModel.makeNewEditorPayload()
                } label: {
                    Label(localization.text("action.add"), systemImage: "plus")
                }

                Button {
                    editorPayload = viewModel.makeEditorPayloadForSelected()
                } label: {
                    Label(localization.text("action.edit"), systemImage: "pencil")
                }
                .disabled(viewModel.selectedProfile == nil)

                Button(role: .destructive) {
                    isDeleteConfirmationShown = true
                } label: {
                    Label(localization.text("action.delete"), systemImage: "trash")
                }
                .disabled(viewModel.selectedProfile == nil)
            }

            ToolbarItemGroup {
                Button(localization.text("action.connect")) {
                    startConnectSelectedProfile()
                }
                .disabled(
                    viewModel.selectedProfile == nil ||
                    viewModel.isSelectedProfileConnected ||
                    viewModel.isBusy ||
                    isConnectActionPending
                )

                Button(localization.text("action.refresh")) {
                    Task {
                        await viewModel.refreshClients()
                    }
                }
                .disabled(!viewModel.isConnected || viewModel.isBusy)

                Button {
                    appUI.presentDiagnostics(for: viewModel.makeDiagnosticsPayloadForSelected())
                } label: {
                    Label(localization.text("action.diagnose"), systemImage: "stethoscope")
                }
                .disabled(viewModel.selectedProfile == nil)

                Button {
                    appUI.presentDashboard()
                } label: {
                    Label(localization.text("action.openDashboard"), systemImage: "rectangle.3.group.bubble.left")
                }

                Menu {
                    Section(localization.text("filters.visibility")) {
                        Toggle(localization.text("toggle.my"), isOn: $viewModel.showOnlyMyDevices)
                    }

                    Section(localization.text("filters.status")) {
                        Picker(localization.text("filters.status"), selection: $statusFilter) {
                            Text(localization.text("filters.status.all")).tag(ClientStatusFilter.all)
                            Text(localization.text("filters.status.online")).tag(ClientStatusFilter.online)
                            Text(localization.text("filters.status.offline")).tag(ClientStatusFilter.offline)
                            Text(localization.text("filters.status.blocked")).tag(ClientStatusFilter.blocked)
                        }
                    }

                    Section(localization.text("filters.policy")) {
                        Button(localization.text("filters.policy.all")) {
                            policyFilter = .all
                        }
                        Button(localization.text("policy.default")) {
                            policyFilter = .defaultPolicy
                        }
                        Button(localization.text("policy.blocked")) {
                            policyFilter = .blocked
                        }

                        if !viewModel.policies.isEmpty {
                            Divider()
                        }

                        ForEach(viewModel.policies) { policy in
                            Button(policy.displayName) {
                                policyFilter = .policy(policy.id)
                            }
                        }
                    }

                    Section(localization.text("filters.segment")) {
                        Button(localization.text("filters.segment.all")) {
                            segmentFilter = nil
                        }

                        ForEach(availableSegments, id: \.self) { segment in
                            Button(segment) {
                                segmentFilter = segment
                            }
                        }
                    }

                    Section(localization.text("filters.sort")) {
                        Picker(localization.text("filters.sort"), selection: $sortMode) {
                            Text(localization.text("filters.sort.smart")).tag(ClientSortMode.smart)
                            Text(localization.text("filters.sort.name")).tag(ClientSortMode.name)
                            Text(localization.text("filters.sort.ip")).tag(ClientSortMode.ip)
                            Text(localization.text("filters.sort.segment")).tag(ClientSortMode.segment)
                            Text(localization.text("filters.sort.policy")).tag(ClientSortMode.policy)
                        }
                    }

                    Divider()

                    Button(localization.text("filters.reset")) {
                        resetFilters()
                    }
                    .disabled(activeFilterCount == 0 && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } label: {
                    Label(
                        activeFilterCount > 0
                            ? localization.text("filters.title.count", args: [activeFilterCount])
                            : localization.text("filters.title"),
                        systemImage: activeFilterCount > 0
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label(
                        localization.text(
                            isInspectorPresented
                                ? "action.hideInspector"
                                : "action.showInspector"
                        ),
                        systemImage: "info.circle"
                    )
                }
                .help(
                    localization.text(
                        isInspectorPresented
                            ? "action.hideInspector"
                            : "action.showInspector"
                    )
                )
            }
        }
        .sheet(isPresented: $isInspectorPresented) {
            ClientInspectorView(client: effectiveInspectorClient)
                .environmentObject(localization)
                .environmentObject(viewModel)
                .frame(minWidth: LayoutMetrics.inspectorWidth, minHeight: 440)
        }
        .fileImporter(
            isPresented: $appUI.isImportingConfiguration,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $appUI.isExportingConfiguration,
            document: appUI.exportDocument,
            contentType: .json,
            defaultFilename: appUI.exportFilename
        ) { result in
            handleExport(result)
        }
        .sheet(item: $editorPayload) { payload in
            RouterEditorView(
                payload: payload,
                onCancel: {
                    editorPayload = nil
                },
                onSave: { savedPayload in
                    viewModel.saveProfile(savedPayload)
                    editorPayload = nil
                },
                onDiagnose: { draft in
                    try await viewModel.runDiagnostics(for: draft)
                }
            )
            .environmentObject(localization)
        }
        .sheet(item: $appUI.diagnosticsPayload) { payload in
            ConnectionDiagnosticsView(
                payload: payload,
                runDiagnostics: { draft in
                    try await viewModel.runDiagnostics(for: draft)
                }
            )
            .environmentObject(localization)
        }
        .sheet(isPresented: $appUI.isDashboardPresented) {
            DashboardView()
                .environmentObject(localization)
                .environmentObject(viewModel)
        }
        .confirmationDialog(
            localization.text("dialog.deleteRouter.title"),
            isPresented: $isDeleteConfirmationShown,
            titleVisibility: .visible
        ) {
            Button(localization.text("action.delete"), role: .destructive) {
                viewModel.deleteSelectedProfile()
            }
            Button(localization.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(localization.text("dialog.deleteRouter.message"))
        }
        .alert(localization.text("alert.error.title"), isPresented: $viewModel.isErrorPresented) {
            Button(localization.text("action.ok"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? localization.text("alert.unknown"))
        }
        .task {
            viewModel.loadData()
        }
        .onChange(of: localization.language) { _, _ in
            viewModel.relocalizeVisibleTexts()
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedProfileID) {
            ForEach(viewModel.profiles) { profile in
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .lineLimit(1)

                        Text(profile.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(profile.id)
                .contextMenu {
                    Button(localization.text("action.edit")) {
                        editorPayload = viewModel.makeEditorPayloadForSelected()
                    }

                    Button(localization.text("action.diagnose")) {
                        appUI.presentDiagnostics(for: viewModel.makeDiagnosticsPayloadForSelected())
                    }

                    Divider()

                    Button(localization.text("action.delete"), role: .destructive) {
                        isDeleteConfirmationShown = true
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(LayoutMetrics.sidebarWidth)
    }

    private var detail: some View {
        Group {
            if viewModel.selectedProfile == nil {
                ContentUnavailableView(
                    localization.text("empty.noRouterSelected.title"),
                    systemImage: "network",
                    description: Text(localization.text("empty.noRouterSelected.subtitle"))
                )
            } else if !viewModel.isConnected {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        localization.text("empty.notConnected.title"),
                        systemImage: "network",
                        description: Text(localization.text("empty.notConnected.subtitle"))
                    )

                    Button(localization.text("action.connect")) {
                        startConnectSelectedProfile()
                    }
                    .disabled(
                        viewModel.selectedProfile == nil ||
                        viewModel.isSelectedProfileConnected ||
                        viewModel.isBusy ||
                        isConnectActionPending
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    header

                    if visibleClients.isEmpty {
                        emptyResultsView
                    } else {
                        clientTable
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.connectedProfile?.name ?? localization.text("router.fallbackName"))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    Text(viewModel.connectedAddress ?? localization.text("common.notAvailable"))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer()

                if let lastRefreshDate = viewModel.lastRefreshDate {
                    Text(localization.text("dashboard.lastRefresh.inline", args: [DateFormatter.inlineRefresh.string(from: lastRefreshDate)]))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(viewModel.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if activeFilterCount > 0 || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(localization.text("filters.resultsCount", args: [visibleClients.count]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var clientTable: some View {
        Table(visibleClients, selection: $viewModel.selectedClientID) {
            TableColumn(localization.text("table.status")) { client in
                Circle()
                    .fill(client.isOnline ? Color.green : Color.secondary)
                    .frame(
                        width: LayoutMetrics.statusIndicatorSize,
                        height: LayoutMetrics.statusIndicatorSize
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .help(client.isOnline ? localization.text("client.online") : localization.text("client.offline"))
            }
            .width(LayoutMetrics.statusColumnWidth)

            TableColumn(localization.text("table.client")) { client in
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.name)
                        .lineLimit(1)

                    Text(client.mac)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .width(
                min: LayoutMetrics.clientColumnMinimumWidth,
                ideal: LayoutMetrics.clientColumnIdealWidth,
                max: nil
            )

            TableColumn(localization.text("table.ip")) { client in
                Text(client.ip)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            .width(LayoutMetrics.ipColumnWidth)

            TableColumn(localization.text("table.segment")) { client in
                Text(viewModel.displaySegmentSummary(for: client))
                    .lineLimit(1)
            }
            .width(
                min: LayoutMetrics.segmentColumnMinimumWidth,
                ideal: LayoutMetrics.segmentColumnIdealWidth,
                max: nil
            )

            TableColumn(localization.text("table.connection")) { client in
                Text(viewModel.displayConnectionSummary(for: client))
                    .lineLimit(1)
            }
            .width(LayoutMetrics.connectionColumnWidth)

            TableColumn(localization.text("table.policy")) { client in
                ClientPolicyMenu(client: client)
                    .environmentObject(localization)
                    .environmentObject(viewModel)
            }
            .width(LayoutMetrics.policyColumnWidth)
        }
    }

    private var emptyResultsView: some View {
        Group {
            if viewModel.clients.isEmpty {
                ContentUnavailableView(
                    localization.text("empty.noClients.title"),
                    systemImage: "desktopcomputer",
                    description: Text(localization.text("empty.noClients.subtitle"))
                )
            } else if viewModel.isMineFilterActiveWithoutMatches && activeFilterCount == 1 && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    localization.text("empty.noMineClients.title"),
                    systemImage: "laptopcomputer",
                    description: Text(localization.text("empty.noMineClients.subtitle"))
                )
            } else {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        localization.text("empty.noFilteredClients.title"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text(localization.text("empty.noFilteredClients.subtitle"))
                    )

                    Button(localization.text("filters.reset")) {
                        resetFilters()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func matchesSearch(_ client: RouterClient, query: String) -> Bool {
        guard !query.isEmpty else { return true }

        let values = [
            client.name,
            client.ip,
            client.mac,
            viewModel.displayPolicyName(for: client),
            viewModel.displaySegmentSummary(for: client),
            viewModel.displayConnectionSummary(for: client)
        ]

        return values.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func matchesStatusFilter(_ client: RouterClient) -> Bool {
        switch statusFilter {
        case .all:
            return true
        case .online:
            return client.isOnline
        case .offline:
            return !client.isOnline
        case .blocked:
            return client.access.lowercased() == "deny"
        }
    }

    private func matchesPolicyFilter(_ client: RouterClient) -> Bool {
        switch policyFilter {
        case .all:
            return true
        case .defaultPolicy:
            return client.access.lowercased() != "deny" && client.policy == nil
        case .blocked:
            return client.access.lowercased() == "deny"
        case let .policy(policyID):
            return client.policy == policyID && client.access.lowercased() != "deny"
        }
    }

    private func matchesSegmentFilter(_ client: RouterClient) -> Bool {
        guard let segmentFilter else { return true }
        return viewModel.displaySegmentSummary(for: client).caseInsensitiveCompare(segmentFilter) == .orderedSame
    }

    private func clientComparator(_ lhs: RouterClient, _ rhs: RouterClient) -> Bool {
        switch sortMode {
        case .smart:
            if lhs.isOnline != rhs.isOnline {
                return lhs.isOnline && !rhs.isOnline
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .name:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .ip:
            return lhs.ip.localizedCaseInsensitiveCompare(rhs.ip) == .orderedAscending
        case .segment:
            return viewModel.displaySegmentSummary(for: lhs)
                .localizedCaseInsensitiveCompare(viewModel.displaySegmentSummary(for: rhs)) == .orderedAscending
        case .policy:
            return viewModel.displayPolicyName(for: lhs)
                .localizedCaseInsensitiveCompare(viewModel.displayPolicyName(for: rhs)) == .orderedAscending
        }
    }

    private func resetFilters() {
        searchText = ""
        statusFilter = .all
        sortMode = .smart
        policyFilter = .all
        segmentFilter = nil
        viewModel.showOnlyMyDevices = false
    }

    /**
     * Blocks duplicate connect taps within the current render pass so every
     * visible "Connect" trigger becomes disabled immediately.
     */
    private func startConnectSelectedProfile() {
        guard !isConnectActionPending, !viewModel.isBusy else { return }

        isConnectActionPending = true
        Task {
            defer { isConnectActionPending = false }
            await viewModel.connectSelectedProfile()
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if didAccessSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try viewModel.importConfiguration(from: url)
            } catch {
                viewModel.present(error: error)
            }
        case let .failure(error):
            if (error as NSError).code != NSUserCancelledError {
                viewModel.present(error: error)
            }
        }
    }

    private func handleExport(_ result: Result<URL, Error>) {
        appUI.finishConfigurationExport()

        switch result {
        case .success:
            viewModel.noteConfigurationExportCompleted()
        case let .failure(error):
            if (error as NSError).code != NSUserCancelledError {
                viewModel.present(error: error)
            }
        }
    }
}

private struct ClientPolicyMenu: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var viewModel: MainViewModel

    let client: RouterClient
    var title: String?

    var body: some View {
        Menu {
            Button(localization.text("policy.default")) {
                Task {
                    await viewModel.applyPolicy(nil, to: client)
                }
            }

            Button(localization.text("policy.blocked")) {
                Task {
                    await viewModel.setClientBlocked(client)
                }
            }

            if !viewModel.policies.isEmpty {
                Divider()
            }

            ForEach(viewModel.policies) { policy in
                Button(policy.displayName) {
                    Task {
                        await viewModel.applyPolicy(policy.id, to: client)
                    }
                }
            }
        } label: {
            Text(title ?? viewModel.displayPolicyName(for: client))
                .lineLimit(1)
        }
    }
}

private struct ClientInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var viewModel: MainViewModel

    let client: RouterClient?

    var body: some View {
        Group {
            if let client {
                Form {
                    Section(localization.text("inspector.overview")) {
                        LabeledContent(localization.text("inspector.name")) {
                            Text(client.name)
                        }

                        LabeledContent(localization.text("inspector.status")) {
                            Label(
                                client.isOnline ? localization.text("client.online") : localization.text("client.offline"),
                                systemImage: client.isOnline ? "dot.radiowaves.left.and.right" : "slash.circle"
                            )
                            .foregroundStyle(client.isOnline ? Color.green : Color.secondary)
                        }

                        LabeledContent(localization.text("inspector.ip")) {
                            Text(client.ip)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }

                        LabeledContent(localization.text("inspector.mac")) {
                            Text(client.mac)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }

                    Section(localization.text("inspector.network")) {
                        LabeledContent(localization.text("inspector.segment")) {
                            Text(viewModel.displaySegmentSummary(for: client))
                        }

                        LabeledContent(localization.text("inspector.connection")) {
                            Text(viewModel.displayConnectionSummary(for: client))
                        }

                        if let trafficPriority = client.trafficPriority, !trafficPriority.isEmpty {
                            LabeledContent(localization.text("inspector.priority")) {
                                Text(trafficPriority)
                            }
                        }
                    }

                    Section(localization.text("inspector.access")) {
                        LabeledContent(localization.text("inspector.policy")) {
                            Text(viewModel.displayPolicyName(for: client))
                        }

                        HStack {
                            ClientPolicyMenu(
                                client: client,
                                title: localization.text("action.changePolicy")
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button(localization.text("action.block")) {
                                Task {
                                    await viewModel.setClientBlocked(client)
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView(
                    localization.text("inspector.emptyTitle"),
                    systemImage: "info.circle",
                    description: Text(localization.text("inspector.emptySubtitle"))
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button(localization.text("action.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 320, idealWidth: 360, minHeight: 440, idealHeight: 540, alignment: .topLeading)
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in self {
            let key = value.lowercased()
            if seen.insert(key).inserted {
                result.append(value)
            }
        }

        return result
    }
}

private extension DateFormatter {
    static let inlineRefresh: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    ContentView()
        .environmentObject(LocalizationManager.shared)
        .environmentObject(MainViewModel())
        .environmentObject(AppUIState())
}
