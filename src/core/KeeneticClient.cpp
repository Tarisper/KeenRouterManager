#include "KeeneticClient.h"

#include <QCryptographicHash>
#include <QEventLoop>
#include <QJsonArray>
#include <QNetworkCookieJar>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSet>
#include <QThread>
#include <QTimer>
#include <QUrl>
#include <optional>

namespace {
/**
 * @brief Normalize a router base URL to ensure consistent formatting.
 * This function trims whitespace, removes trailing slashes, and ensures the URL
 * starts with either "http://" or "https://" based on the preferHttps parameter.
 * It also handles cases where the URL might have multiple leading slashes.
 * @param value The input URL string to normalize
 * @param preferHttps Whether to prefer HTTPS when normalizing the URL
 * @return QString The normalized URL string
 */
QString normalizeUrl(QString value, bool preferHttps = false) {
    value = value.trimmed();
    while (value.endsWith('/')) {
        value.chop(1);
    }

    if (!value.startsWith("http://") && !value.startsWith("https://")) {
        value = (preferHttps ? "https://" : "http://") + value;
    }

    return value;
}

/**
 * @brief Extract the most relevant link state, falling back to the MWS (mesh) status when needed.
 * @param data JSON object with client data
 * @return Link state string (e.g., "up")
 */
QString sanitizeAddress(QString value) {
    value = value.trimmed();
    while (value.endsWith('/')) {
        value.chop(1);
    }
    return value;
}

/**
 * @brief Extract the most relevant link state, falling back to the MWS (mesh) status when needed.
 * @param data JSON object with client data
 * @return Link state string (e.g., "up")
 */
QString stripScheme(QString value, QString &scheme) {
    scheme.clear();
    const auto lower = value.toLower();
    if (lower.startsWith("https://")) {
        scheme = "https";
        value = value.mid(8);
    } else if (lower.startsWith("http://")) {
        scheme = "http";
        value = value.mid(7);
    }
    while (value.startsWith("//")) {
        value.remove(0, 1);
    }
    return value;
}

/**
 * @brief Extract the most relevant link state, falling back to the MWS (mesh) status when needed.
 * @param data JSON object with client data
 * @return Link state string (e.g., "up")
 */
QString stateFromClientData(const QJsonObject &data) {
    const auto link = data.value("link").toString();
    if (link == "up") {
        return link;
    }

    const auto mwsLink = data.value("mws").toObject().value("link").toString();
    return mwsLink;
}

/**
 * @brief Build a list of router applications from a JSON array response.
 * @param array JSON array with application objects
 * @return List of RouterApplication
 */
QList<RouterApplication> parseApplicationsArray(const QJsonArray &array) {
    QList<RouterApplication> result;
    for (const auto &entry : array) {
        if (!entry.isObject()) {
            continue;
        }

        const auto object = entry.toObject();
        RouterApplication app;
        app.name = object.value("name").toString();
        if (app.name.isEmpty()) {
            app.name = object.value("id").toString();
        }
        app.version = object.value("version").toString();

        if (object.contains("running")) {
            app.running = object.value("running").toBool(false);
        } else if (object.contains("enabled")) {
            app.running = object.value("enabled").toBool(false);
        } else if (object.contains("started")) {
            app.running = object.value("started").toBool(false);
        } else {
            const auto state = object.value("state").toString().toLower();
            app.running = (state == "running" || state == "started" || state == "up");
        }

        if (!app.name.isEmpty()) {
            result.append(app);
        }
    }

    return result;
}

/**
 * @brief Some router responses wrap application entries inside objects; this helper normalizes that.
 * @param object JSON object possibly containing application arrays
 * @return List of RouterApplication
 */
QList<RouterApplication> parseApplicationsObject(const QJsonObject &object) {
    QList<RouterApplication> result;

    if (object.contains("application") && object.value("application").isArray()) {
        return parseApplicationsArray(object.value("application").toArray());
    }

    if (object.contains("opkg") && object.value("opkg").isArray()) {
        return parseApplicationsArray(object.value("opkg").toArray());
    }

    for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
        if (!it.value().isObject()) {
            continue;
        }

        const auto appObject = it.value().toObject();
        RouterApplication app;
        app.name = appObject.value("name").toString(it.key());
        app.version = appObject.value("version").toString();

        if (appObject.contains("running")) {
            app.running = appObject.value("running").toBool(false);
        } else if (appObject.contains("enabled")) {
            app.running = appObject.value("enabled").toBool(false);
        } else if (appObject.contains("started")) {
            app.running = appObject.value("started").toBool(false);
        } else {
            const auto state = appObject.value("state").toString().toLower();
            app.running = (state == "running" || state == "started" || state == "up");
        }

        if (!app.name.isEmpty()) {
            result.append(app);
        }
    }

