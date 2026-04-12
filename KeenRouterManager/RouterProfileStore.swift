import Foundation

/**
 * File-based storage for router profiles.
 */
final class RouterProfileStore {
    private enum Storage {
        static let profilesFileName = "routers.json"
    }

    private let fileURL: URL

    /**
     * Creates profile storage at `Application Support/KeenRouterManager/routers.json`.
     * - Parameter fileManager: `FileManager` instance used for file operations.
     */
    init(fileManager: FileManager = .default) {
        let directory = AppStorageLocation.directoryURL(fileManager: fileManager)
        self.fileURL = directory.appendingPathComponent(Storage.profilesFileName)
    }

    /**
     * Loads all saved router profiles.
     * - Returns: Saved profiles or an empty array if the file is absent.
     * - Throws: Read/decode error.
     */
    func loadProfiles() throws -> [RouterProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([RouterProfile].self, from: data)
    }

    /**
     * Persists the full router profile list.
     * - Parameter profiles: Full profile list to save.
     * - Throws: Encode/write error.
     */
    func saveProfiles(_ profiles: [RouterProfile]) throws {
        let data = try JSONEncoder.pretty.encode(profiles)
        try data.write(to: fileURL, options: .atomic)
    }

    /**
     * Absolute path to the `routers.json` file.
     */
    var storagePath: String {
        fileURL.path
    }
}

extension JSONEncoder {
    /**
     * `JSONEncoder` configured for readable local JSON storage.
     */
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
