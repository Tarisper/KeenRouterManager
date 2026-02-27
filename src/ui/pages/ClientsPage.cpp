#include "ClientsPage.h"

#include "../../core/Localizer.h"
#include "../Icons.h"

#include <QHeaderView>
#include <QHBoxLayout>
#include <QJsonArray>
#include <QJsonValue>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QSize>
#include <QTableWidget>
#include <QTableWidgetItem>
#include <QVBoxLayout>
#include <cmath>
#include <QStyledItemDelegate>

namespace {
bool containsFilter(const OnlineClient &client, const QString &filter) {
    if (filter.isEmpty()) {
        return true;
    }

    const auto text = filter.toLower();
    return client.name.toLower().contains(text) ||
           client.ip.toLower().contains(text) ||
           client.mac.toLower().contains(text);
}

QList<OnlineClient> sortedClients(const QList<OnlineClient> &clients) {
    QList<OnlineClient> copy = clients;
    std::sort(copy.begin(), copy.end(), [](const OnlineClient &a, const OnlineClient &b) {
        if (a.online != b.online) {
            return a.online > b.online;
        }

        return a.name.toLower() < b.name.toLower();
    });

    return copy;
}

QTableWidgetItem *makeStateItem(QWidget *owner, bool online) {
    const auto &localizer = Localizer::instance();
    auto *item = new QTableWidgetItem(localizer.text(online ? "status.online" : "status.offline",
                                                     online ? "Online" : "Offline"));
    item->setIcon(online ? Icons::statusOnlineIcon(owner) : Icons::statusOfflineIcon(owner));
    item->setForeground(online ? QColor(34, 125, 74) : QColor(160, 69, 63));
    return item;
}
QString valueToString(const QJsonValue &value) {
    if (value.isString()) {
        return value.toString();
    }
    if (value.isBool()) {
        return value.toBool() ? "1" : "0";
    }
    if (value.isDouble()) {
        const auto number = value.toDouble();
        if (std::floor(number) == number) {
            return QString::number(static_cast<long long>(number));
        }
        return QString::number(number);
    }
    return {};
}

QString pickSegment(const OnlineClient &client) {
    const auto &raw = client.rawData;
    QString segment = raw.value("segment").toString();
    if (segment.isEmpty()) {
        segment = raw.value("segment_name").toString();
    }
    if (segment.isEmpty()) {
        segment = raw.value("segmentName").toString();
    }

    const auto data = raw.value("data").toObject();
    if (segment.isEmpty()) {
        segment = data.value("segment").toString();
    }
    if (segment.isEmpty()) {
        segment = data.value("segment_name").toString();
    }
    if (segment.isEmpty()) {
        segment = data.value("segmentName").toString();
    }

    if (segment.isEmpty()) {
        segment = Localizer::instance().text("clients.network.default", "Home network");
    }

    return segment;
}

QString supportSuffix(const QJsonValue &value) {
    if (value.isUndefined() || value.isNull()) {
        return {};
    }
    if (value.isArray()) {
        QStringList parts;
        for (const auto &entry : value.toArray()) {
            const auto normalized = valueToString(entry);
            if (!normalized.isEmpty()) {
                parts << normalized;
            }
        }
        if (parts.isEmpty()) {
            return {};
        }
        return "/" + parts.join("/");
    }
    const auto text = valueToString(value);
    if (text.isEmpty()) {
        return {};
    }
    return "/" + text;
}

QString wifiBandLabel(const QString &ap) {
    const auto lower = ap.toLower();
    if (lower.contains("wifimaster0") || lower.contains("wifi0")) {
        return "2.4 GHz";
    }
    if (lower.contains("wifimaster1") || lower.contains("wifi1")) {
        return "5 GHz";
    }
    if (lower.contains("wifimaster2") || lower.contains("wifi2")) {
        return "6 GHz";
    }
    return {};
}

struct ConnectionDetails {
    QString segment;
    QString connection;
    QString speed;
    QString info;
};

ConnectionDetails describeConnection(const OnlineClient &client) {
    const auto &localizer = Localizer::instance();
    const auto root = client.rawData;
    const auto explicitData = root.value("data").toObject();
    const auto data = explicitData.isEmpty() ? root : explicitData;
    const auto mws = data.value("mws").toObject();
    auto pickValue = [&](const QString &key) -> QJsonValue {
        if (data.contains(key)) {
            return data.value(key);
        }
        if (mws.contains(key)) {
            return mws.value(key);
        }
        if (root.contains(key) && root.value(key) != data.value(key)) {
            return root.value(key);
        }
        return {};
    };

    auto pickString = [&](const QString &key) {
        return valueToString(pickValue(key));
    };

    auto pickFirstString = [&](const QList<QString> &keys) {
        for (const auto &key : keys) {
            const auto text = pickString(key);
            if (!text.isEmpty()) {
                return text;
            }
        }
        return QString{};
    };

    const QString segment = pickSegment(client);
    const QString ap = pickString("ap");
    const bool isWireless = !ap.isEmpty();
    const QString connection = isWireless
        ? (wifiBandLabel(ap).isEmpty()
               ? localizer.text("clients.connection.wifi.default", "Wi-Fi")
               : localizer.text("clients.connection.wifi", "Wi-Fi %1").arg(wifiBandLabel(ap)))
        : localizer.text("clients.connection.wired", "Wired");

    const QString speedUnit = localizer.text("clients.speed.unit", "Mbit/s");
    const QString frequencyUnit = localizer.text("clients.frequency.unit", "MHz");
    QString speedLine;
    QString infoLine;

    if (isWireless) {
        const QString txRate = pickFirstString({"txrate", "rate", "link_speed", "tx_rate", "linkRate"});
        speedLine = txRate.isEmpty()
            ? localizer.text("clients.speed.unknown", "N/A")
            : QString("%1 %2").arg(txRate, speedUnit);

        const QString security = pickString("security");
        if (!security.isEmpty()) {
            speedLine += " " + security;
        }

        QString detail;
        const QString mode = pickString("mode");
        if (!mode.isEmpty()) {
            detail = mode;
        }

        const QString support = supportSuffix(pickValue("_11"));
        if (!support.isEmpty()) {
            detail += support;
        }

        const QString txss = pickString("txss");
        if (!txss.isEmpty()) {
            if (!detail.isEmpty()) {
                detail += " ";
            }
            detail += QString("%1x%1").arg(txss);
        }

        const QString ht = pickString("ht");
        if (!ht.isEmpty()) {
            if (!detail.isEmpty()) {
                detail += " ";
            }
            detail += QString("%1 %2").arg(ht, frequencyUnit);
        }

        infoLine = detail;
    } else {
        const QString wiredSpeed = pickFirstString({"speed", "link_speed", "rate", "linkRate"});
        speedLine = wiredSpeed.isEmpty()
            ? localizer.text("clients.speed.unknown", "N/A")
            : QString("%1 %2").arg(wiredSpeed, speedUnit);

        const QString port = pickString("port");
        if (!port.isEmpty()) {
            infoLine = localizer.text("clients.speed.port", "Port %1").arg(port);
        }
    }

    return {segment, connection, speedLine, infoLine};
}
} // namespace

