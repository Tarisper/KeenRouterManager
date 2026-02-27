#pragma once

#include <QList>
#include <QWidget>

class QCheckBox;
class QComboBox;
class QFormLayout;
class QGroupBox;
class QListWidget;
class QLabel;
class QPushButton;
class QSpinBox;

#include "../../core/Models.h"

class SettingsPage : public QWidget {
    Q_OBJECT

public:
    explicit SettingsPage(QWidget *parent = nullptr);

    void refresh();
    void setRouters(const QList<RouterInfo> &routers, int currentIndex);
    void setAppSettings(const AppSettings &settings);
    void refreshTranslations();

Q_SIGNALS:
    void addRouterRequested();
    void editRouterRequested(int index);
    void deleteRouterRequested(int index);
    void importRoutersRequested();
    void exportRoutersRequested();
    void routerInfoRequested();
    void appSettingsChanged(const AppSettings &settings);

private:
    QLabel *title_;
    QGroupBox *routersGroup_;
    QListWidget *routersList_;
    QPushButton *addRouterButton_;
    QPushButton *editRouterButton_;
    QPushButton *deleteRouterButton_;
    QPushButton *importButton_;
    QPushButton *exportButton_;
    QPushButton *routerInfoButton_;

    QGroupBox *networkGroup_;
    QFormLayout *networkForm_;
    QLabel *timeoutLabel_;
    QLabel *retriesLabel_;
    QSpinBox *timeoutSpin_;
    QSpinBox *retriesSpin_;
    QCheckBox *preferHttpsCheck_;
    QPushButton *saveNetworkButton_;

    QGroupBox *languageGroup_;
    QFormLayout *languageForm_;
    QLabel *languageLabel_;
    QComboBox *languageCombo_;
    QPushButton *saveLanguageButton_;
};
