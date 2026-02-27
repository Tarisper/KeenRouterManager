#include "MePage.h"

#include "../../core/Localizer.h"
#include "../Icons.h"

#include <QHeaderView>
#include <QLabel>
#include <QComboBox>
#include <QMessageBox>
#include <QNetworkAddressEntry>
#include <QNetworkInterface>
#include <QSize>
#include <QTableWidget>
#include <QVBoxLayout>
#include <algorithm>
#include <QThread>

namespace {
QString normalizeMac(QString mac) {
    mac = mac.toLower();
    QString normalized;
    normalized.reserve(mac.size());

    for (const auto ch : mac) {
        if ((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
            normalized.append(ch);
        }
    }

    return normalized;
}

QTableWidgetItem *makeStateItem(QWidget *owner, bool online) {
    const auto &localizer = Localizer::instance();
    auto *item = new QTableWidgetItem(localizer.text(online ? "status.online" : "status.offline",
                                                     online ? "Online" : "Offline"));
    item->setIcon(online ? Icons::statusOnlineIcon(owner) : Icons::statusOfflineIcon(owner));
    item->setForeground(online ? QColor(34, 125, 74) : QColor(160, 69, 63));
    return item;
}
} // namespace

MePage::MePage(QWidget *parent)
    : QWidget(parent),
      statusLabel_(new QLabel("Select router and click refresh", this)),
      table_(new QTableWidget(this)) {
    table_->setColumnCount(7);
    table_->setHorizontalHeaderLabels({
        Localizer::instance().text("table.state", "State"),
        Localizer::instance().text("table.name", "Name"),
        Localizer::instance().text("table.ip", "IP"),
        Localizer::instance().text("table.mac", "MAC"),
        Localizer::instance().text("table.interface", "Interface"),
        Localizer::instance().text("table.type", "Type"),
        Localizer::instance().text("table.policy", "Policy")
    });
    table_->horizontalHeader()->setSectionResizeMode(QHeaderView::Interactive);
    table_->verticalHeader()->setVisible(false);
    table_->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table_->setShowGrid(false);
    table_->setAlternatingRowColors(true);
    table_->setSelectionBehavior(QAbstractItemView::SelectRows);
    table_->setSelectionMode(QAbstractItemView::SingleSelection);
    table_->setSortingEnabled(true);
    // Auto-resize columns to fit contents
    table_->resizeColumnsToContents();
    table_->horizontalHeader()->setSortIndicatorShown(true);
    table_->setIconSize(QSize(16, 16));
    statusLabel_->setMinimumHeight(22);

    auto *layout = new QVBoxLayout(this);
    layout->setContentsMargins(8, 6, 8, 8);
    layout->setSpacing(8);
    layout->addWidget(statusLabel_);
    layout->addWidget(table_);
    setLayout(layout);

    connect(table_->horizontalHeader(), &QHeaderView::sortIndicatorChanged, this, [this](int column, Qt::SortOrder order) {
        Q_EMIT tableSortChanged(column, order);
    });
}

/**
 * @brief Set the router and client context for the page.
 * @param router RouterInfo
 * @param client KeeneticClient shared pointer
 */

void MePage::setContext(const RouterInfo &router, const std::shared_ptr<KeeneticClient> &client) {
    router_ = router;
    client_ = client;
}

/**
 * @brief Refresh the local interfaces and router clients, update the table.
 */

void MePage::refresh() {
    table_->setSortingEnabled(false);
    table_->setHorizontalHeaderLabels({
        Localizer::instance().text("table.state", "State"),
        Localizer::instance().text("table.name", "Name"),
        Localizer::instance().text("table.ip", "IP"),
        Localizer::instance().text("table.mac", "MAC"),
        Localizer::instance().text("table.interface", "Interface"),
        Localizer::instance().text("table.type", "Type"),
        Localizer::instance().text("table.policy", "Policy")
    });
    table_->setRowCount(0);

    if (!client_) {
        statusLabel_->setText("Router is not selected");
        return;
    }

    const auto clients = client_->getOnlineClients();
    const auto policies = client_->getPolicies();
    const bool hasRouterClients = !clients.isEmpty();

    QMap<QString, OnlineClient> byMac;
    for (const auto &client : clients) {
        byMac.insert(normalizeMac(client.mac), client);
    }

    int row = 0;
    for (const auto &iface : QNetworkInterface::allInterfaces()) {
        if (iface.flags().testFlag(QNetworkInterface::IsLoopBack)) {
            continue;
        }

        const auto macOriginal = iface.hardwareAddress();
        const auto mac = normalizeMac(macOriginal);
        if (mac.isEmpty()) {
            continue;
        }


        QString ip;
        for (const auto &entry : iface.addressEntries()) {
            if (entry.ip().protocol() == QAbstractSocket::IPv4Protocol) {
                const QString candidateIp = entry.ip().toString();
                if (candidateIp != "0.0.0.0") {
                    ip = candidateIp;
                    break;
                }
            }
        }

        QString type = "Ethernet";
        if (iface.humanReadableName().contains("wi", Qt::CaseInsensitive) || iface.name().contains("wl")) {
            type = "Wi-Fi";
        }

        const auto current = byMac.value(mac);
        if (hasRouterClients && !byMac.contains(mac)) {
            continue;
        }

        const bool online = current.online;
        QString displayName = current.name;
        if (displayName.isEmpty() || displayName.compare("Unknown", Qt::CaseInsensitive) == 0) {
            displayName = iface.humanReadableName();
        }

        table_->insertRow(row);
        auto *stateItem = makeStateItem(this, online);
        table_->setItem(row, 0, stateItem);
        table_->setItem(row, 1, new QTableWidgetItem(displayName));
        table_->setItem(row, 2, new QTableWidgetItem(ip));
        table_->setItem(row, 3, new QTableWidgetItem(macOriginal.toLower()));
        table_->setItem(row, 4, new QTableWidgetItem(iface.name()));
        table_->setItem(row, 5, new QTableWidgetItem(type));

        auto *policyCombo = new QComboBox(table_);
        policyCombo->addItem("Default", "");
        policyCombo->addItem("Blocked", "__blocked__");
        for (auto it = policies.constBegin(); it != policies.constEnd(); ++it) {
            policyCombo->addItem(it.value(), it.key());
        }

        if (current.deny) {
            policyCombo->setCurrentIndex(1);
        } else if (!current.policy.isEmpty()) {
            const auto index = policyCombo->findData(current.policy);
            if (index >= 0) {
                policyCombo->setCurrentIndex(index);
            }
        }

        const QString targetMac = current.mac.toLower();
        connect(policyCombo, &QComboBox::currentIndexChanged, this, [this, policyCombo, targetMac](int) {
            if (!client_) {
                return;
            }

            if (targetMac.isEmpty()) {
                QMessageBox::warning(this, "Policy", "Device MAC is unknown for router API.");
                refresh();
                return;
            }

            const auto value = policyCombo->currentData().toString();
            bool ok = false;
            if (value == "__blocked__") {
                ok = client_->setClientBlock(targetMac);
            } else {
                ok = client_->applyPolicyToClient(targetMac, value);
            }

            if (!ok) {
                QMessageBox::warning(this, "Policy", "Failed to update client policy.");
                refresh();
                return;
            }

            const auto latestClients = client_->getOnlineClients();
            const auto targetNormalized = normalizeMac(targetMac);
            bool confirmed = false;

            for (int attempt = 0; attempt < 18 && !confirmed; ++attempt) {
                const auto polledClients = (attempt == 0) ? latestClients : client_->getOnlineClients();
                const auto it = std::find_if(polledClients.cbegin(), polledClients.cend(),
                                             [&targetNormalized](const OnlineClient &item) {
                                                 return normalizeMac(item.mac) == targetNormalized;
                                             });

                if (it != polledClients.cend()) {
                    if (value == "__blocked__") {
                        confirmed = it->deny;
                    } else if (value.isEmpty()) {
                        confirmed = !it->deny && it->policy.isEmpty();
                    } else {
                        confirmed = !it->deny && it->policy == value;
                    }
                }

                if (!confirmed) {
                    QThread::msleep(200);
                }
            }

            if (!confirmed) {
                QMessageBox::warning(this, "Policy", "Router has not confirmed the new policy yet. Try Refresh after a short delay.");
            }

            refresh();
        });

        table_->setCellWidget(row, 6, policyCombo);
        ++row;
    }

    statusLabel_->setText(Localizer::instance().text("status.connected_to", "Connected to: %1").arg(router_.name));
    table_->setSortingEnabled(true);

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
}

/**
 * @brief Set the sort state of the table.
 * @param column Column index
 * @param order Sort order
 */
void MePage::setSortState(int column, Qt::SortOrder order) {
    if (column < 0 || column >= table_->columnCount()) {
        return;
    }
    table_->sortItems(column, order);
}