/**
 * @brief Delegate to disable text elision (truncation)
 * 
 */
class NoElideDelegate : public QStyledItemDelegate {
public:
    using QStyledItemDelegate::QStyledItemDelegate;
    void paint(QPainter *painter, const QStyleOptionViewItem &option, const QModelIndex &index) const override {
        QStyleOptionViewItem opt(option);
        opt.textElideMode = Qt::ElideNone;
        QStyledItemDelegate::paint(painter, opt, index);
    }
};

/**
 * @brief Check if the client matches the filter string (name, IP, or MAC).
 * @param client OnlineClient to check
 * @param filter Filter string
 * @return true if matches, false otherwise
 */
ClientsPage::ClientsPage(QWidget *parent)
    : QWidget(parent),
      searchEdit_(new QLineEdit(this)),
      refreshButton_(new QPushButton(Localizer::instance().text("main.refresh", "Refresh"), this)),
      table_(new QTableWidget(this)) {
    searchEdit_->setPlaceholderText(Localizer::instance().text("search.placeholder", "Search by name, IP or MAC"));

    table_->setColumnCount(8);
    table_->setHorizontalHeaderLabels({
        Localizer::instance().text("table.state", "State"),
        Localizer::instance().text("table.name", "Name"),
        Localizer::instance().text("table.ip", "IP"),
        Localizer::instance().text("table.mac", "MAC"),
        Localizer::instance().text("table.network", "Network"),
        Localizer::instance().text("table.speed", "Speed"),
        Localizer::instance().text("table.policy", "Policy"),
        Localizer::instance().text("table.wol", "Wake-on-LAN")
    });
    table_->horizontalHeader()->setSectionResizeMode(QHeaderView::Interactive);
    table_->verticalHeader()->setVisible(false);
    table_->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table_->setShowGrid(false);
    table_->setAlternatingRowColors(true);
    table_->setWordWrap(true);
    table_->resizeRowsToContents();
    table_->setSelectionBehavior(QAbstractItemView::SelectRows);
    table_->setSelectionMode(QAbstractItemView::SingleSelection);
    table_->setSortingEnabled(true);
    // Auto-resize columns to fit contents
    table_->resizeColumnsToContents();
    table_->horizontalHeader()->setSortIndicatorShown(true);
    table_->setIconSize(QSize(16, 16));
    refreshButton_->setAutoDefault(false);
    refreshButton_->setIcon(Icons::refreshIcon(this));
    refreshButton_->setIconSize(QSize(16, 16));

    auto *controls = new QHBoxLayout;
    controls->setSpacing(8);
    controls->addWidget(refreshButton_);
    controls->addWidget(searchEdit_);

    auto *root = new QVBoxLayout(this);
    root->setContentsMargins(8, 6, 8, 8);
    root->setSpacing(8);
    root->addLayout(controls);
    root->addWidget(table_);
    setLayout(root);

    connect(table_->horizontalHeader(), &QHeaderView::sortIndicatorChanged, this, [this](int column, Qt::SortOrder order) {
        Q_EMIT tableSortChanged(column, order);
    });

    connect(refreshButton_, &QPushButton::clicked, this, [this]() { refresh(); });
    connect(searchEdit_, &QLineEdit::textChanged, this, [this]() { render(); });
}

