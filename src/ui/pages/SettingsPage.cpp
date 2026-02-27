#include "SettingsPage.h"

#include "../../core/Localizer.h"

#include <QCheckBox>
#include <QComboBox>
#include <QFont>
#include <QFormLayout>
#include <QGridLayout>
#include <QGroupBox>
#include <QLabel>
#include <QListWidget>
#include <QPushButton>
#include <QSpinBox>
#include <QHBoxLayout>
#include <QVBoxLayout>

/**
 * @brief SettingsPage constructor. Sets up UI and connects signals.
 * @param parent Parent widget
 */
SettingsPage::SettingsPage(QWidget *parent)
    : QWidget(parent),
    title_(new QLabel(this)),
    routersGroup_(new QGroupBox(this)),
    routersList_(new QListWidget(this)),
    addRouterButton_(new QPushButton(this)),
    editRouterButton_(new QPushButton(this)),
    deleteRouterButton_(new QPushButton(this)),
    importButton_(new QPushButton(this)),
    exportButton_(new QPushButton(this)),
    routerInfoButton_(new QPushButton(this)),
    networkGroup_(new QGroupBox(this)),
    networkForm_(new QFormLayout),
    timeoutLabel_(new QLabel(this)),
    retriesLabel_(new QLabel(this)),
    timeoutSpin_(new QSpinBox(this)),
    retriesSpin_(new QSpinBox(this)),
    preferHttpsCheck_(new QCheckBox(this)),
    saveNetworkButton_(new QPushButton(this)),
    languageGroup_(new QGroupBox(this)),
    languageForm_(new QFormLayout),
    languageLabel_(new QLabel(this)),
    languageCombo_(new QComboBox(this)),
    saveLanguageButton_(new QPushButton(this)) {
    QFont font = title_->font();
    font.setPointSize(font.pointSize() + 4);
    font.setBold(true);
    title_->setFont(font);
    title_->setMinimumHeight(24);

    auto *routersLayout = new QVBoxLayout(routersGroup_);
    routersLayout->setContentsMargins(12, 10, 12, 12);
    routersLayout->setSpacing(10);
    routersList_->setMinimumHeight(150);
    routersLayout->addWidget(routersList_);

    timeoutSpin_->setRange(1, 120);
    timeoutSpin_->setSuffix(" s");
    retriesSpin_->setRange(1, 10);
    addRouterButton_->setMinimumWidth(96);
    editRouterButton_->setMinimumWidth(96);
    deleteRouterButton_->setMinimumWidth(96);
    importButton_->setMinimumWidth(96);
    exportButton_->setMinimumWidth(96);
    routerInfoButton_->setMinimumWidth(96);
    saveNetworkButton_->setAutoDefault(false);
    saveLanguageButton_->setAutoDefault(false);

    auto *routerButtonsGrid = new QGridLayout;
    routerButtonsGrid->setHorizontalSpacing(8);
    routerButtonsGrid->setVerticalSpacing(8);
    routerButtonsGrid->addWidget(addRouterButton_, 0, 0);
    routerButtonsGrid->addWidget(editRouterButton_, 0, 1);
    routerButtonsGrid->addWidget(deleteRouterButton_, 0, 2);
    routerButtonsGrid->addWidget(importButton_, 1, 0);
    routerButtonsGrid->addWidget(exportButton_, 1, 1);
    routerButtonsGrid->addWidget(routerInfoButton_, 1, 2);
    routerButtonsGrid->setColumnStretch(3, 1);
    routersLayout->addLayout(routerButtonsGrid);

    auto *networkLayout = new QVBoxLayout(networkGroup_);
    networkLayout->setContentsMargins(12, 10, 12, 12);
    networkLayout->setSpacing(10);
    networkForm_->setLabelAlignment(Qt::AlignLeft | Qt::AlignVCenter);
    networkForm_->setFormAlignment(Qt::AlignLeft | Qt::AlignTop);
    networkForm_->setHorizontalSpacing(14);
    networkForm_->setVerticalSpacing(10);
    networkForm_->addRow(timeoutLabel_, timeoutSpin_);
    networkForm_->addRow(retriesLabel_, retriesSpin_);
    networkLayout->addLayout(networkForm_);
    networkLayout->addWidget(preferHttpsCheck_);

    auto *networkActions = new QHBoxLayout;
    networkActions->addStretch(1);
    networkActions->addWidget(saveNetworkButton_);
    networkLayout->addLayout(networkActions);

    languageCombo_->addItem("English", "en");
    languageCombo_->addItem("Русский", "ru");
    auto *languageLayout = new QVBoxLayout(languageGroup_);
    languageLayout->setContentsMargins(12, 10, 12, 12);
    languageLayout->setSpacing(10);
    languageForm_->setLabelAlignment(Qt::AlignLeft | Qt::AlignVCenter);
    languageForm_->setFormAlignment(Qt::AlignLeft | Qt::AlignTop);
    languageForm_->setHorizontalSpacing(14);
    languageForm_->setVerticalSpacing(10);
    languageForm_->addRow(languageLabel_, languageCombo_);
    languageLayout->addLayout(languageForm_);

    auto *languageActions = new QHBoxLayout;
    languageActions->addStretch(1);
    languageActions->addWidget(saveLanguageButton_);
    languageLayout->addLayout(languageActions);

    auto *layout = new QVBoxLayout(this);
    layout->setContentsMargins(12, 8, 12, 12);
    layout->setSpacing(12);
    layout->addWidget(title_);
    layout->addWidget(routersGroup_);
    layout->addWidget(networkGroup_);
    layout->addWidget(languageGroup_);
    layout->addStretch(1);
    setLayout(layout);

  refreshTranslations();

  connect(addRouterButton_, &QPushButton::clicked, this, [this]() {
    Q_EMIT addRouterRequested();
  });
  connect(editRouterButton_, &QPushButton::clicked, this, [this]() {
    Q_EMIT editRouterRequested(routersList_->currentRow());
  });
  connect(deleteRouterButton_, &QPushButton::clicked, this, [this]() {
    Q_EMIT deleteRouterRequested(routersList_->currentRow());
  });
  connect(importButton_, &QPushButton::clicked, this, [this]() {
    Q_EMIT importRoutersRequested();
  });
  connect(exportButton_, &QPushButton::clicked, this, [this]() {
    Q_EMIT exportRoutersRequested();
  });
  connect(routerInfoButton_, &QPushButton::clicked, this, [this]() {
    Q_EMIT routerInfoRequested();
  });
  connect(saveNetworkButton_, &QPushButton::clicked, this, [this]() {
    AppSettings settings;
    settings.requestTimeoutSec = timeoutSpin_->value();
    settings.requestRetries = retriesSpin_->value();
    settings.preferHttps = preferHttpsCheck_->isChecked();
    settings.uiLanguage = languageCombo_->currentData().toString();
    Q_EMIT appSettingsChanged(settings);
  });
  connect(saveLanguageButton_, &QPushButton::clicked, this, [this]() {
    AppSettings settings;
    settings.requestTimeoutSec = timeoutSpin_->value();
    settings.requestRetries = retriesSpin_->value();
    settings.preferHttps = preferHttpsCheck_->isChecked();
    settings.uiLanguage = languageCombo_->currentData().toString();
    Q_EMIT appSettingsChanged(settings);
  });
}

