#pragma once

#include <QJsonObject>
#include <QMap>
#include <QString>
#include <QStringList>

struct RouterInfo {
    QString name;
    QString address;
    QString login;
    QString password;
    QString networkIp;
    QStringList keenDnsUrls;
};

struct AppSettings {
    int requestTimeoutSec{5};
    int requestRetries{1};
    bool preferHttps{false};
    QString uiLanguage{"en"};
    QMap<QString, int> tableSortColumns;
    QMap<QString, int> tableSortOrders;
};

struct OnlineClient {
    QString name{"Unknown"};
    QString ip{"N/A"};
    QString mac;
    QString policy;
    QString access{"deny"};
    bool permit{false};
    bool deny{false};
    bool online{false};
    QJsonObject rawData;
};

struct WireguardPeer {
    QString interfaceName;
    QString peerName;
    QString publicKey;
};

struct RouterApplication {
    QString name;
    QString version;
    bool running{false};
    bool stateKnown{false};
    bool manageable{true};
    QString controlName;
};

using Policies = QMap<QString, QString>;
