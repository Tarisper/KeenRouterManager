import Combine
import Foundation

/**
 * Main application model shared across the main window and modal overview flows.
 *
 * Responsibilities:
 * - router profile management;
 * - connecting and loading clients/policies;
 * - client policy changes;
 * - app settings persistence;
 * - network overview summaries;
 * - diagnostics and configuration import/export.
 */
@MainActor
final class MainViewModel: ObservableObject {
    /**
     * Compact label/count pair used by dashboard breakdown sections.
     */
    struct BreakdownItem: Identifiable, Hashable {
        var id: String { title }
        let title: String
        let count: Int
    }

    private enum StatusState {
        case selectRouterAndConnect
        case savedRouters(count: Int)
        case profileUpdatedReconnect
        case profileSaved
        case profileDeleted
        case connecting(routerName: String)
        case connected(address: String)
        case connectFailed
        case refreshed(at: Date)
        case clientProfileUpdated(name: String)
        case clientBlocked(name: String)
        case configurationImported(count: Int)
        case configurationExported
    }

    @Published private(set) var profiles: [RouterProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var selectedClientID: String?
    @Published var showOnlyMyDevices = false {
        didSet {
            guard showOnlyMyDevices != oldValue else { return }
            if showOnlyMyDevices {
                localMACAddresses = localMACAddressProvider.loadMACAddresses()
            }
            if !isRestoringSettings {
                persistSettings()
            }
        }
    }
    @Published var isRouterListVisible = true {
        didSet {
            guard isRouterListVisible != oldValue else { return }
            if !isRestoringSettings {
                persistSettings()
            }
        }
    }
    @Published private(set) var clients: [RouterClient] = []
    @Published private(set) var policies: [RouterPolicy] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedAddress: String?
    @Published private(set) var statusMessage = ""
    @Published private(set) var lastRefreshDate: Date?
    @Published var errorMessage: String?
    @Published var isErrorPresented = false

    private let localization: LocalizationManager
    private let profileStore = RouterProfileStore()
    private let credentialsStore: CredentialsStore = KeychainCredentialsStore()
    private let settingsStore = FileAppSettingsStore()
    private let localMACAddressProvider = LocalMACAddressProvider()

    private var apiClient: KeeneticAPIClient?
    private var connectedProfileID: UUID?
    private var localMACAddresses: Set<String> = []
    private var isRestoringSettings = false
    private var hasLoadedInitialData = false
    private var statusState: StatusState = .selectRouterAndConnect

    /**
     * Creates the shared main model.
     * - Parameter localization: Localization service for all user-facing text.
     */
    init(localization: LocalizationManager? = nil) {
        self.localization = localization ?? LocalizationManager.shared
        setStatus(.selectRouterAndConnect)
    }

    /**
     * Rebuilds the current status string after a language change.
     */
    func relocalizeVisibleTexts() {
        statusMessage = localizedStatus(for: statusState)
    }

    /**
     * Currently selected router profile.
     */
    var selectedProfile: RouterProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first(where: { $0.id == selectedProfileID })
    }

    /**
     * Router profile that owns the active connection, if any.
     */
    var connectedProfile: RouterProfile? {
        guard let connectedProfileID else { return nil }
        return profiles.first(where: { $0.id == connectedProfileID })
    }

    /**
     * Indicates whether the current selection already owns the active connection.
     */
    var isSelectedProfileConnected: Bool {
        isConnected && selectedProfileID == connectedProfileID
    }

    /**
     * Currently selected client in the table.
     */
    var selectedClient: RouterClient? {
        guard let selectedClientID else { return nil }
        return clients.first(where: { $0.id == selectedClientID })
    }

    /**
     * Client list with the persistent "My Devices" filter applied.
     */
    var filteredClients: [RouterClient] {
        guard showOnlyMyDevices else { return clients }
        return clients.filter { localMACAddresses.contains($0.mac.lowercased()) }
    }

    /**
     * Indicates that the "My Devices" filter is active without matches.
     */
    var isMineFilterActiveWithoutMatches: Bool {
        showOnlyMyDevices && !clients.isEmpty && filteredClients.isEmpty
    }

