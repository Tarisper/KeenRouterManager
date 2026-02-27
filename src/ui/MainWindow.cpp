#include "MainWindow.h"

#include <QChar>
#include <QComboBox>
#include <QFileDialog>
#include <QFrame>
#include <QHBoxLayout>
#include "../../build/src/version.h"
#include <QLabel>
#include <QListWidget>
#include <QMessageBox>
#include <QPushButton>
#include <QSize>
#include <QStackedWidget>
#include <QVBoxLayout>
#include <QWidget>

#include "../core/ConfigStore.h"
#include "../core/Localizer.h"
#include "AddEditRouterDialog.h"
#include "Icons.h"
#include "pages/ClientsPage.h"
#include "pages/MePage.h"
#include "pages/SettingsPage.h"
#include "pages/VpnPage.h"

namespace {
QString asUrl(QString value) {
    value = value.trimmed();
    if (!value.startsWith("http://") && !value.startsWith("https://")) {
        value = "http://" + value;
    }
    while (value.endsWith('/')) {
        value.chop(1);
    }
    return value;
}

/**
 * @brief Format a string representing uptime into a human-readable format
 * @param value The string to format (either total seconds or DD:HH:MM:SS format)
 * @param localizer The localizer instance for translation
 * @return QString The formatted uptime string
 */
QString formatUptime(QString value, const Localizer &localizer) {
    value = value.trimmed();
    if (value.isEmpty()) {
        return value;
    }

    // Try parsing as total seconds first
    bool isNumber = false;
    const qlonglong totalSeconds = value.toLongLong(&isNumber);
    if (isNumber && totalSeconds >= 0) {
        const qlonglong days = totalSeconds / 86400;
        const qlonglong hours = (totalSeconds % 86400) / 3600;
        const qlonglong minutes = (totalSeconds % 3600) / 60;
        const qlonglong seconds = totalSeconds % 60;

        const auto timePart = QString("%1:%2:%3")
            .arg(hours, 2, 10, QChar('0'))
            .arg(minutes, 2, 10, QChar('0'))
            .arg(seconds, 2, 10, QChar('0'));

        if (days > 0) {
            return localizer.text("settings.router_info.uptime_days", "%1 d. %2").arg(days).arg(timePart);
        }

        return timePart;
    }

    // If not a number, try parsing as DD:HH:MM:SS format
    QStringList segments;
    for (const auto &segment : value.split(':', Qt::KeepEmptyParts)) {
        segments.append(segment.trimmed());
    }
    if (segments.isEmpty()) {
        return value;
    }

    const auto indexFromEnd = [&](int offset) {
        return segments.size() - 1 - offset;
    };

    int days = 0;
    int hours = 0;
    int minutes = 0;
    int seconds = 0;
    bool ok = true;
    auto parseSegment = [&](int &target, int idx) {
        if (idx < 0) {
            return;
        }
        const auto trimmed = segments.value(idx).trimmed();
        if (trimmed.isEmpty()) {
            target = 0;
            return;
        }
        bool segmentOk = false;
        const int parsed = trimmed.toInt(&segmentOk);
        if (!segmentOk) {
            ok = false;
            return;
        }
        target = parsed;
    };

    parseSegment(seconds, indexFromEnd(0));
    parseSegment(minutes, indexFromEnd(1));
    parseSegment(hours, indexFromEnd(2));
    if (segments.size() >= 4) {
        parseSegment(days, indexFromEnd(3));
    }

    if (!ok) {
        return value;
    }

    const auto timePart = QString("%1:%2:%3")
        .arg(hours, 2, 10, QChar('0'))
        .arg(minutes, 2, 10, QChar('0'))
        .arg(seconds, 2, 10, QChar('0'));

    if (days > 0) {
        return localizer.text("settings.router_info.uptime_days", "%1 d. %2").arg(days).arg(timePart);
    }

    return timePart;
}
} // namespace

/**
 * @brief Convert a string to a normalized URL (adds http:// if missing, trims slashes).
 * @param value Input string
 * @return Normalized URL string
 */