    return result;
}

/**
 * @brief Identify built-in services that do not represent user-installed apps.
 * @param name Application name
 * @return true if system app, false otherwise
 */
bool isSystemApplicationName(const QString &name) {
    static const QSet<QString> exact = {
        "base", "cloudcontrol", "corewireless", "monitor", "network", "storage",
        "trafficcontrol", "usb", "ndmp", "ndns", "mws", "ntce", "mdns", "igmp",
        "pppoe", "pingcheck", "snmp", "ssh", "web-cli", "wifi-system", "coredumps"
    };

    const auto value = name.toLower();
    if (exact.contains(value)) {
        return true;
    }

    return value.startsWith("lang-") || value.startsWith("nathelper-") || value.startsWith("opkg-");
}

/**
 * @brief Turn a simple key/bool JSON object into a map of service flags.
 * @param json JSON document with service flags
 * @return Map of service name to bool flag
 */
QMap<QString, bool> parseServiceMap(const QJsonDocument &json) {
    QMap<QString, bool> services;
    if (!json.isObject()) {
        return services;
    }

    const auto object = json.object();
    for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
        if (it.value().isBool()) {
            services.insert(it.key(), it.value().toBool(false));
        }
    }
    return services;
}

/**
 * @brief Split the raw version components string into an ordered list for display.
 * @param json JSON document with version components
 * @return List of version component strings
 */
QStringList parseVersionComponents(const QJsonDocument &json) {
    QStringList components;
    if (!json.isObject()) {
        return components;
    }

    const auto ndw = json.object().value("ndw").toObject();
    const auto raw = ndw.value("components").toString();
    for (const auto &entry : raw.split(',', Qt::SkipEmptyParts)) {
        const auto value = entry.trimmed();
        if (!value.isEmpty()) {
            components.append(value);
        }
    }

    return components;
}
} // namespace

/**
 * @brief Store the connection configuration and ensure the network manager can persist cookies.
 * @param baseUrl Router base URL
 * @param username Login username
 * @param password Login password
 * @param name Router name
 * @param requestTimeoutSec Request timeout in seconds
 * @param requestRetries Number of request retries
 * @param preferHttps Prefer HTTPS scheme
 */
KeeneticClient::KeeneticClient(QString baseUrl,
                               QString username,
                               QString password,
                               QString name,
                               int requestTimeoutSec,
                               int requestRetries,
                               bool preferHttps)
    : baseUrl_(),
      username_(std::move(username)),
      password_(std::move(password)),
      name_(std::move(name)),
      requestTimeoutSec_(qMax(1, requestTimeoutSec)),
      requestRetries_(qMax(1, requestRetries)),
      preferHttps_(preferHttps) {
    const auto sanitized = sanitizeAddress(std::move(baseUrl));
    baseWithoutScheme_ = stripScheme(sanitized, explicitScheme_);
    hasExplicitScheme_ = !explicitScheme_.isEmpty();
    const QString defaultScheme = hasExplicitScheme_ ? explicitScheme_ : (preferHttps_ ? QStringLiteral("https") : QStringLiteral("http"));
    baseUrl_ = buildBaseForScheme(defaultScheme);
    manager_.setCookieJar(new QNetworkCookieJar(&manager_));
}

/**
 * @brief Authenticate with the router using challenge-response (MD5+SHA256) or session reuse.
 * @return true if login successful, false otherwise
 */
