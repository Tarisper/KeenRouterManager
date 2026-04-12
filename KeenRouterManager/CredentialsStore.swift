import Foundation
import Security

/**
 * Credential storage errors.
 */
enum CredentialsStoreError: LocalizedError {
    case invalidData
    case invalidPasswordData
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return LocalizationManager.shared.text("error.credentials.invalidData")
        case .invalidPasswordData:
            return LocalizationManager.shared.text("error.credentials.invalidPasswordData")
        case let .keychainError(status):
            return LocalizationManager.shared.text("error.credentials.keychain", args: [status])
        }
    }
}

/**
 * Contract for router credential storage.
 */
protocol CredentialsStore {
    /**
     * Loads credentials for the specified router profile.
     * - Parameter routerID: Router profile identifier.
     * - Returns: Stored credentials or `nil` if missing.
     * - Throws: Read/decode error.
     */
    func load(routerID: UUID) throws -> RouterCredentials?

    /**
     * Saves credentials for the specified router profile.
     * - Parameters:
     *   - credentials: Credentials to persist.
     *   - routerID: Router profile identifier.
     * - Throws: Write error.
     */
    func save(_ credentials: RouterCredentials, for routerID: UUID) throws

    /**
     * Deletes credentials for a router profile.
     * - Parameter routerID: Router profile identifier.
     * - Throws: Write error.
     */
    func delete(routerID: UUID) throws
}

/**
 * Legacy file-based credential storage in `Application Support/KeenRouterManager/credentials.json`.
 *
 * The app keeps this store only for migration from the old plain-text format
 * to the system Keychain.
 */
final class FileCredentialsStore: CredentialsStore {
    private enum Storage {
        static let credentialsFileName = "credentials.json"
    }

    private struct FilePayload: Codable {
        var values: [String: RouterCredentials]
    }

    private let fileURL: URL

    /**
     * Creates a legacy file-based credential store.
     * - Parameter fileManager: `FileManager` instance used for file operations.
     */
    init(fileManager: FileManager = .default) {
        let directory = AppStorageLocation.directoryURL(fileManager: fileManager)
        self.fileURL = directory.appendingPathComponent(Storage.credentialsFileName)
    }

    /**
     * Loads credentials for a router profile.
     * - Parameter routerID: Router profile identifier.
     * - Returns: `RouterCredentials` or `nil` when absent.
     * - Throws: Read/decode error.
     */
    func load(routerID: UUID) throws -> RouterCredentials? {
        let payload = try loadPayload()
        return payload.values[routerID.uuidString]
    }

    /**
     * Saves credentials for a router profile.
     * - Parameters:
     *   - credentials: Credentials to persist.
     *   - routerID: Router profile identifier.
     * - Throws: Write/encode error.
     */
    func save(_ credentials: RouterCredentials, for routerID: UUID) throws {
        var payload = try loadPayload()
        payload.values[routerID.uuidString] = credentials
        try persist(payload: payload)
    }

    /**
     * Deletes credentials for a router profile.
     * - Parameter routerID: Router profile identifier.
     * - Throws: Read/write error.
     */
    func delete(routerID: UUID) throws {
        var payload = try loadPayload()
        payload.values.removeValue(forKey: routerID.uuidString)
        try persist(payload: payload)
    }

    private func loadPayload() throws -> FilePayload {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return FilePayload(values: [:])
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return FilePayload(values: [:])
        }

        do {
            return try JSONDecoder().decode(FilePayload.self, from: data)
        } catch {
            throw CredentialsStoreError.invalidData
        }
    }

    private func persist(payload: FilePayload) throws {
        let data = try JSONEncoder.pretty.encode(payload)
        try data.write(to: fileURL, options: .atomic)
    }
}

/**
 * Keychain-based credential storage for router passwords.
 *
 * Passwords are stored as generic passwords, using router profile UUID as the
 * account key. When a password is missing in Keychain, the store attempts a
 * one-time migration from the legacy JSON file.
 */
final class KeychainCredentialsStore: CredentialsStore {
    private let serviceName: String
    private let legacyStore: FileCredentialsStore

    /**
     * Creates a Keychain-backed credential store.
     * - Parameters:
     *   - serviceName: Keychain service identifier. Defaults to the app bundle ID.
     *   - legacyStore: Legacy file store used for one-time migration.
     */
    init(
        serviceName: String = (Bundle.main.bundleIdentifier ?? "com.Tarisper.KeenRouterManager") + ".router-password",
        legacyStore: FileCredentialsStore = FileCredentialsStore()
    ) {
        self.serviceName = serviceName
        self.legacyStore = legacyStore
    }

    /**
     * Loads credentials from Keychain, migrating them from the legacy file
     * store when necessary.
     */
    func load(routerID: UUID) throws -> RouterCredentials? {
        if let credentials = try loadFromKeychain(routerID: routerID) {
            return credentials
        }

        guard let legacyCredentials = try legacyStore.load(routerID: routerID) else {
            return nil
        }

        try save(legacyCredentials, for: routerID)
        cleanupLegacyCredentials(routerID: routerID)
        return legacyCredentials
    }

    /**
     * Saves credentials to Keychain and removes matching legacy file records.
     */
    func save(_ credentials: RouterCredentials, for routerID: UUID) throws {
        guard let passwordData = credentials.password.data(using: .utf8) else {
            throw CredentialsStoreError.invalidPasswordData
        }

        let query = baseQuery(routerID: routerID)
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: passwordData] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw CredentialsStoreError.keychainError(updateStatus)
            }
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = passwordData
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialsStoreError.keychainError(addStatus)
            }
        default:
            throw CredentialsStoreError.keychainError(status)
        }

        cleanupLegacyCredentials(routerID: routerID)
    }

    /**
     * Deletes credentials from Keychain and the legacy file store.
     */
    func delete(routerID: UUID) throws {
        let status = SecItemDelete(baseQuery(routerID: routerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialsStoreError.keychainError(status)
        }

        cleanupLegacyCredentials(routerID: routerID)
    }

    private func loadFromKeychain(routerID: UUID) throws -> RouterCredentials? {
        var query = baseQuery(routerID: routerID)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let password = String(data: data, encoding: .utf8)
            else {
                throw CredentialsStoreError.invalidPasswordData
            }
            return RouterCredentials(password: password)
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialsStoreError.keychainError(status)
        }
    }

    private func baseQuery(routerID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: routerID.uuidString
        ]
    }

    /**
     * Removes migrated credentials from the legacy JSON store.
     * - Parameter routerID: Router profile identifier.
     */
    private func cleanupLegacyCredentials(routerID: UUID) {
        try? legacyStore.delete(routerID: routerID)
    }
}