MainWindow::MainWindow()
    : routerCombo_(nullptr),
            routerLabel_(nullptr),
      addButton_(nullptr),
      refreshButton_(nullptr),
      connectedByLabel_(nullptr),
      sidebar_(nullptr),
      pages_(nullptr),
      mePage_(nullptr),
      vpnPage_(nullptr),
    clientsPage_(nullptr),
            settingsPage_(nullptr),
            connectedByValue_("-") {
    setupUi();
    loadRouters();
}

/**
 * @brief Set up the main window UI, layouts, and connect signals.
 */
void MainWindow::setupUi() {
    setWindowTitle("KeenRouterManager");
#ifdef Q_OS_MAC
    setUnifiedTitleAndToolBarOnMac(true);
#endif

    auto *central = new QWidget(this);
    auto *root = new QVBoxLayout(central);
    root->setContentsMargins(14, 10, 14, 12);
    root->setSpacing(10);

    auto *topBar = new QHBoxLayout;
    topBar->setSpacing(8);
    routerLabel_ = new QLabel("Router:", central);
    routerCombo_ = new QComboBox(central);
    routerCombo_->setMinimumWidth(280);

    addButton_ = new QPushButton("Add", central);
    refreshButton_ = new QPushButton("Refresh", central);
    aboutButton_ = new QPushButton("About", central);
    connectedByLabel_ = new QLabel("Connected by: -", central);
    addButton_->setIcon(Icons::addIcon(this));
    refreshButton_->setIcon(Icons::refreshIcon(this));
    addButton_->setIconSize(QSize(16, 16));
    refreshButton_->setIconSize(QSize(16, 16));
    addButton_->setAutoDefault(false);
    refreshButton_->setAutoDefault(false);
    connectedByLabel_->setAlignment(Qt::AlignRight | Qt::AlignVCenter);

    topBar->addWidget(routerLabel_);
    topBar->addWidget(routerCombo_, 1);
    topBar->addWidget(addButton_);
    topBar->addWidget(refreshButton_);
    topBar->addWidget(aboutButton_);
    topBar->addWidget(connectedByLabel_, 1);

    root->addLayout(topBar);

    auto *content = new QHBoxLayout;
    content->setSpacing(12);
    sidebar_ = new QListWidget(central);
    sidebar_->setFixedWidth(190);
    sidebar_->setFrameShape(QFrame::NoFrame);
    sidebar_->setUniformItemSizes(true);
    sidebar_->setSpacing(2);
    sidebar_->addItem("Me");
    sidebar_->addItem("VPN");
    sidebar_->addItem("Clients");
    sidebar_->addItem("Settings");

    pages_ = new QStackedWidget(central);
    mePage_ = new MePage(pages_);
    vpnPage_ = new VpnPage(pages_);
    clientsPage_ = new ClientsPage(pages_);
    settingsPage_ = new SettingsPage(pages_);

    pages_->addWidget(mePage_);
    pages_->addWidget(vpnPage_);
    pages_->addWidget(clientsPage_);
    pages_->addWidget(settingsPage_);

    content->addWidget(sidebar_);
    content->addWidget(pages_, 1);
    root->addLayout(content, 1);

    setCentralWidget(central);

    connect(sidebar_, &QListWidget::currentRowChanged, pages_, &QStackedWidget::setCurrentIndex);
    connect(sidebar_, &QListWidget::currentRowChanged, this, [this](int) { refreshCurrentPage(); });
    connect(routerCombo_, &QComboBox::currentIndexChanged, this, [this](int index) { applyRouterByIndex(index); });

    connect(addButton_, &QPushButton::clicked, this, [this]() { onAddRouter(); });
    connect(refreshButton_, &QPushButton::clicked, this, [this]() { refreshCurrentPage(); });
    connect(aboutButton_, &QPushButton::clicked, this, [this]() { onShowAbout(); });

    connect(settingsPage_, &SettingsPage::addRouterRequested, this, [this]() { onAddRouter(); });
    connect(settingsPage_, &SettingsPage::editRouterRequested, this, [this](int index) { onEditRouterByIndex(index); });
    connect(settingsPage_, &SettingsPage::deleteRouterRequested, this, [this](int index) { onDeleteRouterByIndex(index); });
    connect(settingsPage_, &SettingsPage::importRoutersRequested, this, [this]() { onImportRoutersFromSettings(); });
    connect(settingsPage_, &SettingsPage::exportRoutersRequested, this, [this]() { onExportRoutersFromSettings(); });
    connect(settingsPage_, &SettingsPage::routerInfoRequested, this, [this]() { onShowRouterInfoFromSettings(); });
    connect(settingsPage_, &SettingsPage::appSettingsChanged, this, [this](const AppSettings &settings) { onAppSettingsChanged(settings); });

    connect(mePage_, &MePage::tableSortChanged, this, [this](int column, Qt::SortOrder order) {
        onTableSortChanged("me", column, order);
    });
    connect(vpnPage_, &VpnPage::tableSortChanged, this, [this](int column, Qt::SortOrder order) {
        onTableSortChanged("vpn", column, order);
    });
    connect(clientsPage_, &ClientsPage::tableSortChanged, this, [this](int column, Qt::SortOrder order) {
        onTableSortChanged("clients", column, order);
    });

    sidebar_->setCurrentRow(0);
}

