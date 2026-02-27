#include "VpnPage.h"

#include "../../core/Localizer.h"
#include "../Icons.h"

#include <QComboBox>
#include <QHeaderView>
#include <QHBoxLayout>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QSize>
#include <QTableWidget>
#include <QTableWidgetItem>
#include <QVBoxLayout>

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

QTableWidgetItem *makeStateItem(QWidget *owner, bool online) {
    const auto &localizer = Localizer::instance();
    auto *item = new QTableWidgetItem(localizer.text(online ? "status.online" : "status.offline",
                                                     online ? "Online" : "Offline"));
    item->setIcon(online ? Icons::statusOnlineIcon(owner) : Icons::statusOfflineIcon(owner));
    item->setForeground(online ? QColor(34, 125, 74) : QColor(160, 69, 63));
    return item;
}
} // namespace

/**
 * @brief Check if the client matches the filter string (name, IP, or MAC).
 * @param client OnlineClient to check
 * @param filter Filter string
 * @return true if matches, false otherwise
 */

VpnPage::VpnPage(QWidget *parent)
    : QWidget(parent),
      searchEdit_(new QLineEdit(this)),
    refreshButton_(new QPushButton(Localizer::instance().text("main.refresh", "Refresh"), this)),
      table_(new QTableWidget(this)) {
        searchEdit_->setPlaceholderText(Localizer::instance().text("search.placeholder", "Search by name, IP or MAC"));

    table_->setColumnCount(5);
    table_->setHorizontalHeaderLabels({
        Localizer::instance().text("table.state", "State"),
        Localizer::instance().text("table.name", "Name"),
        Localizer::instance().text("table.ip", "IP"),
        Localizer::instance().text("table.mac", "MAC"),
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

void VpnPage::setContext(const RouterInfo &router, const std::shared_ptr<KeeneticClient> &client) {
    router_ = router;
    client_ = client;
}

/**
 * @brief Refresh the VPN clients and policies from the router.
 */

void VpnPage::refresh() {
    if (!client_) {
        clients_.clear();
        policies_.clear();
        render();
        return;
    }

    clients_ = client_->getOnlineClients();
    policies_ = client_->getPolicies();
    render();
}

/**
 * @brief Render the VPN clients table with current data and filter.
 */

void VpnPage::render() {
    table_->setSortingEnabled(false);
    refreshButton_->setText(Localizer::instance().text("main.refresh", "Refresh"));
    refreshButton_->setIcon(Icons::refreshIcon(this));
    searchEdit_->setPlaceholderText(Localizer::instance().text("search.placeholder", "Search by name, IP or MAC"));
    table_->setHorizontalHeaderLabels({
        Localizer::instance().text("table.state", "State"),
        Localizer::instance().text("table.name", "Name"),
        Localizer::instance().text("table.ip", "IP"),
        Localizer::instance().text("table.mac", "MAC"),
        Localizer::instance().text("table.policy", "Policy")
    });
    table_->setRowCount(0);

    int row = 0;
    const auto filter = searchEdit_->text().trimmed();
    for (const auto &client : clients_) {
        if (!containsFilter(client, filter)) {
            continue;
        }

        table_->insertRow(row);
        auto *stateItem = makeStateItem(this, client.online);
        table_->setItem(row, 0, stateItem);
        table_->setItem(row, 1, new QTableWidgetItem(client.name));
        table_->setItem(row, 2, new QTableWidgetItem(client.ip));
        table_->setItem(row, 3, new QTableWidgetItem(client.mac));

        auto *policyCombo = new QComboBox(table_);
        policyCombo->addItem("Default", "");
        policyCombo->addItem("Blocked", "__blocked__");
        for (auto it = policies_.constBegin(); it != policies_.constEnd(); ++it) {
            policyCombo->addItem(it.value(), it.key());
        }

        if (client.deny) {
            policyCombo->setCurrentIndex(1);
        } else if (!client.policy.isEmpty()) {
            const auto index = policyCombo->findData(client.policy);
            if (index >= 0) {
                policyCombo->setCurrentIndex(index);
            }
        }

        const auto mac = client.mac;
        connect(policyCombo, &QComboBox::currentIndexChanged, this, [this, policyCombo, mac](int) {
            if (!client_) {
                return;
            }

            const auto value = policyCombo->currentData().toString();
            bool ok = false;
            if (value == "__blocked__") {
                ok = client_->setClientBlock(mac);
            } else {
                ok = client_->applyPolicyToClient(mac, value);
            }

            if (!ok) {
                QMessageBox::warning(this, "Policy", "Failed to update client policy.");
            }
        });

        table_->setCellWidget(row, 4, policyCombo);
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

void VpnPage::setSortState(int column, Qt::SortOrder order) {
    if (column < 0 || column >= table_->columnCount()) {
        return;
    }
    table_->sortItems(column, order);
}
