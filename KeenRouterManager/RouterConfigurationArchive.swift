import Foundation

/**
 * Serialized application configuration archive for import/export.
 *
 * Passwords remain in the system Keychain and are intentionally excluded from
 * this transfer format. This keeps exports portable without writing secrets to
 * disk in plain text.
 */
struct RouterConfigurationArchive {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var exportedAt: Date
    var credentialsIncluded: Bool
    var appSettings: AppSettings
    var profiles: [RouterProfile]

    init(
        formatVersion: Int = currentFormatVersion,
        exportedAt: Date = Date(),
        credentialsIncluded: Bool = false,
        appSettings: AppSettings = AppSettings(),
        profiles: [RouterProfile] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.credentialsIncluded = credentialsIncluded
        self.appSettings = appSettings
        self.profiles = profiles
    }
}

/**
 * Codable transport DTO kept separate from the runtime archive model to avoid
 * actor-isolation leaking into `FileDocument` serialization paths.
 */
struct RouterConfigurationArchiveDTO: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var credentialsIncluded: Bool
    var appSettings: AppSettings
    var profiles: [RouterProfile]
}

extension RouterConfigurationArchive {
    init(dto: RouterConfigurationArchiveDTO) {
        self.init(
            formatVersion: dto.formatVersion,
            exportedAt: dto.exportedAt,
            credentialsIncluded: dto.credentialsIncluded,
            appSettings: dto.appSettings,
            profiles: dto.profiles
        )
    }

    var dto: RouterConfigurationArchiveDTO {
        RouterConfigurationArchiveDTO(
            formatVersion: formatVersion,
            exportedAt: exportedAt,
            credentialsIncluded: credentialsIncluded,
            appSettings: appSettings,
            profiles: profiles
        )
    }
}