/**
 * @brief Load routers from config file.
 */
void MainWindow::loadRouters() {
    routers_ = ConfigStore::loadRouters();
    appSettings_ = ConfigStore::loadAppSettings();

    const auto languagePacksPath = Localizer::detectLanguagePacksPath();
    if (!languagePacksPath.isEmpty()) {
        Localizer::instance().loadLanguagePacks(languagePacksPath);
    }
    Localizer::instance().setLanguage(appSettings_.uiLanguage);
    applyLanguage();
    restoreTableSortState();

    rebuildRouterCombo();
    settingsPage_->setAppSettings(appSettings_);
    syncSettingsPage();

    if (!routers_.isEmpty()) {
        routerCombo_->setCurrentIndex(0);
    }
}

/**
 * @brief Save routers to config file.
 */
void MainWindow::saveRouters() {
    ConfigStore::saveRouters(routers_);
}

/**
 * @brief Rebuild the router selection combo box.
 */
void MainWindow::rebuildRouterCombo() {
    routerCombo_->clear();
    for (const auto &router : routers_) {
        routerCombo_->addItem(router.name);
    }

    syncSettingsPage();
}

/**
 * @brief Sync settings page with current routers and settings.
 */
void MainWindow::syncSettingsPage() {
    settingsPage_->setRouters(routers_, routerCombo_->currentIndex());
}

/**
 * @brief Apply current language to all UI elements.
 */
void MainWindow::applyLanguage() {
    const auto &localizer = Localizer::instance();

    setWindowTitle(localizer.text("main.window_title", "KeenRouterManager"));
    routerLabel_->setText(localizer.text("main.router", "Router:"));
    addButton_->setText(localizer.text("main.add", "Add"));
    refreshButton_->setText(localizer.text("main.refresh", "Refresh"));
    aboutButton_->setText(localizer.text("main.about", "About"));

    const int currentRow = sidebar_->currentRow();
    sidebar_->clear();
    sidebar_->addItem(localizer.text("main.sidebar.me", "Me"));
    sidebar_->addItem(localizer.text("main.sidebar.vpn", "VPN"));
    sidebar_->addItem(localizer.text("main.sidebar.clients", "Clients"));
    sidebar_->addItem(localizer.text("main.sidebar.settings", "Settings"));
    sidebar_->setCurrentRow(currentRow >= 0 ? currentRow : 0);

    settingsPage_->refreshTranslations();
    updateConnectedByLabel();
}

/**
 * @brief Restore table sort state from settings.
 */
void MainWindow::restoreTableSortState() {
    restoringTableSort_ = true;

    auto restore = [this](const QString &key, auto *page) {
        if (!appSettings_.tableSortColumns.contains(key)) {
            return;
        }
        const int column = appSettings_.tableSortColumns.value(key);
        const auto order = appSettings_.tableSortOrders.value(key, 0) == 1
                               ? Qt::DescendingOrder
                               : Qt::AscendingOrder;
        page->setSortState(column, order);
    };

    restore("me", mePage_);
    restore("vpn", vpnPage_);
    restore("clients", clientsPage_);

    restoringTableSort_ = false;
}

