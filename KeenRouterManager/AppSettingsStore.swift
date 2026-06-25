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
        case allowsSelfSignedRouterCertificates
        case xkeenSSHPort
        case xkeenPath
        case geoAutoUpdateDay
        case geoAutoUpdateHour
        case geoAutoUpdateMinute
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
     * Whether HTTPS router connections may accept local/self-signed certificates.
     */
    var allowsSelfSignedRouterCertificates: Bool = AppDefaults.allowsSelfSignedRouterCertificates

    /**
     * SSH port used for Xkeen management.
     */
    var xkeenSSHPort: Int = AppDefaults.xkeenSSHPort

    /**
     * Absolute path to the Xkeen executable on the router.
     */
    var xkeenPath: String = AppDefaults.xkeenPath

    /**
     * Xkeen Geo auto-update weekday (`1...7`) or daily (`8`).
     */
    var geoAutoUpdateDay: Int = AppDefaults.geoAutoUpdateDay

    /**
     * Xkeen Geo auto-update hour (`0...23`).
     */
    var geoAutoUpdateHour: Int = AppDefaults.geoAutoUpdateHour

    /**
     * Xkeen Geo auto-update minute (`0...59`).
     */
    var geoAutoUpdateMinute: Int = AppDefaults.geoAutoUpdateMinute

    /**
     * Creates settings with explicit values.
     */
    init(
        showOnlyMyDevices: Bool = false,
        favoriteClientMACs: Set<String> = [],
        isRouterListVisible: Bool = true,
        interfaceLanguageCode: String? = nil,
        allowsSelfSignedRouterCertificates: Bool = AppDefaults.allowsSelfSignedRouterCertificates,
        xkeenSSHPort: Int = AppDefaults.xkeenSSHPort,
        xkeenPath: String = AppDefaults.xkeenPath,
        geoAutoUpdateDay: Int = AppDefaults.geoAutoUpdateDay,
        geoAutoUpdateHour: Int = AppDefaults.geoAutoUpdateHour,
        geoAutoUpdateMinute: Int = AppDefaults.geoAutoUpdateMinute
    ) {
        self.showOnlyMyDevices = showOnlyMyDevices
        self.favoriteClientMACs = Self.normalizedMACs(favoriteClientMACs)
        self.isRouterListVisible = isRouterListVisible
        self.interfaceLanguageCode = interfaceLanguageCode
        self.allowsSelfSignedRouterCertificates = allowsSelfSignedRouterCertificates
        self.xkeenSSHPort = AppDefaults.normalizedXkeenSSHPort(xkeenSSHPort)
        self.xkeenPath = xkeenPath
        self.geoAutoUpdateDay = AppDefaults.normalizedGeoAutoUpdateDay(geoAutoUpdateDay)
        self.geoAutoUpdateHour = AppDefaults.normalizedGeoAutoUpdateHour(geoAutoUpdateHour)
        self.geoAutoUpdateMinute = AppDefaults.normalizedGeoAutoUpdateMinute(geoAutoUpdateMinute)
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
        self.allowsSelfSignedRouterCertificates =
            try container.decodeIfPresent(Bool.self, forKey: .allowsSelfSignedRouterCertificates) ??
            AppDefaults.allowsSelfSignedRouterCertificates
        self.xkeenSSHPort = AppDefaults.normalizedXkeenSSHPort(try Self.decodeSSHPort(from: container))
        self.xkeenPath = try container.decodeIfPresent(String.self, forKey: .xkeenPath) ?? AppDefaults.xkeenPath
        self.geoAutoUpdateDay = AppDefaults.normalizedGeoAutoUpdateDay(
            try container.decodeIfPresent(Int.self, forKey: .geoAutoUpdateDay) ?? AppDefaults.geoAutoUpdateDay
        )
        self.geoAutoUpdateHour = AppDefaults.normalizedGeoAutoUpdateHour(
            try container.decodeIfPresent(Int.self, forKey: .geoAutoUpdateHour) ?? AppDefaults.geoAutoUpdateHour
        )
        self.geoAutoUpdateMinute = AppDefaults.normalizedGeoAutoUpdateMinute(
            try container.decodeIfPresent(Int.self, forKey: .geoAutoUpdateMinute) ?? AppDefaults.geoAutoUpdateMinute
        )
    }

    private static func normalizedMACs(_ macs: Set<String>) -> Set<String> {
        Set(macs.map { $0.lowercased() })
    }

    private static func decodeSSHPort(from container: KeyedDecodingContainer<CodingKeys>) throws -> Int {
        guard container.contains(.xkeenSSHPort), try !container.decodeNil(forKey: .xkeenSSHPort) else {
            return AppDefaults.xkeenSSHPort
        }
        if let port = try? container.decode(Int.self, forKey: .xkeenSSHPort) {
            return port
        }
        if let rawPort = try? container.decode(String.self, forKey: .xkeenSSHPort),
           let port = Int(rawPort.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return port
        }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(
                codingPath: container.codingPath + [CodingKeys.xkeenSSHPort],
                debugDescription: "Expected an integer SSH port or a numeric string."
            )
        )
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
