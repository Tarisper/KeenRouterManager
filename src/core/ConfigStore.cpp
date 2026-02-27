#include "ConfigStore.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

namespace {
QString configDirPath() {
    QString base = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    if (base.isEmpty()) {
        base = QDir::homePath() + "/.config/KeenRouterManager";
    }

    QDir dir(base);
    if (!dir.exists()) {
        dir.mkpath(".");
    }

    return dir.absolutePath();
}

QString configFilePath() {
    return configDirPath() + "/routers.json";
}

QString settingsFilePath() {
    return configDirPath() + "/settings.json";
}

QJsonObject routerToJson(const RouterInfo &router) {
    QJsonObject object;
    object["name"] = router.name;
    object["address"] = router.address;
    object["login"] = router.login;
    object["password"] = router.password;
    object["network_ip"] = router.networkIp;

    QJsonArray urls;
    for (const auto &url : router.keenDnsUrls) {
        urls.append(url);
    }
    object["keendns_urls"] = urls;
    return object;
}

RouterInfo jsonToRouter(const QJsonObject &object) {
    RouterInfo router;
    router.name = object.value("name").toString();
    router.address = object.value("address").toString();
    router.login = object.value("login").toString();
    router.password = object.value("password").toString();
    router.networkIp = object.value("network_ip").toString();

    const auto urls = object.value("keendns_urls").toArray();
    for (const auto &value : urls) {
        router.keenDnsUrls.append(value.toString());
    }

    return router;
}

QJsonArray routersToJsonArray(const QList<RouterInfo> &routers) {
    QJsonArray array;
    for (const auto &router : routers) {
        array.append(routerToJson(router));
    }
    return array;
}

QList<RouterInfo> routersFromJsonArray(const QJsonArray &array) {
    QList<RouterInfo> routers;
    for (const auto &entry : array) {
        if (entry.isObject()) {
            routers.append(jsonToRouter(entry.toObject()));
        }
    }
    return routers;
}

QJsonObject appSettingsToJson(const AppSettings &settings) {
    QJsonObject object;
    object["request_timeout_sec"] = settings.requestTimeoutSec;
    object["request_retries"] = settings.requestRetries;
    object["prefer_https"] = settings.preferHttps;
    object["ui_language"] = settings.uiLanguage;

    QJsonObject tableSort;
    for (auto it = settings.tableSortColumns.constBegin(); it != settings.tableSortColumns.constEnd(); ++it) {
        QJsonObject entry;
        entry["column"] = it.value();
        entry["order"] = settings.tableSortOrders.value(it.key(), 0);
        tableSort[it.key()] = entry;
    }
    object["table_sort"] = tableSort;

    return object;
}

AppSettings jsonToAppSettings(const QJsonObject &object) {
    AppSettings settings;
    settings.requestTimeoutSec = qMax(1, object.value("request_timeout_sec").toInt(settings.requestTimeoutSec));
    settings.requestRetries = qMax(1, object.value("request_retries").toInt(settings.requestRetries));
    settings.preferHttps = object.value("prefer_https").toBool(settings.preferHttps);
    settings.uiLanguage = object.value("ui_language").toString(settings.uiLanguage);
    if (settings.uiLanguage != "ru" && settings.uiLanguage != "en") {
        settings.uiLanguage = "en";
    }

    const auto tableSort = object.value("table_sort").toObject();
    for (auto it = tableSort.constBegin(); it != tableSort.constEnd(); ++it) {
        if (!it.value().isObject()) {
            continue;
        }

        const auto entry = it.value().toObject();
        const int column = entry.value("column").toInt(-1);
        const int order = entry.value("order").toInt(0);
        if (column < 0) {
            continue;
        }

        settings.tableSortColumns[it.key()] = column;
        settings.tableSortOrders[it.key()] = (order == 1 ? 1 : 0);
    }

    return settings;
}
} // namespace

QList<RouterInfo> ConfigStore::loadRouters() {
    QList<RouterInfo> routers;
    QFile file(configFilePath());
    if (!file.exists()) {
        return routers;
    }

    if (!file.open(QIODevice::ReadOnly)) {
        return routers;
    }

    const auto document = QJsonDocument::fromJson(file.readAll());
    if (!document.isArray()) {
        return routers;
    }

    for (const auto &entry : document.array()) {
        if (entry.isObject()) {
            routers.append(jsonToRouter(entry.toObject()));
        }
    }

    return routers;
}

bool ConfigStore::saveRouters(const QList<RouterInfo> &routers) {
    QFile file(configFilePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }

    const auto document = QJsonDocument(routersToJsonArray(routers));
    file.write(document.toJson(QJsonDocument::Indented));
    return true;
}

QList<RouterInfo> ConfigStore::importRoutersFromFile(const QString &filePath, bool *ok) {
    if (ok != nullptr) {
        *ok = false;
    }

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }

    const auto document = QJsonDocument::fromJson(file.readAll());
    if (!document.isArray()) {
        return {};
    }

    if (ok != nullptr) {
        *ok = true;
    }
    return routersFromJsonArray(document.array());
}

bool ConfigStore::exportRoutersToFile(const QList<RouterInfo> &routers, const QString &filePath) {
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }

    const auto document = QJsonDocument(routersToJsonArray(routers));
    file.write(document.toJson(QJsonDocument::Indented));
    return true;
}

AppSettings ConfigStore::loadAppSettings() {
    QFile file(settingsFilePath());
    if (!file.exists() || !file.open(QIODevice::ReadOnly)) {
        return {};
    }

    const auto document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject()) {
        return {};
    }

    return jsonToAppSettings(document.object());
}

bool ConfigStore::saveAppSettings(const AppSettings &settings) {
    QFile file(settingsFilePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }

    const auto document = QJsonDocument(appSettingsToJson(settings));
    file.write(document.toJson(QJsonDocument::Indented));
    return true;
}