/**
 * @brief Handle table sort change event and save state.
 * @param tableKey Table identifier
 * @param column Column index
 * @param order Sort order
 */
void MainWindow::onTableSortChanged(const QString &tableKey, int column, Qt::SortOrder order) {
    if (restoringTableSort_) {
        return;
    }

    appSettings_.tableSortColumns[tableKey] = column;
    appSettings_.tableSortOrders[tableKey] = (order == Qt::DescendingOrder ? 1 : 0);
    ConfigStore::saveAppSettings(appSettings_);
}

/**
 * @brief Update the label showing how the router is connected.
 */
void MainWindow::updateConnectedByLabel() {
    const auto &localizer = Localizer::instance();
    if (connectedByValue_ == "-") {
        connectedByLabel_->setText(localizer.text("main.connected_none", "Connected by: -"));
        return;
    }

    if (connectedByValue_ == "failed") {
        connectedByLabel_->setText(localizer.text("main.connected_failed", "Connected by: failed"));
        return;
    }

    connectedByLabel_->setText(localizer.text("main.connected_by", "Connected by: %1").arg(connectedByValue_));
}

/**
 * @brief Apply router by index from combo box selection.
 * @param index Index in routers list
 */
void MainWindow::applyRouterByIndex(int index) {
    if (index < 0 || index >= routers_.size()) {
        client_.reset();
        connectedByValue_ = "-";
        updateConnectedByLabel();
        refreshCurrentPage();
        return;
    }

    currentRouter_ = routers_[index];

    QString usedAddress;
    std::shared_ptr<KeeneticClient> selected;

    const QString preferred = currentRouter_.networkIp.isEmpty() ? currentRouter_.address : currentRouter_.networkIp;
    auto probe = std::make_shared<KeeneticClient>(preferred,
                                                  currentRouter_.login,
                                                  currentRouter_.password,
                                                  currentRouter_.name,
                                                  appSettings_.requestTimeoutSec,
                                                  appSettings_.requestRetries,
                                                  appSettings_.preferHttps);
    if (probe->login()) {
        selected = probe;
        usedAddress = probe->baseUrl();
    } else {
        for (const auto &domain : currentRouter_.keenDnsUrls) {
            const auto candidateAddress = domain.startsWith("http") ? domain : "https://" + domain;
            auto candidate = std::make_shared<KeeneticClient>(candidateAddress,
                                                              currentRouter_.login,
                                                              currentRouter_.password,
                                                              currentRouter_.name,
                                                              appSettings_.requestTimeoutSec,
                                                              appSettings_.requestRetries,
                                                              appSettings_.preferHttps);
            if (candidate->login()) {
                selected = candidate;
                usedAddress = candidate->baseUrl();
                break;
            }
        }
    }

    if (!selected) {
        const auto &localizer = Localizer::instance();
        QMessageBox::warning(this,
                             localizer.text("router.title", "Router"),
                             localizer.text("router.connect_failed", "Failed to connect to router."));
        client_.reset();
        connectedByValue_ = "failed";
        updateConnectedByLabel();
        refreshCurrentPage();
        return;
    }

    client_ = selected;
    connectedByValue_ = usedAddress;
    updateConnectedByLabel();

    bool changed = false;
    if (currentRouter_.networkIp.isEmpty()) {
        const auto networkIp = client_->getNetworkIp();
        if (!networkIp.isEmpty()) {
            currentRouter_.networkIp = networkIp;
            changed = true;
        }
    }

    if (currentRouter_.keenDnsUrls.isEmpty()) {
        const auto urls = client_->getKeenDnsUrls();
        if (!urls.isEmpty()) {
            currentRouter_.keenDnsUrls = urls;
            changed = true;
        }
    }

    routers_[index] = currentRouter_;
    if (changed) {
        saveRouters();
    }

    mePage_->setContext(currentRouter_, client_);
    vpnPage_->setContext(currentRouter_, client_);
    clientsPage_->setContext(currentRouter_, client_);
    refreshCurrentPage();
}

