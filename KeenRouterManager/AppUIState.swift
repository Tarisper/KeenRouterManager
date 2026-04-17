import Combine
import SwiftUI

/**
 * Shared UI state for file transfer panels and modal presentations.
 *
 * The app keeps these flags outside individual views so toolbar buttons,
 * menu commands, and the main window can coordinate the same import/export
 * and diagnostics flows.
 */
@MainActor
final class AppUIState: ObservableObject {
    @Published var isImportingConfiguration = false
    @Published var isExportingConfiguration = false
    @Published var exportDocument = RouterConfigurationDocument()
    @Published var exportFilename = "KeenRouterManager-Configuration"
    @Published var isDashboardPresented = false
    @Published var diagnosticsPayload: RouterEditorPayload?

    /**
     * Requests the shared configuration import panel.
     */
    func presentConfigurationImport() {
        isImportingConfiguration = true
    }

    /**
     * Requests the shared configuration export panel with a prepared document.
     * - Parameters:
     *   - document: Document to export.
     *   - filename: Suggested file name without path.
     */
    func presentConfigurationExport(document: RouterConfigurationDocument, filename: String) {
        exportDocument = document
        exportFilename = filename
        isExportingConfiguration = true
    }

    /**
     * Clears transient export state after the panel closes.
     */
    func finishConfigurationExport() {
        isExportingConfiguration = false
    }

    /**
     * Requests the network overview sheet from the main window.
     */
    func presentDashboard() {
        isDashboardPresented = true
    }

    /**
     * Requests diagnostics for an existing router payload.
     * - Parameter payload: Router configuration used for the diagnostic check.
     */
    func presentDiagnostics(for payload: RouterEditorPayload?) {
        diagnosticsPayload = payload
    }
}
