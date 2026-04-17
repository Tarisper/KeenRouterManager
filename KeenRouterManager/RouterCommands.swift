import SwiftUI

/**
 * Native macOS menu commands for router-specific actions and file transfer.
 */
struct RouterCommands: Commands {
    @ObservedObject var appState: AppUIState
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var localization: LocalizationManager

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "KeenRouterManager"
    }

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()
        ToolbarCommands()

        CommandGroup(replacing: .appInfo) {
            Button(localization.text("menu.aboutApp", args: [appName])) {
                AppSceneActionBridge.shared.openAbout?()
            }
        }

        CommandGroup(after: .importExport) {
            Button(localization.text("menu.importConfiguration")) {
                appState.presentConfigurationImport()
            }
            .keyboardShortcut("o")

            Button(localization.text("menu.exportConfiguration")) {
                requestConfigurationExport()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandMenu(localization.text("menu.router")) {
            Button(localization.text("action.connect")) {
                Task {
                    await viewModel.connectSelectedProfile()
                }
            }
            .disabled(viewModel.selectedProfile == nil || viewModel.isBusy)
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button(localization.text("action.refresh")) {
                Task {
                    await viewModel.refreshClients()
                }
            }
            .disabled(!viewModel.isConnected || viewModel.isBusy)
            .keyboardShortcut("r")

            Button(localization.text("action.diagnose")) {
                appState.presentDiagnostics(for: viewModel.makeDiagnosticsPayloadForSelected())
            }
            .disabled(viewModel.selectedProfile == nil)

            Divider()

            Button(localization.text("menu.openDashboard")) {
                appState.presentDashboard()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }

    private func requestConfigurationExport() {
        do {
            let document = try viewModel.makeConfigurationDocument()
            appState.presentConfigurationExport(
                document: document,
                filename: viewModel.defaultConfigurationExportFilename
            )
        } catch {
            viewModel.present(error: error)
        }
    }
}