/**
 * @brief Refresh the current page (Me, VPN, Clients, Settings).
 */
void MainWindow::refreshCurrentPage() {
    const auto index = pages_->currentIndex();
    if (index == 0) {
        mePage_->refresh();
    } else if (index == 1) {
        vpnPage_->refresh();
    } else if (index == 2) {
        clientsPage_->refresh();
    } else if (index == 3) {
        settingsPage_->refresh();
    }
}

/**
 * @brief Normalize address for display (removes scheme, trims).
 * @param address Input address string
 * @return Normalized address string
 */
QString MainWindow::normalizeAddressForDisplay(const QString &address) const {
    return asUrl(address);
}

/**
 * @brief Show dialog to add a new router.
 */
void MainWindow::onAddRouter() {
    auto created = AddEditRouterDialog::showDialog(this);
    if (!created.has_value()) {
        return;
    }

    routers_.append(*created);
    saveRouters();
    rebuildRouterCombo();
    routerCombo_->setCurrentIndex(routers_.size() - 1);
}

/**
 * @brief Show dialog to edit router by index.
 * @param index Index in routers list
 */
void MainWindow::onEditRouterByIndex(int index) {
    if (index < 0 || index >= routers_.size()) {
        return;
    }

    auto updated = AddEditRouterDialog::showDialog(this, routers_[index]);
    if (!updated.has_value()) {
        return;
    }

    updated->networkIp = routers_[index].networkIp;
    updated->keenDnsUrls = routers_[index].keenDnsUrls;

    routers_[index] = *updated;
    saveRouters();
    rebuildRouterCombo();
    routerCombo_->setCurrentIndex(index);
}

/**
 * @brief Delete router by index after confirmation.
 * @param index Index in routers list
 */
void MainWindow::onDeleteRouterByIndex(int index) {
    if (index < 0 || index >= routers_.size()) {
        return;
    }

    routers_.removeAt(index);
    saveRouters();
    rebuildRouterCombo();

    if (routers_.isEmpty()) {
        client_.reset();
        connectedByValue_ = "-";
        updateConnectedByLabel();
        syncSettingsPage();
        refreshCurrentPage();
    } else {
        routerCombo_->setCurrentIndex(0);
    }
}

/**
 * @brief Import routers from settings page.
 */
void MainWindow::onImportRoutersFromSettings() {
    const auto path = QFileDialog::getOpenFileName(this,
                                                   Localizer::instance().text("settings.import.title", "Import Routers"),
                                                   QString(),
                                                   Localizer::instance().text("common.files.json", "JSON files (*.json);;All files (*.*)"));
    if (path.isEmpty()) {
        return;
    }

    bool ok = false;
    const auto imported = ConfigStore::importRoutersFromFile(path, &ok);
    if (!ok) {
        QMessageBox::warning(this,
                             Localizer::instance().text("settings.group.routers", "Routers"),
                             Localizer::instance().text("settings.import.fail", "Failed to parse file."));
        return;
    }

    routers_ = imported;
    saveRouters();
    rebuildRouterCombo();

    if (routers_.isEmpty()) {
        client_.reset();
        connectedByValue_ = "-";
        updateConnectedByLabel();
        refreshCurrentPage();
    } else {
        routerCombo_->setCurrentIndex(0);
    }
}

/**
 * @brief Export routers from settings page.
 */
void MainWindow::onExportRoutersFromSettings() {
    const auto path = QFileDialog::getSaveFileName(this,
                                                   Localizer::instance().text("settings.export.title", "Export Routers"),
                                                   Localizer::instance().text("settings.export.filename", "routers.json"),
                                                   Localizer::instance().text("common.files.json", "JSON files (*.json);;All files (*.*)"));
    if (path.isEmpty()) {
        return;
    }

    if (!ConfigStore::exportRoutersToFile(routers_, path)) {
        QMessageBox::warning(this,
                             Localizer::instance().text("settings.group.routers", "Routers"),
                             Localizer::instance().text("settings.export.fail", "Failed to write file."));
        return;
    }

    QMessageBox::information(this,
                             Localizer::instance().text("settings.group.routers", "Routers"),
                             Localizer::instance().text("settings.export.success", "Routers exported successfully."));
}

