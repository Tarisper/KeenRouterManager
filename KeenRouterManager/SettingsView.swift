import SwiftUI

/**
 * Application settings window.
 *
 * The settings scene follows the standard macOS pattern: a dedicated window
 * with a compact form-based layout for app-level preferences.
 */
struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var viewModel: MainViewModel

    var body: some View {
        Form {
            Section(localization.text("settings.general")) {
                Picker(localization.text("settings.interfaceLanguage"), selection: $localization.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(localization.displayName(for: language))
                            .tag(language)
                    }
                }

                Text(localization.text("settings.interfaceLanguageHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(localization.text("settings.xkeen")) {
                TextField(localization.text("settings.xkeen.sshPort"), text: $viewModel.xkeenSSHPort)
                TextField(localization.text("settings.xkeen.path"), text: $viewModel.xkeenPath)

                Text(localization.text("settings.xkeen.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
        .scenePadding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(LocalizationManager.shared)
        .environmentObject(MainViewModel())
}