bool KeeneticClient::login() {
    // Start with an unauthenticated /auth request to see if we already have a session.
    auto initial = request("auth");
    if (!initial.has_value()) {
        loggedIn_ = false;
        return false;
    }

    if (initial->statusCode == 200) {
        loggedIn_ = true;
        return true;
    }

    if (initial->statusCode != 401) {
        loggedIn_ = false;
        return false;
    }

    // When we get a 401, the router returns a realm/challenge pair for digest authentication.
    const auto realm = headerValue(*initial, "X-NDM-Realm");
    const auto challenge = headerValue(*initial, "X-NDM-Challenge");
    if (realm.isEmpty() || challenge.isEmpty()) {
        loggedIn_ = false;
        return false;
    }

    const auto md5Input = QString("%1:%2:%3").arg(username_, QString::fromUtf8(realm), password_).toUtf8();
    const auto md5Hash = QCryptographicHash::hash(md5Input, QCryptographicHash::Md5).toHex();
    const auto shaInput = challenge + md5Hash;
    const auto shaHash = QCryptographicHash::hash(shaInput, QCryptographicHash::Sha256).toHex();

    QJsonObject authBody;
    authBody["login"] = username_;
    authBody["password"] = QString::fromUtf8(shaHash);

    auto auth = request("auth", authBody, true);
    loggedIn_ = auth.has_value() && auth->statusCode == 200;
    return loggedIn_;
}

/**
 * @brief Get KeenDNS domains from the router.
 * @return List of KeenDNS domain strings
 */
QStringList KeeneticClient::getKeenDnsUrls() {
    if (!ensureLoggedIn()) {
        return {};
    }

    auto json = requestJson("rci/ip/http/ssl/acme/list/certificate");
    if (!json.has_value() || !json->isArray()) {
        return {};
    }

    QStringList urls;
    for (const auto &entry : json->array()) {
        const auto object = entry.toObject();
        const auto domain = object.value("domain").toString();
        if (!domain.isEmpty()) {
            urls.append(domain);
        }
    }
    return urls;
}

/**
 * @brief Get the local network IP address of the router.
 * @return Local IP address string
 */
QString KeeneticClient::getNetworkIp() {
    if (!ensureLoggedIn()) {
        return {};
    }

    auto json = requestJson("rci/sc/interface/Bridge0/ip/address");
    if (!json.has_value() || !json->isObject()) {
        return {};
    }

    return json->object().value("address").toString();
}

/**
 * @brief Collect a flattened set of router metadata by querying version/system/cloud endpoints.
 * @return Map of info keys to values (model, serial, firmware, etc.)
 */