/**
 * @brief Show router info dialog from settings page.
 */
void MainWindow::onShowRouterInfoFromSettings() {
    const auto &localizer = Localizer::instance();

    if (!client_) {
        QMessageBox::information(this,
                                 localizer.text("settings.router_info.title", "Router Information"),
                                 localizer.text("settings.router_info.no_router", "Select and connect a router first."));
        return;
    }

    const auto info = client_->getRouterInfo();
    if (info.isEmpty()) {
        QMessageBox::information(this,
                                 localizer.text("settings.router_info.title", "Router Information"),
                                 localizer.text("settings.router_info.empty", "Router did not provide additional information."));
        return;
    }

    struct FieldDef {
        QString key;
        QString labelKey;
        QString fallback;
    };

    const QList<FieldDef> fields = {
        {"model", "settings.router_info.model", "Model"},
        {"serial", "settings.router_info.serial", "Serial Number"},
        {"service_code", "settings.router_info.service_code", "Service Code"},
        {"firmware", "settings.router_info.firmware", "Firmware Version"},
        {"domain", "settings.router_info.domain", "Domain Name"},
        {"ip_local", "settings.router_info.ip_local", "Local IP"},
        {"ip_external", "settings.router_info.ip_external", "External IP"},
        {"uptime", "settings.router_info.uptime", "Uptime"},
        {"hardware", "settings.router_info.hardware", "Hardware"}
    };

    QStringList lines;
    for (const auto &field : fields) {
        if (!info.contains(field.key)) {
            continue;
        }
        const auto value = info.value(field.key).trimmed();
        if (value.isEmpty()) {
            continue;
        }

        QString displayValue = value;
        if (field.key == "uptime") {
            displayValue = formatUptime(value, localizer);
        }

        lines.append(QString("%1: %2").arg(localizer.text(field.labelKey, field.fallback), displayValue));
    }

    if (lines.isEmpty()) {
        QMessageBox::information(this,
                                 localizer.text("settings.router_info.title", "Router Information"),
                                 localizer.text("settings.router_info.empty", "Router did not provide additional information."));
        return;
    }

    QMessageBox::information(this,
                             localizer.text("settings.router_info.title", "Router Information"),
                             lines.join("\n"));
}

/**
 * @brief Handle application settings change (language, network, etc).
 * @param settings New AppSettings
 */
void MainWindow::onAppSettingsChanged(const AppSettings &settings) {
    const auto languageChanged = appSettings_.uiLanguage != settings.uiLanguage;
    appSettings_ = settings;
    if (!ConfigStore::saveAppSettings(appSettings_)) {
        QMessageBox::warning(this,
                             Localizer::instance().text("settings.msg.title", "Settings"),
                             Localizer::instance().text("settings.msg.save_fail", "Failed to save settings."));
        return;
    }

    if (languageChanged) {
        Localizer::instance().setLanguage(appSettings_.uiLanguage);
        applyLanguage();
    }

    QMessageBox::information(this,
                             Localizer::instance().text("settings.msg.title", "Settings"),
                             Localizer::instance().text("settings.msg.saved", "Settings saved."));
}

/**
 * @brief Show the About dialog with app info.
 */
void MainWindow::onShowAbout() {
    const auto &localizer = Localizer::instance();
    const QString title = localizer.text("about.title", "About KeenRouterManager");
    const QString version = QString::fromUtf8(KEENETIC_MANAGER_VERSION);
    const QString message = localizer.text("about.message",
        QString("<h3>KeenRouterManager</h3>"
                "<p><b>Version:</b> %1</p>"
                "<p><b>Developer:</b> Tarisper</p>"
                "<p><b>GitHub:</b> <a href='https://github.com/Tarisper/KeenRouterManager'>https://github.com/Tarisper/KeenRouterManager</a></p>")
            .arg(version)
    );
    QMessageBox::about(this, title, message);
}
