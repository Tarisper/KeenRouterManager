#include "Localizer.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>

/// Returns the shared localizer instance.
Localizer &Localizer::instance() {
    static Localizer localizer;
    return localizer;
}

namespace {
QMap<QString, QString> mapFromObject(const QJsonObject &object) {
    QMap<QString, QString> result;
    for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
        result.insert(it.key(), it.value().toString());
    }
    return result;
}

QString selectLanguage(const QMap<QString, QMap<QString, QString>> &packs, const QString &current) {
    if (packs.contains(current)) {
        return current;
    }
    if (packs.contains("en")) {
        return "en";
    }
    return packs.isEmpty() ? QString{} : packs.firstKey();
}
} // namespace

/// Loads language definitions from the provided JSON path.
bool Localizer::loadLanguagePacks(const QString &filePath) {
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        return false;
    }

    const auto json = QJsonDocument::fromJson(file.readAll());
    if (!json.isObject()) {
        return false;
    }

    QMap<QString, QMap<QString, QString>> loaded;
    const auto root = json.object();
    for (auto langIt = root.constBegin(); langIt != root.constEnd(); ++langIt) {
        if (!langIt.value().isObject()) {
            continue;
        }

        const auto entries = mapFromObject(langIt.value().toObject());
        if (!entries.isEmpty()) {
            loaded.insert(langIt.key(), entries);
        }
    }

    if (loaded.isEmpty()) {
        return false;
    }

    packs_ = std::move(loaded);
    currentLanguage_ = selectLanguage(packs_, currentLanguage_);

    return true;
}

/// Switches the active language if it exists in packs.
void Localizer::setLanguage(const QString &languageCode) {
    if (packs_.contains(languageCode)) {
        currentLanguage_ = languageCode;
    }
}

/// Returns the currently active language code.
QString Localizer::currentLanguage() const {
    return currentLanguage_;
}

/// Lists all languages present in the loaded packs.
QStringList Localizer::availableLanguages() const {
    return packs_.keys();
}

/// Retrieves localized text for the given key with fallback.
QString Localizer::text(const QString &key, const QString &fallback) const {
    const auto lookup = [this, &key](const QString &lang) {
        if (packs_.contains(lang)) {
            const auto &langMap = packs_[lang];
            return langMap.value(key, {});
        }
        return QString{};
    };

    const QString primary = lookup(currentLanguage_);
    const QString result = primary.isEmpty() ? lookup("en") : primary;
    if (!result.isEmpty()) {
        return result;
    }
    return fallback.isEmpty() ? key : fallback;
}

/// Detects where the current build stores the language pack JSON.
QString Localizer::detectLanguagePacksPath() {
    const auto appDir = QCoreApplication::applicationDirPath();
    const QStringList candidates = {
        QDir(appDir).absoluteFilePath("../Resources/language_packs.json"),
        QDir(appDir).absoluteFilePath("language_packs.json"),
        QDir(QDir::currentPath()).absoluteFilePath("resources/language_packs.json"),
        QDir(QDir::currentPath()).absoluteFilePath("../resources/language_packs.json")
    };

    for (const auto &path : candidates) {
        if (QFile::exists(path)) {
            return path;
        }
    }

    return {};
}
