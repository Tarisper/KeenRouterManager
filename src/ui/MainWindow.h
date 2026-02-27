#pragma once

#include <QList>
#include <QMainWindow>
#include <memory>

#include "../core/KeeneticClient.h"
#include "../core/Models.h"

class QComboBox;
class QLabel;
class QListWidget;
class QStackedWidget;
class QPushButton;

class MePage;
class VpnPage;
class ClientsPage;
class SettingsPage;

class MainWindow : public QMainWindow {
public:
    MainWindow();

private:
    void setupUi();
    void loadRouters();
    void saveRouters();
    void rebuildRouterCombo();
    void syncSettingsPage();
    void applyLanguage();
    void restoreTableSortState();
    void onTableSortChanged(const QString &tableKey, int column, Qt::SortOrder order);
    void updateConnectedByLabel();
    void applyRouterByIndex(int index);
    void refreshCurrentPage();
    QString normalizeAddressForDisplay(const QString &address) const;

    void onAddRouter();
    void onEditRouterByIndex(int index);
    void onDeleteRouterByIndex(int index);
    void onImportRoutersFromSettings();
    void onExportRoutersFromSettings();
    void onShowRouterInfoFromSettings();
    void onAppSettingsChanged(const AppSettings &settings);
    void onShowAbout();

    QList<RouterInfo> routers_;
    RouterInfo currentRouter_;
    AppSettings appSettings_;
    std::shared_ptr<KeeneticClient> client_;

    QComboBox *routerCombo_;
    QLabel *routerLabel_;
    QPushButton *addButton_;
    QPushButton *refreshButton_;
    QPushButton *aboutButton_;
    QLabel *connectedByLabel_;
    QString connectedByValue_;

    QListWidget *sidebar_;
    QStackedWidget *pages_;
    MePage *mePage_;
    VpnPage *vpnPage_;
    ClientsPage *clientsPage_;
    SettingsPage *settingsPage_;
    bool restoringTableSort_{false};
};