QMap<QString, QString> KeeneticClient::getRouterInfo() {
    // Collect a flattened set of router metadata by querying version/system/cloud endpoints.
    QMap<QString, QString> info;
    if (!ensureLoggedIn()) {
        return info;
    }

    // Normalize scalars so we can compare values regardless of type.
    auto asString = [](const QJsonValue &value) -> QString {
        if (value.isString()) {
            return value.toString().trimmed();
        }
        if (value.isDouble()) {
            return QString::number(value.toDouble(), 'g', 12);
        }
        if (value.isBool()) {
            return value.toBool() ? "true" : "false";
        }
        return {};
    };

    // Resolve nested dot-separated keys from the JSON payloads.
    auto nestedValue = [](const QJsonObject &object, const QString &path) -> QJsonValue {
        const auto parts = path.split('.', Qt::SkipEmptyParts);
        if (parts.isEmpty()) {
            return {};
        }

        QJsonValue current = object.value(parts.first());
        for (int i = 1; i < parts.size(); ++i) {
            if (current.isObject()) {
                current = current.toObject().value(parts[i]);
            } else if (current.isArray()) {
                const auto array = current.toArray();
                if (array.isEmpty() || !array.first().isObject()) {
                    return {};
                }
                current = array.first().toObject().value(parts[i]);
            } else {
                return {};
            }
        }

        return current;
    };

    // Look through prioritized JSON blobs until one of the candidate keys yields text.
    auto pickFirst = [&](const QList<QJsonObject> &sources, const QStringList &paths) -> QString {
        for (const auto &source : sources) {
            for (const auto &path : paths) {
                const auto value = asString(nestedValue(source, path));
                if (!value.isEmpty()) {
                    return value;
                }
            }
        }
        return {};
    };

    auto addField = [&](const QString &key, const QString &value) {
        const auto trimmed = value.trimmed();
        if (!trimmed.isEmpty()) {
            info.insert(key, trimmed);
        }
    };

    QList<QJsonObject> versionSources;
    QList<QJsonObject> systemSources;
    QList<QJsonObject> cloudSources;

    if (const auto versionJson = requestJson("rci/show/version"); versionJson.has_value() && versionJson->isObject()) {
        const auto root = versionJson->object();
        versionSources.append(root);
        if (root.value("ndw").isObject()) {
            versionSources.append(root.value("ndw").toObject());
        }
        if (root.value("hw").isObject()) {
            versionSources.append(root.value("hw").toObject());
        }
    }

    if (const auto systemJson = requestJson("rci/show/system"); systemJson.has_value() && systemJson->isObject()) {
        const auto root = systemJson->object();
        systemSources.append(root);
        if (root.value("system").isObject()) {
            systemSources.append(root.value("system").toObject());
        }
        if (root.value("device").isObject()) {
            systemSources.append(root.value("device").toObject());
        }
    }

    if (const auto cloudJson = requestJson("rci/show/sc/cloud/status"); cloudJson.has_value() && cloudJson->isObject()) {
        const auto root = cloudJson->object();
        cloudSources.append(root);
        if (root.value("cloud").isObject()) {
            cloudSources.append(root.value("cloud").toObject());
        }
        if (root.value("status").isObject()) {
            cloudSources.append(root.value("status").toObject());
        }
    }

    if (const auto globalIpJson = requestJson("rci/show/ip/global"); globalIpJson.has_value() && globalIpJson->isObject()) {
        cloudSources.append(globalIpJson->object());
    }

    QList<QJsonObject> allSources = systemSources;
    allSources.append(versionSources);
    QList<QJsonObject> versionThenSystem = versionSources;
    versionThenSystem.append(systemSources);
    QList<QJsonObject> systemThenCloud = systemSources;
    systemThenCloud.append(cloudSources);
    QList<QJsonObject> cloudThenSystem = cloudSources;
    cloudThenSystem.append(systemSources);

    addField("model", pickFirst(allSources, {
        "model", "device.model", "name", "product", "hw.model", "ndw.model"
    }));

    addField("serial", pickFirst(allSources, {
        "serial", "serial-number", "serial_number", "sn", "device.serial", "hw.serial", "ndw.serial"
    }));

    addField("service_code", pickFirst(allSources, {
        "service-code", "service_code", "servicecode", "service.code", "device.service-code"
    }));

    QString firmware = pickFirst(versionThenSystem, {
        "version", "firmware", "firmware.version", "ndw.version", "release", "build"
    });
    const QString branch = pickFirst({versionSources}, {"branch", "ndw.branch", "channel"});
    if (!branch.isEmpty() && !firmware.contains(branch, Qt::CaseInsensitive)) {
        firmware = firmware.isEmpty() ? branch : QString("%1 (%2)").arg(firmware, branch);
    }
    addField("firmware", firmware);

    addField("domain", pickFirst(systemThenCloud, {
        "domain", "domain-name", "hostname", "host-name", "cloud.domain", "keen_dns", "name"
    }));

    const auto domains = getKeenDnsUrls();
    if (!domains.isEmpty()) {
        addField("domain", domains.first());
    }

    addField("ip_local", getNetworkIp());
    addField("ip_external", pickFirst(cloudThenSystem, {
        "address", "ip", "public-ip", "public_ip", "public.address", "wan.ip"
    }));

    addField("uptime", pickFirst(allSources, {
        "uptime", "up-time", "system.uptime"
    }));
    addField("hardware", pickFirst(versionThenSystem, {
        "platform", "board", "hw.revision", "revision", "cpu"
    }));

    return info;
}

/**
 * @brief Get available client policies from the router.
 * @return Map of policy key to description
 */
