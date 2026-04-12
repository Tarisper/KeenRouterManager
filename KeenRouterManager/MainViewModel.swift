import Combine
import Foundation

/**
 * Main view model of the application.
 *
 * Responsibilities:
 * - router profile management;
 * - connecting and loading clients/policies;
 * - applying policies to clients;
 * - persisting and restoring UI settings.
 */
@MainActor
final class MainViewModel: ObservableObject {
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
    }

    @Published private(set) var profiles: [RouterProfile] = []
    @Published var selectedProfileID: UUID?
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
    private var statusState: StatusState = .selectRouterAndConnect

    /**
     * Creates the main view model using the shared localization manager.
     */
    init() {
        self.localization = .shared
        setStatus(.selectRouterAndConnect)
    }

    /**
     * Creates the main view model.
     * - Parameter localization: Localization manager for user-facing text.
     */
    init(localization: LocalizationManager) {
        self.localization = localization
        setStatus(.selectRouterAndConnect)
    }

    /**
     * Rebuilds currently visible localized texts after language change.
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
     * Client list with the "My devices" filter applied.
     */
    var filteredClients: [RouterClient] {
        guard showOnlyMyDevices else { return clients }
        return clients.filter { localMACAddresses.contains($0.mac.lowercased()) }
    }

    /**
     * Indicates that the "My devices" filter is active without matches.
     */
    var isMineFilterActiveWithoutMatches: Bool {
        showOnlyMyDevices && !clients.isEmpty && filteredClients.isEmpty
    }

    /**
     * Returns the display name of a client's access policy.
     * - Parameter client: Router client.
     * - Returns: User-facing policy label for UI.
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
     * Returns a readable segment summary for a client.
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
     * Returns a readable connection summary for a client.
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

    /**
     * Loads profiles and application settings at startup.
     */
    func loadData() {
        do {
            profiles = try profileStore.loadProfiles()
            localMACAddresses = localMACAddressProvider.loadMACAddresses()
            let settings = try settingsStore.load()
            isRestoringSettings = true
            defer { isRestoringSettings = false }
            showOnlyMyDevices = settings.showOnlyMyDevices
            isRouterListVisible = settings.isRouterListVisible

            if selectedProfileID == nil {
                selectedProfileID = profiles.first?.id
            }
            setStatus(.savedRouters(count: profiles.count))
        } catch {
            present(error: error)
        }
    }

    /**
     * Builds an empty payload for creating a new profile.
     * - Returns: Payload with default values.
     */
    func makeNewEditorPayload() -> RouterEditorPayload {
        RouterEditorPayload(profileID: nil, name: "", address: "", username: "admin", password: "")
    }

    /**
     * Builds an editor payload for the selected profile.
     * - Returns: Payload with current values, or `nil` if no profile is selected.
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
     * Creates or updates a router profile and stores credentials.
     * - Parameter payload: Profile editor form values.
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
     * Deletes the selected profile and its stored credentials.
     */
    func deleteSelectedProfile() {
        guard let selectedProfile else { return }

        do {
            profiles.removeAll { $0.id == selectedProfile.id }
            try profileStore.saveProfiles(profiles)
            try credentialsStore.delete(routerID: selectedProfile.id)

            if connectedProfileID == selectedProfile.id {
                disconnect(withStatus: .profileDeleted)
            }

            selectedProfileID = profiles.first?.id
            setStatus(.profileDeleted)
        } catch {
            present(error: error)
        }
    }

    /**
     * Connects to the selected router and loads clients/policies.
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

            self.apiClient = client
            self.connectedProfileID = profile.id
            self.isConnected = true
            self.connectedAddress = client.connectionAddress
            self.policies = fetchedPolicies
            self.clients = fetchedClients
            self.setStatus(.connected(address: client.connectionAddress))
        } catch {
            present(error: error)
            disconnect(withStatus: .connectFailed)
        }

        isBusy = false
    }

    /**
     * Refreshes clients and policies for an existing connection.
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
            clients = try await apiClient.fetchClients()
            setStatus(.refreshed(at: Date()))
        } catch {
            present(error: error)
        }
    }

    /**
     * Applies an access policy to a client.
     * - Parameters:
     *   - policyID: Policy identifier, or `nil` for the default policy.
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
            }
            setStatus(.clientProfileUpdated(name: client.name))
        } catch {
            present(error: error)
        }
    }

    /**
     * Blocks internet access for a client.
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

    private func disconnect(withStatus status: StatusState) {
        apiClient = nil
        connectedProfileID = nil
        isConnected = false
        connectedAddress = nil
        clients = []
        policies = []
        setStatus(status)
    }

    private func present(error: Error) {
        present(errorMessage: error.localizedDescription)
    }

    private func present(errorMessage: String) {
        self.errorMessage = errorMessage
        isErrorPresented = true
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

private extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