/**
 * @brief Refresh the settings page (stub).
 */
void SettingsPage::refresh() {
}

/**
 * @brief Set the list of routers and select the current one.
 * @param routers List of RouterInfo
 * @param currentIndex Index to select
 */
void SettingsPage::setRouters(const QList<RouterInfo> &routers, int currentIndex) {
  routersList_->clear();
  for (const auto &router : routers) {
    routersList_->addItem(router.name);
  }

  if (currentIndex >= 0 && currentIndex < routersList_->count()) {
    routersList_->setCurrentRow(currentIndex);
  }
}

/**
 * @brief Set the application settings (network, language, table sort).
 * @param settings AppSettings struct
 */
void SettingsPage::setAppSettings(const AppSettings &settings) {
  timeoutSpin_->setValue(settings.requestTimeoutSec);
  retriesSpin_->setValue(settings.requestRetries);
  preferHttpsCheck_->setChecked(settings.preferHttps);

  const int languageIndex = languageCombo_->findData(settings.uiLanguage);
  if (languageIndex >= 0) {
    languageCombo_->setCurrentIndex(languageIndex);
  }
}

/**
 * @brief Refresh translations for all UI elements.
 */
void SettingsPage::refreshTranslations() {
  const auto &localizer = Localizer::instance();

  title_->setText(localizer.text("settings.title", "Settings"));
  routersGroup_->setTitle(localizer.text("settings.group.routers", "Routers"));
  addRouterButton_->setText(localizer.text("settings.btn.add", "Add"));
  editRouterButton_->setText(localizer.text("settings.btn.edit", "Edit"));
  deleteRouterButton_->setText(localizer.text("settings.btn.delete", "Delete"));
  importButton_->setText(localizer.text("settings.btn.import", "Import"));
  exportButton_->setText(localizer.text("settings.btn.export", "Export"));
  routerInfoButton_->setText(localizer.text("settings.btn.router_info", "Router Info"));

  networkGroup_->setTitle(localizer.text("settings.group.network", "Network"));
  timeoutLabel_->setText(localizer.text("settings.network.timeout", "Request timeout"));
  retriesLabel_->setText(localizer.text("settings.network.retries", "Request retries"));
  timeoutSpin_->setSuffix(localizer.text("settings.seconds_suffix", " s"));
  preferHttpsCheck_->setText(localizer.text("settings.network.https", "Prefer HTTPS"));
  saveNetworkButton_->setText(localizer.text("settings.network.save", "Save Network Settings"));

  languageGroup_->setTitle(localizer.text("settings.group.language", "Language"));
  languageLabel_->setText(localizer.text("settings.language.label", "Interface language"));
  languageCombo_->setItemText(0, localizer.text("settings.language.english", "English"));
  languageCombo_->setItemText(1, localizer.text("settings.language.russian", "Russian"));
  saveLanguageButton_->setText(localizer.text("settings.language.save", "Apply Language"));
}
