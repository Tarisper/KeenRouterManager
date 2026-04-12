//
//  KeenRouterManagerApp.swift
//  KeenRouterManager
//
//  Created by Daniyar Hayitov on 10.04.2026.
//

import AppKit
import SwiftUI

/**
 * Shared bridge for invoking SwiftUI scene actions from AppKit menu code.
 */
@MainActor
final class AppSceneActionBridge {
    static let shared = AppSceneActionBridge()

    var openSettings: (() -> Void)?
    var openAbout: (() -> Void)?
}

/**
 * Invisible helper view that captures SwiftUI scene-opening actions
 * and exposes them to the AppKit menu bridge.
 */
struct AppSceneActionCaptureView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                AppSceneActionBridge.shared.openSettings = { openSettings() }
                AppSceneActionBridge.shared.openAbout = { openWindow(id: "about") }
            }
    }
}

/**
 * App window size configuration and sizing helpers.
 *
 * The app keeps a fixed height and switches between expanded and collapsed
 * widths when the router sidebar is shown or hidden.
 */
@MainActor
enum WindowLayout {
    static let expandedWidth: CGFloat = 1100
    static let sidebarWidth: CGFloat = 300
    static let collapsedWidth: CGFloat = expandedWidth - sidebarWidth - 6
    static let height: CGFloat = 750

    /**
     * Returns the target window size based on sidebar visibility.
     * - Parameter sidebarVisible: Whether the left router list is visible.
     * - Returns: Window size in `NSWindow.frame` coordinates.
     */
    static func frameSize(sidebarVisible: Bool) -> CGSize {
        CGSize(width: sidebarVisible ? expandedWidth : collapsedWidth, height: height)
    }

    /**
     * Applies a fixed window size based on sidebar visibility.
     * - Parameter sidebarVisible: Whether the left router list is visible.
     */
    static func apply(sidebarVisible: Bool) {
        guard
            let window = NSApplication.shared.mainWindow
                ?? NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first
        else {
            return
        }

        let targetSize = frameSize(sidebarVisible: sidebarVisible)
        let currentFrame = window.frame

        // Keep the top edge fixed so the window does not "crawl" vertically
        // when sidebar visibility changes.
        let fixedTopY = currentFrame.maxY
        let targetFrame = NSRect(
            x: currentFrame.origin.x,
            y: fixedTopY - targetSize.height,
            width: targetSize.width,
            height: targetSize.height
        )

        window.minSize = targetSize
        window.maxSize = targetSize
        if abs(currentFrame.width - targetSize.width) > 0.5 || abs(currentFrame.height - targetSize.height) > 0.5 {
            window.setFrame(targetFrame, display: true, animate: false)
        }
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }
}

/**
 * Entry point for the KeenRouterManager app.
 *
 * Creates the main window, injects shared localization state, disables
 * default SwiftUI sidebar/toolbar commands, and registers auxiliary scenes.
 */
@main
struct KeenRouterManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var localization = LocalizationManager.shared
    private let initialSidebarVisible = FileAppSettingsStore.loadCurrent().isRouterListVisible

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(localization)
                .background(AppSceneActionCaptureView())
                .frame(
                    minWidth: WindowLayout.collapsedWidth,
                    idealWidth: WindowLayout.frameSize(sidebarVisible: initialSidebarVisible).width,
                    maxWidth: WindowLayout.expandedWidth,
                    minHeight: WindowLayout.height,
                    idealHeight: WindowLayout.height,
                    maxHeight: WindowLayout.height
                )
        }
        .defaultSize(
            width: WindowLayout.frameSize(sidebarVisible: initialSidebarVisible).width,
            height: WindowLayout.height
        )
        .windowResizability(.contentMinSize)
        .commands {
            // Remove standard sidebar/toolbar commands so SwiftUI does not
            // recreate the View menu for the split view.
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .toolbar) {}
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

