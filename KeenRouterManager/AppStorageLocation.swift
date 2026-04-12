import Foundation

/**
 * Shared `Application Support` location for KeenRouterManager data files.
 *
 * The helper also migrates data from the legacy `KeenMngr` directory so
 * existing router profiles, credentials, and settings survive the rename.
 */
enum AppStorageLocation {
    static let directoryName = "KeenRouterManager"
    private static let legacyDirectoryName = "KeenMngr"

    /**
     * Returns the app-specific storage directory, creating it when needed.
     * - Parameter fileManager: `FileManager` used for file operations.
     * - Returns: Directory URL inside `Application Support`.
     */
    static func directoryURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let currentDirectory = appSupport.appendingPathComponent(directoryName, isDirectory: true)
        let legacyDirectory = appSupport.appendingPathComponent(legacyDirectoryName, isDirectory: true)

        migrateLegacyDirectoryIfNeeded(from: legacyDirectory, to: currentDirectory, fileManager: fileManager)

        if !fileManager.fileExists(atPath: currentDirectory.path) {
            try? fileManager.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        }

        return currentDirectory
    }

    /**
     * Moves or merges files from the legacy application support directory.
     * - Parameters:
     *   - legacyDirectory: Previous app directory.
     *   - currentDirectory: New app directory.
     *   - fileManager: `FileManager` used for file operations.
     */
    private static func migrateLegacyDirectoryIfNeeded(
        from legacyDirectory: URL,
        to currentDirectory: URL,
        fileManager: FileManager
    ) {
        guard fileManager.fileExists(atPath: legacyDirectory.path) else {
            return
        }

        guard fileManager.fileExists(atPath: currentDirectory.path) else {
            try? fileManager.moveItem(at: legacyDirectory, to: currentDirectory)
            return
        }

        guard let legacyItems = try? fileManager.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for legacyItem in legacyItems {
            let targetItem = currentDirectory.appendingPathComponent(legacyItem.lastPathComponent)
            guard !fileManager.fileExists(atPath: targetItem.path) else { continue }
            try? fileManager.copyItem(at: legacyItem, to: targetItem)
        }
    }
}
