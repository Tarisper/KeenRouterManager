import Foundation

enum XkeenCommand: String, CaseIterable, Identifiable, Sendable {
    case status
    case start
    case stop
    case restart
    case updateGeo
    case updateXray
    case updateXkeen
    case backupXkeen
    case backupConfig
    case restoreXkeen
    case restoreConfig
    case deleteBackups
    case downloadBackups
    case replaceConfigs

    var id: String { rawValue }

    nonisolated var argument: String {
        switch self {
        case .status:
            return "-status"
        case .start:
            return "-start"
        case .stop:
            return "-stop"
        case .restart:
            return "-restart"
        case .updateGeo:
            return "-ug"
        case .updateXray:
            return "-ux"
        case .updateXkeen:
            return "-uk"
        case .backupXkeen:
            return "-kb"
        case .backupConfig:
            return "-cb"
        case .restoreXkeen:
            return "-kbr"
        case .restoreConfig:
            return "-cbr"
        case .deleteBackups, .downloadBackups, .replaceConfigs:
            return ""
        }
    }

    nonisolated var localizationKey: String {
        switch self {
        case .status:
            return "xkeen.command.status"
        case .start:
            return "xkeen.command.start"
        case .stop:
            return "xkeen.command.stop"
        case .restart:
            return "xkeen.command.restart"
        case .updateGeo:
            return "xkeen.command.updateGeo"
        case .updateXray:
            return "xkeen.command.updateXray"
        case .updateXkeen:
            return "xkeen.command.updateXkeen"
        case .backupXkeen:
            return "xkeen.command.backupXkeen"
        case .backupConfig:
            return "xkeen.command.backupConfig"
        case .restoreXkeen:
            return "xkeen.command.restoreXkeen"
        case .restoreConfig:
            return "xkeen.command.restoreConfig"
        case .deleteBackups:
            return "xkeen.command.deleteBackups"
        case .downloadBackups:
            return "xkeen.command.downloadBackups"
        case .replaceConfigs:
            return "xkeen.command.replaceConfigs"
        }
    }

    nonisolated var createsBackupBeforeRun: XkeenCommand? {
        switch self {
        case .updateXkeen:
            return .backupXkeen
        default:
            return nil
        }
    }
}

struct XkeenSSHProfile: Identifiable, Hashable, Sendable {
    var id: String { "\(username)@\(host):\(port):\(xkeenPath)" }
    var host: String
    var port: Int
    var username: String
    var password: String
    var xkeenPath: String
}

struct XkeenCommandResult: Hashable, Sendable {
    var command: XkeenCommand
    var exitCode: Int32
    var output: String
}

struct XkeenBackupItem: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var kind: String
    var sizeKilobytes: Int?
    var modified: String
}

enum XkeenSSHError: LocalizedError, Sendable {
    case missingHost
    case missingUsername
    case missingPassword
    case missingXkeenPath
    case launchFailed(String)
    case invalidBackupName(String)
    case downloadFailed(String)
    case invalidConfigFileName(String)
    case uploadFailed(String)
    case interactiveInputRequired

    var errorDescription: String? {
        switch self {
        case .missingHost:
            return LocalizationManager.shared.text("error.ssh.missingHost")
        case .missingUsername:
            return LocalizationManager.shared.text("error.ssh.missingUsername")
        case .missingPassword:
            return LocalizationManager.shared.text("error.ssh.missingPassword")
        case .missingXkeenPath:
            return LocalizationManager.shared.text("error.ssh.missingXkeenPath")
        case let .launchFailed(message):
            return LocalizationManager.shared.text("error.ssh.launchFailed", args: [message])
        case let .invalidBackupName(name):
            return LocalizationManager.shared.text("error.ssh.invalidBackupName", args: [name])
        case let .downloadFailed(message):
            return LocalizationManager.shared.text("error.ssh.downloadFailed", args: [message])
        case let .invalidConfigFileName(name):
            return LocalizationManager.shared.text("error.ssh.invalidConfigFileName", args: [name])
        case let .uploadFailed(message):
            return LocalizationManager.shared.text("error.ssh.uploadFailed", args: [message])
        case .interactiveInputRequired:
            return LocalizationManager.shared.text("error.ssh.interactiveInputRequired")
        }
    }
}