/**
 * `NSApplication` delegate for post-launch window and menu tuning.
 *
 * Rebuilds the top-level menu using runtime-localized strings and applies the
 * initial fixed window size after launch.
 */
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var languageObserver: NSObjectProtocol?

    deinit {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }

    /**
     * Performs post-launch menu synchronization and initial window sizing.
     * - Parameter notification: System application launch notification.
     */
    func applicationDidFinishLaunching(_ notification: Notification) {
        synchronizeMenu()
        languageObserver = NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.synchronizeMenu()
        }

        DispatchQueue.main.async {
            let isRouterListVisible = FileAppSettingsStore.loadCurrent().isRouterListVisible
            WindowLayout.apply(sidebarVisible: isRouterListVisible)
        }
    }

    /**
     * Rebuilds the main menu immediately and repeats the update a few times
     * to catch any delayed SwiftUI/AppKit menu reconfiguration after launch
     * or language changes.
     */
    private func synchronizeMenu() {
        rebuildMainMenu()
        let delays: [TimeInterval] = [0.02, 0.08, 0.2]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.rebuildMainMenu()
            }
        }
    }

    /**
     * Recreates the app's top-level menu using the current interface language.
     */
    private func rebuildMainMenu() {
        let localization = LocalizationManager.shared
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "KeenRouterManager"
        let mainMenu = NSMenu(title: appName)

        let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        appMenuItem.submenu = buildApplicationMenu(appName: appName, localization: localization)
        mainMenu.addItem(appMenuItem)

        let windowMenu = buildWindowMenu(localization: localization)
        let windowMenuItem = NSMenuItem(title: localization.text("menu.window"), action: nil, keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    /**
     * Builds the application menu (`About`, `Settings`, `Hide`, `Quit`, etc.).
     * - Parameters:
     *   - appName: Display name of the app.
     *   - localization: Active localization manager.
     * - Returns: Configured AppKit menu.
     */
    private func buildApplicationMenu(appName: String, localization: LocalizationManager) -> NSMenu {
        let menu = NSMenu(title: appName)
        let servicesMenu = NSMenu(title: localization.text("menu.services"))

        let aboutItem = menuItem(
            localization.text("menu.aboutApp", args: [appName]),
            action: #selector(openAboutWindow(_:))
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let settingsItem = menuItem(
            localization.text("menu.settings"),
            action: #selector(openSettingsScene(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let servicesItem = NSMenuItem(title: localization.text("menu.services"), action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        menu.addItem(.separator())
        menu.addItem(menuItem(
            localization.text("menu.hideApp", args: [appName]),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        menu.addItem(menuItem(
            localization.text("menu.hideOthers"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifierMask: [.command, .option]
        ))
        menu.addItem(menuItem(
            localization.text("menu.showAll"),
            action: #selector(NSApplication.unhideAllApplications(_:))
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            localization.text("menu.quitApp", args: [appName]),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        return menu
    }

    /**
     * Builds the `Window` menu.
     * - Parameter localization: Active localization manager.
     * - Returns: Configured AppKit menu.
     */
    private func buildWindowMenu(localization: LocalizationManager) -> NSMenu {
        let menu = NSMenu(title: localization.text("menu.window"))

        menu.addItem(menuItem(
            localization.text("menu.windowMinimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        menu.addItem(menuItem(
            localization.text("menu.windowZoom"),
            action: #selector(NSWindow.performZoom(_:))
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            localization.text("menu.windowBringAllToFront"),
            action: #selector(NSApplication.arrangeInFront(_:))
        ))

        return menu
    }

    /**
     * Creates a convenience `NSMenuItem`.
     * - Parameters:
     *   - title: Menu item title.
     *   - action: Selector invoked by AppKit.
     *   - keyEquivalent: Keyboard shortcut key.
     *   - modifierMask: Keyboard shortcut modifiers.
     * - Returns: Configured menu item.
     */
    private func menuItem(
        _ title: String,
        action: Selector?,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : modifierMask
        return item
    }

    /**
     * Opens the SwiftUI Settings scene through the captured `openSettings` action.
     * - Parameter sender: AppKit sender object.
     */
    @objc
    private func openSettingsScene(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        AppSceneActionBridge.shared.openSettings?()
    }

    /**
     * Opens the SwiftUI About window.
     * - Parameter sender: AppKit sender object.
     */
    @objc
    private func openAboutWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        AppSceneActionBridge.shared.openAbout?()
    }
}
