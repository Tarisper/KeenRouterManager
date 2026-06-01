import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum XkeenFilePanels {
    static func chooseBackupDownloadURL(localization: LocalizationManager) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.gzip]
        panel.nameFieldStringValue = defaultBackupArchiveName()
        panel.title = localization.text("xkeen.backups.downloadPanel.title")
        panel.prompt = localization.text("xkeen.backups.downloadPanel.prompt")
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseXrayConfigURLs(localization: LocalizationManager) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.title = localization.text("xkeen.configs.replacePanel.title")
        panel.prompt = localization.text("xkeen.configs.replacePanel.prompt")
        return panel.runModal() == .OK ? panel.urls : []
    }

    private static func defaultBackupArchiveName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "xkeen-backups-\(formatter.string(from: Date())).tar.gz"
    }
}