Policies KeeneticClient::getPolicies() {
    Policies policies;
    if (!ensureLoggedIn()) {
        return policies;
    }

    auto json = requestJson("rci/show/rc/ip/policy");
    if (!json.has_value() || !json->isObject()) {
        return policies;
    }

    const auto object = json->object();
    for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
        const auto policyInfo = it.value().toObject();
        const auto description = policyInfo.value("description").toString(it.key());
        policies.insert(it.key(), description);
    }

    return policies;
}

/**
 * @brief Get the list of online clients from the router.
 * @return List of OnlineClient
 */
QList<OnlineClient> KeeneticClient::getOnlineClients() {
    QList<OnlineClient> result;
    if (!ensureLoggedIn()) {
        return result;
    }

    auto clientsJson = requestJson("rci/show/ip/hotspot/host");
    if (!clientsJson.has_value() || !clientsJson->isArray()) {
        return result;
    }

    QMap<QString, OnlineClient> byMac;
    for (const auto &entry : clientsJson->array()) {
        const auto object = entry.toObject();
        const auto mac = object.value("mac").toString().toLower();
        if (mac.isEmpty()) {
            continue;
        }

        OnlineClient client;
        client.name = object.value("name").toString("Unknown");
        {
            QString ip = object.value("ip").toString();
            if (ip == "0.0.0.0" || ip.isEmpty()) {
                ip = "";
            }
            client.ip = ip;
        }
        client.mac = mac;
        client.rawData = object;
        client.online = stateFromClientData(object) == "up";
        byMac.insert(mac, client);
    }

    auto policyJson = requestJson("rci/show/rc/ip/hotspot/host");
    if (policyJson.has_value() && policyJson->isArray()) {
        for (const auto &entry : policyJson->array()) {
            const auto object = entry.toObject();
            const auto mac = object.value("mac").toString().toLower();
            if (mac.isEmpty()) {
                continue;
            }

            if (!byMac.contains(mac)) {
                OnlineClient client;
                client.mac = mac;
                byMac.insert(mac, client);
            }

            auto &client = byMac[mac];
            client.policy = object.value("policy").toString();
            client.access = object.value("access").toString("deny");
            client.permit = object.value("permit").toBool(false);
            client.deny = object.value("deny").toBool(false);
        }
    }

    for (const auto &client : byMac) {
        result.append(client);
    }

    return result;
}

/**
 * @brief Get the list of Wireguard peers from the router.
 * @return List of WireguardPeer
 */
QList<WireguardPeer> KeeneticClient::getWireguardPeers() {
    QList<WireguardPeer> result;
    if (!ensureLoggedIn()) {
        return result;
    }

    auto json = requestJson("rci/show/interface/Wireguard");
    if (!json.has_value() || !json->isObject()) {
        return result;
    }

    const auto wgObject = json->object();
    for (auto it = wgObject.constBegin(); it != wgObject.constEnd(); ++it) {
        const auto interfaceName = it.key();
        const auto interfaceObject = it.value().toObject();
        const auto peersObject = interfaceObject.value("peer").toObject();

        for (auto peerIt = peersObject.constBegin(); peerIt != peersObject.constEnd(); ++peerIt) {
            const auto peerName = peerIt.key();
            const auto peerObject = peerIt.value().toObject();

            WireguardPeer peer;
            peer.interfaceName = interfaceName;
            peer.peerName = peerName;
            peer.publicKey = peerObject.value("public-key").toString();
            result.append(peer);
        }
    }

    return result;
}

/**
 * @brief Get the list of installed applications/services on the router.
 * @param includeSystem Include system applications if true
 * @return List of RouterApplication
 */