    /**
     * Human-readable timestamp for the dashboard.
     */
    var lastRefreshDescription: String {
        guard let lastRefreshDate else {
            return localization.text("common.notAvailable")
        }
        return DateFormatter.dashboardTimestamp.string(from: lastRefreshDate)
    }

    /**
     * Number of online clients in the active router snapshot.
     */
    var onlineClientCount: Int {
        clients.filter(\.isOnline).count
    }

    /**
     * Number of blocked clients in the active router snapshot.
     */
    var blockedClientCount: Int {
        clients.filter { $0.access.lowercased() == "deny" }.count
    }

    /**
     * Number of current router clients that match this Mac's local interfaces.
     */
    var myClientCount: Int {
        clients.filter { localMACAddresses.contains($0.mac.lowercased()) }.count
    }

    /**
     * Policy breakdown for the network overview sheet.
     */
    var policyBreakdown: [BreakdownItem] {
        makeBreakdown(from: clients.map { displayPolicyName(for: $0) })
    }

    /**
     * Segment breakdown for the network overview sheet.
     */
    var segmentBreakdown: [BreakdownItem] {
        makeBreakdown(from: clients.map { displaySegmentSummary(for: $0) })
    }

    /**
     * Loads profiles and persisted app settings once per app launch.
     */
    func loadData() {
        guard !hasLoadedInitialData else { return }

        do {
            profiles = try loadSortedProfiles()
            localMACAddresses = localMACAddressProvider.loadMACAddresses()
            apply(settings: try settingsStore.load())

            if selectedProfileID == nil {
                selectedProfileID = profiles.first?.id
            }

            hasLoadedInitialData = true
            setStatus(.savedRouters(count: profiles.count))
        } catch {
            present(error: error)
        }
    }

    /**
     * Builds an empty payload for creating a new router profile.
     */
    func makeNewEditorPayload() -> RouterEditorPayload {
        RouterEditorPayload(profileID: nil, name: "", address: "", username: "admin", password: "")
    }

    /**
     * Builds an editor payload for the selected router profile.
     * - Returns: Current router data and password, or `nil` if unavailable.
     */
    func makeEditorPayloadForSelected() -> RouterEditorPayload? {
        guard let profile = selectedProfile else {
            return nil
        }

        let password: String
        do {
            password = try credentialsStore.load(routerID: profile.id)?.password ?? ""
        } catch {
            present(error: error)
            return nil
        }

        return RouterEditorPayload(
            profileID: profile.id,
            name: profile.name,
            address: profile.address,
            username: profile.username,
            password: password
        )
    }

    /**
     * Builds a payload for router diagnostics using the selected saved profile.
     */
    func makeDiagnosticsPayloadForSelected() -> RouterEditorPayload? {
        makeEditorPayloadForSelected()
    }

    /**
     * Creates or updates a router profile and stores credentials in Keychain.
     * - Parameter payload: Form values from the router editor.
     */
    func saveProfile(_ payload: RouterEditorPayload) {
        let trimmedName = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = payload.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = payload.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedPassword = payload.password.trimmingCharacters(in: .newlines)

        guard !trimmedName.isEmpty, !trimmedAddress.isEmpty, !trimmedUsername.isEmpty, !sanitizedPassword.isEmpty else {
            present(errorMessage: localization.text("error.fillAllFields"))
            return
        }

        do {
            let normalizedAddress = try KeeneticAPIClient.normalizedBaseAddress(from: trimmedAddress)
            let profileID = payload.profileID ?? UUID()
            let profile = RouterProfile(
                id: profileID,
                name: trimmedName,
                address: normalizedAddress,
                username: trimmedUsername
            )

            if let index = profiles.firstIndex(where: { $0.id == profileID }) {
                profiles[index] = profile
            } else {
                profiles.append(profile)
            }

            profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selectedProfileID = profileID

            try profileStore.saveProfiles(profiles)
            try credentialsStore.save(RouterCredentials(password: sanitizedPassword), for: profileID)

            if connectedProfileID == profileID {
                disconnect(withStatus: .profileUpdatedReconnect)
            } else {
                setStatus(.profileSaved)
            }
        } catch {
            present(error: error)
        }
    }

