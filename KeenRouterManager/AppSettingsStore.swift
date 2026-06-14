import Foundation

/**
 * Errors produced by application settings storage.
 */
enum AppSettingsStoreError: LocalizedError {
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return LocalizationManager.shared.text("error.settings.invalidData")
        }
    }
}

/**
 * Global application settings persisted locally.
 *
 * This model stores small UI preferences that should survive app relaunches.
 */
struct AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case showOnlyMyDevices
        case favoriteClientMACs
        case isRouterListVisible
        case interfaceLanguageCode
        case xkeenSSHPort
        case xkeenPath
    }

    /**
     * Show only devices that match local MAC addresses of this Mac.
     */
    var showOnlyMyDevices: Bool = false

    /**
     * MAC addresses of clients marked as favorites.
     */
    var favoriteClientMACs: Set<String> = []

    /**
     * Whether the router list sidebar is visible.
     */
    var isRouterListVisible: Bool = true

    /**
     * Selected interface language code (`ru`/`en`).
     *
     * When `nil`, the app uses system language and persists the resolved value later.
     */
    var interfaceLanguageCode: String? = nil

    /**
     * SSH port used for Xkeen management.
     */
    var xkeenSSHPort: String = "222"

    /**
     * Absolute path to the Xkeen executable on the router.
     */
    var xkeenPath: String = "/opt/sbin/xkeen"

    /**
     * Creates settings with explicit values.
     */
    init(
        showOnlyMyDevices: Bool = false,
        favoriteClientMACs: Set<String> = [],
        isRouterListVisible: Bool = true,
        interfaceLanguageCode: String? = nil,
        xkeenSSHPort: String = "222",
        xkeenPath: String = "/opt/sbin/xkeen"
    ) {
        self.showOnlyMyDevices = showOnlyMyDevices
        self.favoriteClientMACs = Self.normalizedMACs(favoriteClientMACs)
        self.isRouterListVisible = isRouterListVisible
        self.interfaceLanguageCode = interfaceLanguageCode
        self.xkeenSSHPort = xkeenSSHPort
        self.xkeenPath = xkeenPath
    }

    /**
     * Decodes settings while tolerating missing keys from older app versions.
     * - Parameter decoder: Decoder providing stored JSON.
     * - Throws: Decoder error only when present values have invalid types.
     */
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showOnlyMyDevices = try container.decodeIfPresent(Bool.self, forKey: .showOnlyMyDevices) ?? false
        self.favoriteClientMACs = Self.normalizedMACs(
            try container.decodeIfPresent(Set<String>.self, forKey: .favoriteClientMACs) ?? []
        )
        self.isRouterListVisible = try container.decodeIfPresent(Bool.self, forKey: .isRouterListVisible) ?? true
        self.interfaceLanguageCode = try container.decodeIfPresent(String.self, forKey: .interfaceLanguageCode)
        self.xkeenSSHPort = try container.decodeIfPresent(String.self, forKey: .xkeenSSHPort) ?? "222"
        self.xkeenPath = try container.decodeIfPresent(String.self, forKey: .xkeenPath) ?? "/opt/sbin/xkeen"
    }

    private static func normalizedMACs(_ macs: Set<String>) -> Set<String> {
        Set(macs.map { $0.lowercased() })
    }
}

/**
 * File-based settings storage in `Application Support/KeenRouterManager/settings.json`.
 */
final class FileAppSettingsStore {
    private enum Storage {
        static let settingsFileName = "settings.json"
    }

    private let fileURL: URL

    /**
     * Creates the file-based settings store.
     * - Parameter fileManager: `FileManager` instance used for file operations.
     */
    init(fileManager: FileManager = .default) {
        let directory = AppStorageLocation.directoryURL(fileManager: fileManager)
        fileURL = directory.appendingPathComponent(Storage.settingsFileName)
    }

    /**
     * Loads application settings from disk.
     * - Returns: Decoded settings, or defaults when the file is absent/empty.
     * - Throws: `AppSettingsStoreError.invalidData` when JSON is malformed.
     */
    func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return AppSettings()
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            throw AppSettingsStoreError.invalidData
        }
    }

    /**
     * Saves application settings to a JSON file.
     * - Parameter settings: Settings model to persist.
     * - Throws: File system error when writing fails.
     */
    func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder.pretty.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    /**
     * Atomically updates settings while preserving unrelated fields.
     * - Parameter mutate: In-place settings mutator.
     * - Throws: Read/decode/write errors.
     */
    func update(_ mutate: (inout AppSettings) -> Void) throws {
        var settings = try load()
        mutate(&settings)
        try save(settings)
    }

    /**
     * Loads current settings or returns defaults when reading fails.
     * - Returns: Decoded settings or default values.
     */
    static func loadCurrent() -> AppSettings {
        (try? FileAppSettingsStore().load()) ?? AppSettings()
    }
}
