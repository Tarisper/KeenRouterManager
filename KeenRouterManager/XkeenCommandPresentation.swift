import Foundation

extension XkeenCommand {
    var systemImage: String {
        switch self {
        case .status:
            return "info.circle"
        case .start:
            return "play.fill"
        case .stop:
            return "stop.fill"
        case .restart:
            return "arrow.clockwise"
        case .updateGeo:
            return "map"
        case .updateXray:
            return "bolt.horizontal"
        case .updateXkeen:
            return "shippingbox"
        case .backupXkeen, .backupConfig:
            return "externaldrive"
        case .restoreXkeen, .restoreConfig:
            return "arrow.uturn.backward"
        case .deleteBackups:
            return "trash"
        case .downloadBackups:
            return "square.and.arrow.down"
        case .replaceConfigs:
            return "arrow.up.doc"
        }
    }
}