    /**
     * Deletes the selected router profile and its stored password.
     */
    func deleteSelectedProfile() {
        guard let selectedProfile else { return }

        do {
            profiles.removeAll { $0.id == selectedProfile.id }
            try profileStore.saveProfiles(profiles)
            try credentialsStore.delete(routerID: selectedProfile.id)

            if connectedProfileID == selectedProfile.id {
                disconnect(withStatus: .profileDeleted)
            } else {
                setStatus(.profileDeleted)
            }

            selectedProfileID = profiles.first?.id
        } catch {
            present(error: error)
        }
    }

    /**
     * Connects to the selected router and loads current clients and policies.
     */
    func connectSelectedProfile() async {
        guard let profile = selectedProfile else {
            present(errorMessage: localization.text("error.selectRouterFirst"))
            return
        }

        do {
            guard let credentials = try credentialsStore.load(routerID: profile.id) else {
                present(errorMessage: localization.text("error.passwordNotFound"))
                return
            }

            isBusy = true
            setStatus(.connecting(routerName: profile.name))

            let client = try KeeneticAPIClient(
                address: profile.address,
                username: profile.username,
                password: credentials.password.trimmingCharacters(in: .newlines)
            )

            localMACAddresses = localMACAddressProvider.loadMACAddresses()
            try await client.authenticate()
            let fetchedPolicies = try await client.fetchPolicies()
            let fetchedClients = try await client.fetchClients()
            let refreshedAt = Date()

            apiClient = client
            connectedProfileID = profile.id
            isConnected = true
            connectedAddress = client.connectionAddress
            policies = fetchedPolicies
            setClients(fetchedClients)
            lastRefreshDate = refreshedAt
            setStatus(.connected(address: client.connectionAddress))
        } catch {
            present(error: error)
            disconnect(withStatus: .connectFailed)
        }

        isBusy = false
    }

    /**
     * Refreshes the client and policy snapshot for the active router connection.
     */
    func refreshClients() async {
        guard let apiClient else {
            present(errorMessage: localization.text("error.connectFirst"))
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            localMACAddresses = localMACAddressProvider.loadMACAddresses()
            policies = try await apiClient.fetchPolicies()
            setClients(try await apiClient.fetchClients())
            let refreshedAt = Date()
            lastRefreshDate = refreshedAt
            setStatus(.refreshed(at: refreshedAt))
        } catch {
            present(error: error)
        }
    }

    /**
     * Applies an access policy to a router client.
     * - Parameters:
     *   - policyID: Policy identifier, or `nil` for the router default.
     *   - client: Target router client.
     */
    func applyPolicy(_ policyID: String?, to client: RouterClient) async {
        guard let apiClient else {
            present(errorMessage: localization.text("error.connectFirst"))
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await apiClient.applyPolicy(mac: client.mac, policy: policyID)
            if let index = clients.firstIndex(where: { $0.id == client.id }) {
                clients[index].policy = policyID
                clients[index].access = "permit"
            }
            setStatus(.clientProfileUpdated(name: client.name))
        } catch {
            present(error: error)
        }
    }

    /**
     * Blocks internet access for a router client.
     * - Parameter client: Target router client.
     */
    func setClientBlocked(_ client: RouterClient) async {
        guard let apiClient else {
            present(errorMessage: localization.text("error.connectFirst"))
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await apiClient.setClientBlocked(mac: client.mac)
            if let index = clients.firstIndex(where: { $0.id == client.id }) {
                clients[index].access = "deny"
                clients[index].policy = nil
            }
            setStatus(.clientBlocked(name: client.name))
        } catch {
            present(error: error)
        }
    }

    /**
     * Runs a connection diagnostic without mutating the active router session.
     * - Parameter payload: Router address and credentials to validate.
     * - Returns: Diagnostic report with endpoint attempts and guidance.
     * - Throws: Validation or address parsing error before network work starts.
     */
    func runDiagnostics(for payload: RouterEditorPayload) async throws -> ConnectionDiagnosticReport {
        let trimmedAddress = payload.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = payload.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedPassword = payload.password.trimmingCharacters(in: .newlines)

        guard !trimmedAddress.isEmpty, !trimmedUsername.isEmpty, !sanitizedPassword.isEmpty else {
            throw LocalizedMessageError(message: localization.text("error.diagnostics.fillRequiredFields"))
        }

        let client = try KeeneticAPIClient(
            address: trimmedAddress,
            username: trimmedUsername,
            password: sanitizedPassword
        )
        return await client.diagnoseConnection()
    }

