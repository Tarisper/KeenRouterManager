import Combine
import Foundation

/**
 * Supported interface languages.
 */
enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }

    /**
     * Resolves a language from an arbitrary language code.
     * - Parameter code: Full or short language code (for example `ru-RU`, `en_US`, `ru`).
     * - Returns: Matching app language, or `nil` when unsupported.
     */
    nonisolated static func resolve(code: String?) -> AppLanguage? {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !code.isEmpty else {
            return nil
        }

        if code.hasPrefix("ru") {
            return .russian
        }
        if code.hasPrefix("en") {
            return .english
        }
        return nil
    }

    /**
     * Chooses the best language from current system preferences.
     * - Returns: Supported language inferred from `Locale.preferredLanguages`.
     */
    nonisolated static func systemDefault() -> AppLanguage {
        for preferred in Locale.preferredLanguages {
            if let resolved = resolve(code: preferred) {
                return resolved
            }
        }
        return .english
    }
}

/**
 * Runtime localization service that loads translated strings from a JSON file
 * and persists the selected interface language in app settings.
 */
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            persistLanguageSelection()
            NotificationCenter.default.post(name: .appLanguageDidChange, object: language)
        }
    }

    private let settingsStore: FileAppSettingsStore
    private let translations: [AppLanguage: [String: String]]

    /**
     * Creates localization manager and restores language from app settings.
     * - Parameters:
     *   - settingsStore: Settings storage used to persist selected language.
     *   - bundle: Bundle used to load `InterfaceStrings.json`.
     */
    init(settingsStore: FileAppSettingsStore = FileAppSettingsStore(), bundle: Bundle = .main) {
        self.settingsStore = settingsStore
        self.translations = Self.loadTranslations(from: bundle)

        let storedLanguage = (try? settingsStore.load().interfaceLanguageCode).flatMap(AppLanguage.resolve)
        let effectiveLanguage = storedLanguage ?? AppLanguage.systemDefault()
        language = effectiveLanguage

        if storedLanguage == nil {
            persistLanguageSelection()
        }
    }

    /**
     * Returns localized text for a key using the active language.
     * - Parameters:
     *   - key: Translation key.
     *   - args: Optional format arguments (`String(format:)` style).
     * - Returns: Localized text, English fallback, or the key itself when missing.
     */
    func text(_ key: String, args: [CVarArg] = []) -> String {
        let template = translations[language]?[key]
            ?? translations[.english]?[key]
            ?? key

        guard !args.isEmpty else {
            return template
        }

        return String(format: template, locale: Locale(identifier: language.rawValue), arguments: args)
    }

    /**
     * Convenience overload for vararg formatting.
     * - Parameters:
     *   - key: Translation key.
     *   - args: Format arguments.
     * - Returns: Localized string.
     */
    func text(_ key: String, _ args: CVarArg...) -> String {
        text(key, args: args)
    }

    /**
     * User-facing language name in the current UI language.
     * - Parameter language: Language to display.
     * - Returns: Localized language name.
     */
    func displayName(for language: AppLanguage) -> String {
        switch language {
        case .russian:
            return text("language.russian")
        case .english:
            return text("language.english")
        }
    }

    private func persistLanguageSelection() {
        do {
            try settingsStore.update { settings in
                settings.interfaceLanguageCode = language.rawValue
            }
        } catch {
            // Keep app functional even if settings cannot be saved.
        }
    }

    private static func loadTranslations(from bundle: Bundle) -> [AppLanguage: [String: String]] {
        guard
            let url = bundle.url(forResource: "InterfaceStrings", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let raw = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else {
            return [:]
        }

        var mapped: [AppLanguage: [String: String]] = [:]
        for (code, entries) in raw {
            guard let language = AppLanguage.resolve(code: code) else { continue }
            mapped[language] = entries
        }
        return mapped
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("appLanguageDidChange")
}