/**
 * @brief Set the router and client context for the page.
 * @param router RouterInfo
 * @param client KeeneticClient shared pointer
 */
void ClientsPage::setContext(const RouterInfo &router, const std::shared_ptr<KeeneticClient> &client) {
    router_ = router;
    client_ = client;
}

/**
 * @brief Refresh the clients list from the router and update the table.
 */
void ClientsPage::refresh() {
    if (!client_) {
        clients_.clear();
        render();
        return;
    }

    clients_ = client_->getOnlineClients();
    render();
}

/**
 * @brief Render the clients table with current data and filter.
 */
void ClientsPage::render() {
    table_->setSortingEnabled(false);
    refreshButton_->setText(Localizer::instance().text("main.refresh", "Refresh"));
    refreshButton_->setIcon(Icons::refreshIcon(this));
    searchEdit_->setPlaceholderText(Localizer::instance().text("search.placeholder", "Search by name, IP or MAC"));
    const auto &localizer = Localizer::instance();
    table_->setHorizontalHeaderLabels({
        localizer.text("table.state", "State"),
        localizer.text("table.name", "Name"),
        localizer.text("table.ip", "IP"),
        localizer.text("table.mac", "MAC"),
        localizer.text("table.network", "Network"),
        localizer.text("table.speed", "Speed"),
        localizer.text("table.policy", "Policy"),
        localizer.text("table.wol", "Wake-on-LAN")
    });
    table_->setRowCount(0);

    int row = 0;
    const auto filter = searchEdit_->text().trimmed();
    const auto ordered = sortedClients(clients_);

    for (const auto &client : ordered) {
        if (!containsFilter(client, filter)) {
            continue;
        }

        table_->insertRow(row);
        auto *stateItem = makeStateItem(this, client.online);
        table_->setItem(row, 0, stateItem);
        table_->setItem(row, 1, new QTableWidgetItem(client.name));
        table_->setItem(row, 2, new QTableWidgetItem(client.ip));
        table_->setItem(row, 3, new QTableWidgetItem(client.mac));

        const auto connection = describeConnection(client);
        QStringList networkParts;
        if (!connection.segment.isEmpty()) {
            networkParts << connection.segment;
        }
        if (!connection.connection.isEmpty()) {
            networkParts << connection.connection;
        }
        const QString networkText = networkParts.join("\n");

        QStringList speedParts;
        if (!connection.speed.isEmpty()) {
            speedParts << connection.speed;
        }
        if (!connection.info.isEmpty()) {
            speedParts << connection.info;
        }
        const QString speedText = speedParts.join("\n");
        table_->setItem(row, 4, new QTableWidgetItem(networkText));
        table_->setItem(row, 5, new QTableWidgetItem(speedText));

        QString policy = "Default";
        if (client.deny) {
            policy = "Blocked";
        } else if (!client.policy.isEmpty()) {
            policy = client.policy;
        }
        table_->setItem(row, 6, new QTableWidgetItem(policy));

        auto *button = new QPushButton(Localizer::instance().text("clients.wol.button", "Wake"), table_);
        const auto mac = client.mac;
        connect(button, &QPushButton::clicked, this, [this, mac]() {
            if (!client_) {
                return;
            }

            QString message;
            const auto success = client_->wakeOnLan(mac, &message);
            if (success) {
                QMessageBox::information(this,
                    Localizer::instance().text("clients.wol.title.success", "Wake-on-LAN"),
                    message);
            } else {
                QMessageBox::warning(this,
                    Localizer::instance().text("clients.wol.title.error", "Wake-on-LAN"),
                    message);
            }
        });

        table_->setCellWidget(row, 7, button);
        ++row;
    }

    // Auto-resize columns to fit the longest cell content (not just header)
    for (int col = 0; col < table_->columnCount(); ++col) {
        int maxWidth = table_->horizontalHeader()->sectionSizeHint(col);
        for (int row = 0; row < table_->rowCount(); ++row) {
            QWidget *cellWidget = table_->cellWidget(row, col);
            if (cellWidget) {
                maxWidth = std::max(maxWidth, cellWidget->sizeHint().width());
            }
            QTableWidgetItem *item = table_->item(row, col);
            if (item) {
                maxWidth = std::max(maxWidth, table_->fontMetrics().horizontalAdvance(item->text()) + 24);
            }
        }
        table_->setColumnWidth(col, maxWidth);
    }

    table_->setSortingEnabled(true);
}

/**
 * @brief Set the sort state of the table.
 * @param column Column index
 * @param order Sort order
 */
void ClientsPage::setSortState(int column, Qt::SortOrder order) {
    if (column < 0 || column >= table_->columnCount()) {
        return;
    }
    table_->sortItems(column, order);
}