    /**
     * Prepares the current app configuration for export.
     * - Returns: File document ready for `fileExporter`.
     * - Throws: File system read error.
     */
    func makeConfigurationDocument() throws -> RouterConfigurationDocument {
        RouterConfigurationDocument(
            archive: RouterConfigurationArchive(
                appSettings: currentSettingsSnapshot(),
                profiles: profiles
            )
        )
    }

    /**
     * Suggested export filename for the configuration document.
     */
    var defaultConfigurationExportFilename: String {
        "KeenRouterManager-Configuration-\(DateFormatter.exportFilename.string(from: Date()))"
    }

    /**
     * Imports router profiles and app settings from a configuration file URL.
     * - Parameter url: Picked file URL.
     * - Throws: Decode, validation, or persistence error.
     */
    func importConfiguration(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let archive = try RouterConfigurationDocument.decodeArchive(from: data)
        try applyImportedConfiguration(archive)
    }

    /**
     * Marks configuration export as completed in the status area.
     */
    func noteConfigurationExportCompleted() {
        setStatus(.configurationExported)
    }

    /**
     * Presents a user-facing error.
     * - Parameter error: Error to expose through the shared alert.
     */
    func present(error: Error) {
        present(errorMessage: error.localizedDescription)
    }

    /**
     * Presents a user-facing error message.
     * - Parameter errorMessage: Message shown in the shared alert.
     */
    func present(errorMessage: String) {
        self.errorMessage = errorMessage
        isErrorPresented = true
    }

    /**
     * User-facing policy label for a client.
     * - Parameter client: Router client.
     * - Returns: Current policy label or fallback description.
     */
    func displayPolicyName(for client: RouterClient) -> String {
        if client.access.lowercased() == "deny" {
            return localization.text("policy.blocked")
        }
        guard let policyID = client.policy else {
            return localization.text("policy.default")
        }
        if let mapped = policies.first(where: { $0.id == policyID }) {
            return mapped.displayName
        }
        return policyID
    }

    /**
     * Readable segment summary for a client.
     * - Parameter client: Router client.
     * - Returns: Cleaned segment string.
     */
    func displaySegmentSummary(for client: RouterClient) -> String {
        let title = cleanedSegmentValue(client.segmentTitle)
        let subtitle = cleanedSegmentValue(client.segmentSubtitle)

        if let title, let subtitle {
            if title.caseInsensitiveCompare(subtitle) == .orderedSame {
                return title
            }
            return "\(title) \(subtitle)"
        }

        if let title {
            return title
        }

        if let subtitle {
            return subtitle
        }

        return localization.text("common.notAvailable")
    }

    /**
     * Readable connection summary for a client.
     * - Parameter client: Router client.
     * - Returns: Primary and secondary connection information.
     */
    func displayConnectionSummary(for client: RouterClient) -> String {
        let title = nonEmpty(client.connectionTitle) ?? localization.text("common.notAvailable")
        if let subtitle = nonEmpty(client.connectionSubtitle) {
            return "\(title) · \(subtitle)"
        }
        return title
    }

    private func applyImportedConfiguration(_ archive: RouterConfigurationArchive) throws {
        profiles = mergeProfiles(existing: profiles, imported: archive.profiles)
        try profileStore.saveProfiles(profiles)

        localMACAddresses = localMACAddressProvider.loadMACAddresses()
        let importedSettings = archive.appSettings
        try settingsStore.save(importedSettings)
        apply(settings: importedSettings)

        if let importedLanguage = AppLanguage.resolve(code: importedSettings.interfaceLanguageCode) {
            localization.language = importedLanguage
        }

        if isConnected {
            disconnect(withStatus: .configurationImported(count: archive.profiles.count))
        } else {
            setStatus(.configurationImported(count: archive.profiles.count))
        }

        if selectedProfileID == nil || !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }

