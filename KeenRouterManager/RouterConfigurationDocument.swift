import SwiftUI
import UniformTypeIdentifiers

/**
 * Errors produced while importing or exporting configuration archives.
 */
enum RouterConfigurationTransferError: LocalizedError {
    case invalidData
    case unsupportedFormatVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return LocalizationManager.shared.text("error.configuration.invalidData")
        case let .unsupportedFormatVersion(version):
            return LocalizationManager.shared.text("error.configuration.unsupportedVersion", args: [version])
        }
    }
}

/**
 * SwiftUI file document wrapper around `RouterConfigurationArchive`.
 */
struct RouterConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var archive: RouterConfigurationArchive

    init(archive: RouterConfigurationArchive = RouterConfigurationArchive()) {
        self.archive = archive
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw RouterConfigurationTransferError.invalidData
        }
        self.archive = try Self.decodeArchive(from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encodeArchive(archive))
    }

    /**
     * Decodes an archive from raw JSON data.
     * - Parameter data: File contents.
     * - Returns: Parsed archive.
     * - Throws: Transfer validation error.
     */
    static func decodeArchive(from data: Data) throws -> RouterConfigurationArchive {
        do {
            let archiveDTO = try MainActor.assumeIsolated {
                try makeDecoder().decode(RouterConfigurationArchiveDTO.self, from: data)
            }
            let archive = RouterConfigurationArchive(dto: archiveDTO)
            guard archive.formatVersion <= RouterConfigurationArchive.currentFormatVersion else {
                throw RouterConfigurationTransferError.unsupportedFormatVersion(archive.formatVersion)
            }
            return archive
        } catch let error as RouterConfigurationTransferError {
            throw error
        } catch {
            throw RouterConfigurationTransferError.invalidData
        }
    }

    /**
     * Encodes an archive to JSON data.
     * - Parameter archive: Archive to serialize.
     * - Returns: JSON data.
     * - Throws: Encoding error.
     */
    static func encodeArchive(_ archive: RouterConfigurationArchive) throws -> Data {
        let encoder = JSONEncoder.pretty
        encoder.dateEncodingStrategy = .iso8601
        return try MainActor.assumeIsolated {
            try encoder.encode(archive.dto)
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