QList<RouterApplication> KeeneticClient::getInstalledApplications(bool includeSystem) {
    QList<RouterApplication> result;
    if (!ensureLoggedIn()) {
        return result;
    }

    QMap<QString, bool> serviceStates;
    {
        auto json = requestJson("rci/show/rc/service");
        if (json.has_value()) {
            serviceStates = parseServiceMap(*json);
        }
    }
    if (serviceStates.isEmpty()) {
        auto json = requestJson("rci/show/sc/service");
        if (json.has_value()) {
            serviceStates = parseServiceMap(*json);
        }
    }

    QStringList components;
    {
        auto json = requestJson("rci/show/version");
        if (json.has_value()) {
            components = parseVersionComponents(*json);
        }
    }

    QSet<QString> allNames;
    for (auto it = serviceStates.constBegin(); it != serviceStates.constEnd(); ++it) {
        allNames.insert(it.key());
    }
    for (const auto &component : components) {
        allNames.insert(component);
    }

    for (const auto &name : allNames) {
        if (!includeSystem && isSystemApplicationName(name)) {
            continue;
        }

        RouterApplication app;
        app.name = name;
        app.controlName = name;
        app.version = components.contains(name) ? "component" : "service";
        app.manageable = true;

        if (serviceStates.contains(name)) {
            app.stateKnown = true;
            app.running = serviceStates.value(name);
        }

        result.append(app);
    }

    std::sort(result.begin(), result.end(), [](const RouterApplication &a, const RouterApplication &b) {
        return a.name.toLower() < b.name.toLower();
    });

    if (!result.isEmpty()) {
        return result;
    }

    const QStringList endpoints = {
        "rci/show/app/opkg",
        "rci/show/app/application",
        "rci/show/app",
        "rci/show/sc/service",
        "rci/show/rc/service"
    };

    for (const auto &endpoint : endpoints) {
        auto json = requestJson(endpoint);
        if (!json.has_value()) {
            continue;
        }

        if (json->isArray()) {
            result = parseApplicationsArray(json->array());
        } else if (json->isObject()) {
            const auto object = json->object();
            bool allBoolValues = !object.isEmpty();
            for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
                if (!it.value().isBool()) {
                    allBoolValues = false;
                    break;
                }
            }

            if (allBoolValues) {
                for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
                    RouterApplication app;
                    app.name = it.key();
                    app.version = "service";
                    app.running = it.value().toBool(false);
                    result.append(app);
                }
            } else {
                result = parseApplicationsObject(object);
            }
        }

        if (!result.isEmpty()) {
            if (!includeSystem) {
                QList<RouterApplication> filtered;
                for (const auto &app : result) {
                    if (!isSystemApplicationName(app.name)) {
                        filtered.append(app);
                    }
                }
                result = filtered;
            }
            return result;
        }
    }

    return result;
}

/**
 * @brief Start or stop an application/service on the router.
 * @param applicationName Name of the application
 * @param running true to start, false to stop
 * @return true if operation succeeded
 */
bool KeeneticClient::setApplicationRunning(const QString &applicationName, bool running) {
    if (!ensureLoggedIn() || applicationName.trimmed().isEmpty()) {
        return false;
    }

    struct RequestVariant {
        QString endpoint;
        QJsonObject payload;
    };

    QList<RequestVariant> variants;
    variants.append({"rci/service", QJsonObject{{applicationName, running}}});
    variants.append({"rci/app/opkg", QJsonObject{{"name", applicationName}, {"started", running}}});
    variants.append({"rci/app/opkg", QJsonObject{{"name", applicationName}, {"running", running}}});
    variants.append({"rci/app/opkg", QJsonObject{{"name", applicationName}, {"action", running ? "start" : "stop"}}});
    variants.append({"rci/app/application", QJsonObject{{"name", applicationName}, {"started", running}}});
    variants.append({"rci/app/application", QJsonObject{{"name", applicationName}, {"action", running ? "start" : "stop"}}});
    variants.append({"rci/app", QJsonObject{{"name", applicationName}, {"started", running}}});

    auto readServiceState = [&](const QString &endpoint, const QString &name) -> std::optional<bool> {
        auto stateJson = requestJson(endpoint);
        if (!stateJson.has_value() || !stateJson->isObject()) {
            return std::nullopt;
        }

        const auto object = stateJson->object();
        if (!object.contains(name)) {
            return std::nullopt;
        }

        return object.value(name).toBool(false);
    };

    auto isStateConfirmed = [&](const QString &name, bool expectedRunning) {
        for (int attempt = 0; attempt < 24; ++attempt) {
            const auto rcState = readServiceState("rci/show/rc/service", name);
            const auto scState = readServiceState("rci/show/sc/service", name);

            if (expectedRunning) {
                if ((rcState.has_value() && rcState.value()) || (scState.has_value() && scState.value())) {
                    return true;
                }
            } else {
                const bool rcStopped = !rcState.has_value() || !rcState.value();
                const bool scStopped = !scState.has_value() || !scState.value();
                if (rcStopped && scStopped) {
                    return true;
                }
            }

            QThread::msleep(250);
        }

        return false;
    };

    bool serviceRouteTried = false;
    bool serviceRouteConfirmed = false;

    for (const auto &variant : variants) {
        auto response = request(variant.endpoint, variant.payload, true);
        if (response.has_value() && response->statusCode >= 200 && response->statusCode < 300) {
            if (variant.endpoint == "rci/service") {
                serviceRouteTried = true;
                if (isStateConfirmed(applicationName, running)) {
                    serviceRouteConfirmed = true;
                    return true;
                }
            } else {
                if (serviceRouteTried && !serviceRouteConfirmed) {
                    continue;
                }
                return true;
            }
        }
    }

    if (serviceRouteTried && !serviceRouteConfirmed) {
        return false;
    }

    return false;
}

