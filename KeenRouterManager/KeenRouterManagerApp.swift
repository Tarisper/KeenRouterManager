import AppKit
import SwiftUI

/**
 * Shared bridge for opening auxiliary windows from menu commands.
 */
@MainActor
final class AppSceneActionBridge {
    static let shared = AppSceneActionBridge()

    var openAbout: (() -> Void)?
}

/**
 * Invisible helper view that captures SwiftUI window-opening actions and
 * exposes them to menu commands.
 */
struct AppSceneActionCaptureView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear {
                AppSceneActionBridge.shared.openAbout = { openWindow(id: "about") }
            }
    }
}

/**
 * Entry point for KeenRouterManager.
 *
 * The app uses native SwiftUI scenes for the main router browser, settings,
 * and about window. Contextual flows like diagnostics and the network overview
 * are presented from the main window as sheets.
 */
@main
struct KeenRouterManagerApp: App {
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var viewModel = MainViewModel()
    @StateObject private var appUI = AppUIState()

    init() {
        // The app never uses document-style tabbed windows, so remove the
        // system tabbing commands from the Window menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("KeenRouterManager", id: "main") {
            ContentView()
                .environmentObject(localization)
                .environmentObject(viewModel)
                .environmentObject(appUI)
                .background(AppSceneActionCaptureView())
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            RouterCommands(
                appState: appUI,
                viewModel: viewModel,
                localization: localization
            )
        }

        Settings {
            SettingsView()
                .environmentObject(localization)
        }
        .windowResizability(.contentSize)

        Window(localization.text("about.windowTitle"), id: "about") {
            AboutView()
                .environmentObject(localization)
        }
        .windowResizability(.contentSize)
    }
}
