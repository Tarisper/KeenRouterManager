import Foundation

/**
 * Shared defaults for persisted app preferences and Xkeen management.
 */
enum AppDefaults {
    nonisolated static let xkeenSSHPort = 222
    nonisolated static let xkeenPath = "/opt/sbin/xkeen"
    nonisolated static let xkeenBackupPath = "/opt/backups"
    nonisolated static let allowsSelfSignedRouterCertificates = true
    nonisolated static let geoAutoUpdateDay = GeoAutoUpdateDay.daily.rawValue
    nonisolated static let geoAutoUpdateHour = 4
    nonisolated static let geoAutoUpdateMinute = 30

    nonisolated static func normalizedXkeenSSHPort(_ port: Int) -> Int {
        isValidXkeenSSHPort(port) ? port : xkeenSSHPort
    }

    nonisolated static func isValidXkeenSSHPort(_ port: Int) -> Bool {
        (1...65535).contains(port)
    }

    nonisolated static func normalizedXkeenPath(_ path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? xkeenPath : trimmedPath
    }

    nonisolated static func isValidXkeenPath(_ path: String) -> Bool {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.hasPrefix("/") && trimmedPath.count > 1
    }

    nonisolated static func normalizedGeoAutoUpdateDay(_ day: Int) -> Int {
        GeoAutoUpdateDay(rawValue: day)?.rawValue ?? geoAutoUpdateDay
    }

    nonisolated static func normalizedGeoAutoUpdateHour(_ hour: Int) -> Int {
        (0...23).contains(hour) ? hour : geoAutoUpdateHour
    }

    nonisolated static func normalizedGeoAutoUpdateMinute(_ minute: Int) -> Int {
        (0...59).contains(minute) ? minute : geoAutoUpdateMinute
    }
}
