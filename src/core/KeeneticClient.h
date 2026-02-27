#pragma once

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QString>
#include <QStringList>
#include <optional>

#include "Models.h"

class KeeneticClient {
public:
    KeeneticClient(QString baseUrl,
                   QString username,
                   QString password,
                   QString name,
                   int requestTimeoutSec = 5,
                   int requestRetries = 1,
                   bool preferHttps = false);

    bool login();

    QStringList getKeenDnsUrls();
    QString getNetworkIp();
    QMap<QString, QString> getRouterInfo();
    Policies getPolicies();
    QList<OnlineClient> getOnlineClients();
    QList<WireguardPeer> getWireguardPeers();
    QList<RouterApplication> getInstalledApplications(bool includeSystem = false);
    bool setApplicationRunning(const QString &applicationName, bool running);

    bool applyPolicyToClient(const QString &mac, const QString &policy);
    bool setClientBlock(const QString &mac);
    bool wakeOnLan(const QString &mac, QString *message = nullptr);

    const QString &baseUrl() const { return baseUrl_; }

private:
    struct HttpResponse {
        int statusCode{0};
        QByteArray body;
        QList<QPair<QByteArray, QByteArray>> headers;
    };

    QString normalizedBaseUrl(const QString &value) const;
    QString buildBaseForScheme(const QString &scheme) const;
    QStringList schemeCandidates() const;
    std::optional<HttpResponse> requestWithBase(const QString &base, const QString &endpoint, const QJsonObject &data, bool isPost);
    QByteArray headerValue(const HttpResponse &response, const QByteArray &name) const;

    bool ensureLoggedIn();
    std::optional<HttpResponse> request(const QString &endpoint, const QJsonObject &data = {}, bool isPost = false);
    std::optional<QJsonDocument> requestJson(const QString &endpoint, const QJsonObject &data = {}, bool isPost = false);

    QString baseUrl_;
    QString username_;
    QString password_;
    QString name_;

    QString baseWithoutScheme_;
    QString explicitScheme_;
    bool hasExplicitScheme_ = false;
    bool preferHttps_ = false;

    bool loggedIn_{false};
    int requestTimeoutSec_{5};
    int requestRetries_{1};
    QNetworkAccessManager manager_;
};