        hasLoadedInitialData = true
    }

    private func mergeProfiles(existing: [RouterProfile], imported: [RouterProfile]) -> [RouterProfile] {
        var merged = existing

        for incoming in imported {
            if let index = merged.firstIndex(where: { $0.id == incoming.id || isSameRouterDefinition($0, incoming) }) {
                let preservedID = merged[index].id
                merged[index] = RouterProfile(
                    id: preservedID,
                    name: incoming.name,
                    address: incoming.address,
                    username: incoming.username
                )
            } else {
                merged.append(incoming)
            }
        }

        return merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func isSameRouterDefinition(_ lhs: RouterProfile, _ rhs: RouterProfile) -> Bool {
        lhs.address.caseInsensitiveCompare(rhs.address) == .orderedSame &&
            lhs.username.caseInsensitiveCompare(rhs.username) == .orderedSame
    }

    private func loadSortedProfiles() throws -> [RouterProfile] {
        try profileStore.loadProfiles().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func currentSettingsSnapshot() -> AppSettings {
        AppSettings(
            showOnlyMyDevices: showOnlyMyDevices,
            isRouterListVisible: isRouterListVisible,
            interfaceLanguageCode: localization.language.rawValue
        )
    }

    private func apply(settings: AppSettings) {
        isRestoringSettings = true
        defer { isRestoringSettings = false }

        showOnlyMyDevices = settings.showOnlyMyDevices
        isRouterListVisible = settings.isRouterListVisible
    }

    private func disconnect(withStatus status: StatusState) {
        apiClient = nil
        connectedProfileID = nil
        isConnected = false
        connectedAddress = nil
        lastRefreshDate = nil
        clients = []
        policies = []
        selectedClientID = nil
        setStatus(status)
    }

    private func setClients(_ newClients: [RouterClient]) {
        clients = newClients

        if let selectedClientID, newClients.contains(where: { $0.id == selectedClientID }) {
            return
        }
        selectedClientID = newClients.first?.id
    }

    private func setStatus(_ state: StatusState) {
        statusState = state
        statusMessage = localizedStatus(for: state)
    }

    private func localizedStatus(for state: StatusState) -> String {
        switch state {
        case .selectRouterAndConnect:
            return localization.text("status.selectRouterAndConnect")
        case let .savedRouters(count):
            return localization.text("status.savedRouters", args: [count])
        case .profileUpdatedReconnect:
            return localization.text("status.profileUpdatedReconnect")
        case .profileSaved:
            return localization.text("status.profileSaved")
        case .profileDeleted:
            return localization.text("status.profileDeleted")
        case let .connecting(routerName):
            return localization.text("status.connecting", args: [routerName])
        case let .connected(address):
            return localization.text("status.connected", args: [address])
        case .connectFailed:
            return localization.text("status.connectFailed")
        case let .refreshed(at):
            return localization.text("status.refreshed", args: [DateFormatter.shortTime.string(from: at)])
        case let .clientProfileUpdated(name):
            return localization.text("status.clientProfileUpdated", args: [name])
        case let .clientBlocked(name):
            return localization.text("status.clientBlocked", args: [name])
        case let .configurationImported(count):
            return localization.text("status.configurationImported", args: [count])
        case .configurationExported:
            return localization.text("status.configurationExported")
        }
    }

    private func persistSettings() {
        do {
            try settingsStore.update { settings in
                settings.showOnlyMyDevices = showOnlyMyDevices
                settings.isRouterListVisible = isRouterListVisible
            }
        } catch {
            present(error: error)
        }
    }

    private func makeBreakdown(from titles: [String]) -> [BreakdownItem] {
        let counts = titles.reduce(into: [String: Int]()) { partialResult, title in
            partialResult[title, default: 0] += 1
        }

        return counts
            .map { BreakdownItem(title: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func cleanedSegmentValue(_ value: String?) -> String? {
        guard let raw = nonEmpty(value) else {
            return nil
        }

        let cleaned = raw
            .replacingOccurrences(of: "·", with: " ")
            .replacingOccurrences(of: "•", with: " ")
            .replacingOccurrences(of: "—", with: " ")
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "-.,:;")
                )
            )
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }
}

private struct LocalizedMessageError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let dashboardTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let exportFilename: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
