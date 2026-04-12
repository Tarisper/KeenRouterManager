import Foundation

/**
 * Connection profile for a Keenetic router.
 */
struct RouterProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var address: String
    var username: String

    /**
     * Creates a router profile.
     * - Parameters:
     *   - id: Unique profile identifier.
     *   - name: Display name shown in the UI.
     *   - address: Router base address (IP, local DNS, or KeenDNS).
     *   - username: Router admin login.
     */
    init(id: UUID = UUID(), name: String, address: String, username: String) {
        self.id = id
        self.name = name
        self.address = address
        self.username = username
    }
}

/**
 * Credentials used to authenticate on the router.
 */
struct RouterCredentials: Codable, Hashable {
    var password: String
}

/**
 * Router client device entry.
 */
struct RouterClient: Identifiable, Hashable {
    let id: String
    var name: String
    var ip: String
    var mac: String
    var policy: String?
    var access: String
    var isOnline: Bool
    var segmentTitle: String?
    var segmentSubtitle: String?
    var connectionTitle: String?
    var connectionSubtitle: String?
    var trafficPriority: String?

    /**
     * Creates a router client model.
     * - Parameters:
     *   - name: Device name.
     *   - ip: Device IPv4 address.
     *   - mac: Device MAC address.
     *   - policy: Access policy identifier.
     *   - access: Access mode (for example `permit`/`deny`).
     *   - isOnline: Online status flag.
     *   - segmentTitle: Primary segment label.
     *   - segmentSubtitle: Additional segment label.
     *   - connectionTitle: Primary connection string.
     *   - connectionSubtitle: Additional connection string.
     *   - trafficPriority: Traffic priority value.
     */
    init(
        name: String,
        ip: String,
        mac: String,
        policy: String?,
        access: String,
        isOnline: Bool = false,
        segmentTitle: String? = nil,
        segmentSubtitle: String? = nil,
        connectionTitle: String? = nil,
        connectionSubtitle: String? = nil,
        trafficPriority: String? = nil
    ) {
        self.id = mac.lowercased()
        self.name = name
        self.ip = ip
        self.mac = mac.lowercased()
        self.policy = policy
        self.access = access
        self.isOnline = isOnline
        self.segmentTitle = segmentTitle
        self.segmentSubtitle = segmentSubtitle
        self.connectionTitle = connectionTitle
        self.connectionSubtitle = connectionSubtitle
        self.trafficPriority = trafficPriority
    }
}

/**
 * Access policy available for client assignment.
 */
struct RouterPolicy: Identifiable, Hashable {
    let id: String
    let displayName: String
}

/**
 * Form payload for creating or editing a router profile.
 */
struct RouterEditorPayload: Identifiable {
    let id = UUID()
    let profileID: UUID?
    var name: String
    var address: String
    var username: String
    var password: String

    /**
     * Indicates whether the payload is for a new profile.
     */
    var isNew: Bool {
        profileID == nil
    }
}
