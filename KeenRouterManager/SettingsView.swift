import SwiftUI

/**
 * Application settings window.
 *
 * Currently exposes interface language selection and applies changes immediately.
 */
struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.text("settings.interfaceLanguage"))
                .font(.headline)

            HStack(alignment: .center, spacing: 12) {
                Text(localization.text("settings.interfaceLanguage"))
                    .frame(width: 170, alignment: .leading)

                Picker("", selection: $localization.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(localization.displayName(for: language))
                            .tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 220, alignment: .leading)
            }

            Text(localization.text("settings.interfaceLanguageHint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 460, height: 170, alignment: .topLeading)
    }
}

#Preview {
    SettingsView()
        .environmentObject(LocalizationManager.shared)
}
