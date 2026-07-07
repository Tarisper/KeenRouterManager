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
            Section(localization.text("settings.interface")) {
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

            Section(localization.text("settings.filters")) {
                Toggle(localization.text("settings.filters.myDevices"), isOn: $viewModel.showOnlyMyDevices)
            }

            Section(localization.text("settings.security")) {
                Toggle(
                    localization.text("settings.security.allowSelfSignedCertificates"),
                    isOn: $viewModel.allowsSelfSignedRouterCertificates
                )

                Text(localization.text("settings.security.allowSelfSignedCertificatesHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(localization.text("settings.xkeen")) {
                Stepper(
                    value: $viewModel.xkeenSSHPort,
                    in: 1...65535
                ) {
                    LabeledContent(localization.text("settings.xkeen.sshPort")) {
                        Text("\(viewModel.xkeenSSHPort)")
                            .monospacedDigit()
                    }
                }
                TextField(localization.text("settings.xkeen.path"), text: $viewModel.xkeenPath)
                    .onSubmit {
                        viewModel.normalizeXkeenPath()
                    }

                if !viewModel.isXkeenPathValid {
                    Label(localization.text("settings.xkeen.invalidPath"), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text(localization.text("settings.xkeen.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(localization.text("settings.geoAutoUpdate")) {
                Picker(localization.text("settings.geoAutoUpdate.day"), selection: $viewModel.geoAutoUpdateDay) {
                    ForEach(GeoAutoUpdateDay.allCases) { day in
                        Text(localization.text("xkeen.geoAutoUpdate.day.\(day.rawValue)"))
                            .tag(day.rawValue)
                    }
                }

                Stepper(value: $viewModel.geoAutoUpdateHour, in: 0...23) {
                    LabeledContent(localization.text("settings.geoAutoUpdate.hour")) {
                        Text(String(format: "%02d", viewModel.geoAutoUpdateHour))
                            .monospacedDigit()
                    }
                }

                Stepper(value: $viewModel.geoAutoUpdateMinute, in: 0...59) {
                    LabeledContent(localization.text("settings.geoAutoUpdate.minute")) {
                        Text(String(format: "%02d", viewModel.geoAutoUpdateMinute))
                            .monospacedDigit()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 590)
        .scenePadding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(LocalizationManager.shared)
        .environmentObject(MainViewModel())
}