/**
 * @brief Apply a policy to a client by MAC address.
 * @param mac Client MAC address
 * @param policy Policy key (empty for default)
 * @return true if operation succeeded
 */
bool KeeneticClient::applyPolicyToClient(const QString &mac, const QString &policy) {
    if (!ensureLoggedIn()) {
        return false;
    }

    QJsonObject body;
    body["mac"] = mac;
    body["permit"] = true;
    body["schedule"] = false;
    body["deny"] = false;
    if (policy.isEmpty()) {
        body["policy"] = false;
    } else {
        body["policy"] = policy;
    }

    auto response = request("rci/ip/hotspot/host", body, true);
    return response.has_value() && response->statusCode == 200;
}

/**
 * @brief Block a client by MAC address.
 * @param mac Client MAC address
 * @return true if operation succeeded
 */
bool KeeneticClient::setClientBlock(const QString &mac) {
    if (!ensureLoggedIn()) {
        return false;
    }

    QJsonObject body;
    body["mac"] = mac;
    body["schedule"] = false;
    body["deny"] = true;

    auto response = request("rci/ip/hotspot/host", body, true);
    return response.has_value() && response->statusCode == 200;
}

/**
 * @brief Send a Wake-on-LAN packet to a client.
 * @param mac Client MAC address
 * @param message Optional pointer to receive status message
 * @return true if WoL sent successfully
 */
bool KeeneticClient::wakeOnLan(const QString &mac, QString *message) {
    if (!ensureLoggedIn()) {
        if (message != nullptr) {
            *message = "Authentication failed";
        }
        return false;
    }

    QJsonObject body;
    body["mac"] = mac;

    auto response = request("rci/ip/hotspot/wake", body, true);
    if (!response.has_value() || response->statusCode != 200) {
        if (message != nullptr) {
            *message = "Request failed";
        }
        return false;
    }

    const auto json = QJsonDocument::fromJson(response->body);
    if (json.isObject()) {
        const auto statusArray = json.object().value("status").toArray();
        if (!statusArray.isEmpty()) {
            const auto first = statusArray.first().toObject();
            const auto text = first.value("message").toString();
            if (!text.isEmpty() && message != nullptr) {
                *message = text;
            }
        }
    }

    if (message != nullptr && message->isEmpty()) {
        *message = "WoL sent successfully";
    }

    return true;
}

/**
 * @brief Normalize a base URL (static helper).
 * @param value Input URL string
 * @return Normalized URL string
 */
QString KeeneticClient::normalizedBaseUrl(const QString &value) const {
    return normalizeUrl(value);
}

/**
 * @brief Get a header value from an HTTP response (case-insensitive).
 * @param response HTTP response
 * @param name Header name
 * @return Header value as QByteArray
 */
QByteArray KeeneticClient::headerValue(const HttpResponse &response, const QByteArray &name) const {
    const auto target = name.toLower();
    for (const auto &[headerName, headerValue] : response.headers) {
        if (headerName.toLower() == target) {
            return headerValue;
        }
    }
    return {};
}

/**
 * @brief Ensure the client is authenticated (login if needed).
 * @return true if authenticated
 */
bool KeeneticClient::ensureLoggedIn() {
    if (loggedIn_) {
        return true;
    }
    return login();
}

