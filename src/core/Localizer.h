#pragma once

#include <QMap>
#include <QString>
#include <QStringList>

class Localizer {
public:
    static Localizer &instance();

    bool loadLanguagePacks(const QString &filePath);
    void setLanguage(const QString &languageCode);

    QString currentLanguage() const;
    QStringList availableLanguages() const;
    QString text(const QString &key, const QString &fallback = QString()) const;

    static QString detectLanguagePacksPath();

private:
    Localizer() = default;

    QMap<QString, QMap<QString, QString>> packs_;
    QString currentLanguage_{"en"};
};