/**
 * @brief Perform an HTTP request to the router, trying all scheme candidates.
 * @param endpoint API endpoint
 * @param data JSON body (for POST)
 * @param isPost true for POST, false for GET
 * @return Optional HttpResponse
 */
std::optional<KeeneticClient::HttpResponse> KeeneticClient::request(const QString &endpoint, const QJsonObject &data, bool isPost) {
    for (const auto &scheme : schemeCandidates()) {
        const auto candidateBase = buildBaseForScheme(scheme);
        auto response = requestWithBase(candidateBase, endpoint, data, isPost);
        if (response.has_value()) {
            baseUrl_ = candidateBase;
            return response;
        }
    }

    return std::nullopt;
}

/**
 * @brief Perform an HTTP request and parse the response as JSON.
 * @param endpoint API endpoint
 * @param data JSON body (for POST)
 * @param isPost true for POST, false for GET
 * @return Optional QJsonDocument
 */
std::optional<QJsonDocument> KeeneticClient::requestJson(const QString &endpoint, const QJsonObject &data, bool isPost) {
    auto response = request(endpoint, data, isPost);
    if (!response.has_value()) {
        return std::nullopt;
    }

    if (response->statusCode < 200 || response->statusCode >= 300) {
        return std::nullopt;
    }

    const auto json = QJsonDocument::fromJson(response->body);
    if (json.isNull()) {
        return std::nullopt;
    }

    return json;
}

/**
 * @brief Build a base URL for a given scheme (http/https).
 * @param scheme Scheme string
 * @return Base URL string
 */
QString KeeneticClient::buildBaseForScheme(const QString &scheme) const {
    if (baseWithoutScheme_.isEmpty()) {
        return QStringLiteral("%1://").arg(scheme);
    }
    return QStringLiteral("%1://%2").arg(scheme, baseWithoutScheme_);
}

/**
 * @brief Get the list of scheme candidates to try (http/https).
 * @return List of scheme strings
 */
QStringList KeeneticClient::schemeCandidates() const {
    if (hasExplicitScheme_) {
        if (preferHttps_ && explicitScheme_.compare("https", Qt::CaseInsensitive) != 0) {
            return {QStringLiteral("https"), explicitScheme_};
        }
        return {explicitScheme_};
    }

    if (preferHttps_) {
        return {QStringLiteral("https"), QStringLiteral("http")};
    }
    return {QStringLiteral("http"), QStringLiteral("https")};
}

/**
 * @brief Perform an HTTP request using a specific base URL.
 * @param base Base URL
 * @param endpoint API endpoint
 * @param data JSON body (for POST)
 * @param isPost true for POST, false for GET
 * @return Optional HttpResponse
 */
std::optional<KeeneticClient::HttpResponse> KeeneticClient::requestWithBase(const QString &base, const QString &endpoint, const QJsonObject &data, bool isPost) {
    if (base.isEmpty()) {
        return std::nullopt;
    }

    const auto url = QUrl(base + "/" + endpoint);
    if (!url.isValid()) {
        return std::nullopt;
    }

    for (int attempt = 0; attempt < requestRetries_; ++attempt) {
        QNetworkRequest request(url);
        QNetworkReply *reply = nullptr;

        if (isPost) {
            request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
            const auto payload = QJsonDocument(data).toJson(QJsonDocument::Compact);
            reply = manager_.post(request, payload);
        } else {
            reply = manager_.get(request);
        }

        QEventLoop loop;
        QTimer timeout;
        timeout.setSingleShot(true);

        QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
        QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);

        timeout.start(requestTimeoutSec_ * 1000);
        loop.exec();

        if (!timeout.isActive()) {
            reply->abort();
            reply->deleteLater();
            continue;
        }

        const auto error = reply->error();

        HttpResponse response;
        response.statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        response.body = reply->readAll();

        const auto headers = reply->rawHeaderPairs();
        for (const auto &header : headers) {
            response.headers.append(header);
        }

        reply->deleteLater();

        if (error != QNetworkReply::NoError && attempt + 1 < requestRetries_) {
            continue;
        }

        return response;
    }

    return std::nullopt;
}
