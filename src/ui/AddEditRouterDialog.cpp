#include "AddEditRouterDialog.h"

#include "../core/Localizer.h"
#include "Icons.h"

#include <QDialogButtonBox>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QLineEdit>
#include <QMessageBox>
#include <QSize>
#include <QToolButton>
#include <QVBoxLayout>

/**
 * @brief Construct a new Add Edit Router Dialog:: Add Edit Router Dialog object
 * 
 * @param parent The parent widget
 * @param initial The initial router information, if any
 */
AddEditRouterDialog::AddEditRouterDialog(QWidget *parent, const std::optional<RouterInfo> &initial)
    : QDialog(parent),
      nameEdit_(new QLineEdit(this)),
      addressEdit_(new QLineEdit(this)),
      loginEdit_(new QLineEdit(this)),
      passwordEdit_(new QLineEdit(this)) {
        const auto &localizer = Localizer::instance();
        setWindowTitle(initial.has_value()
                                             ? localizer.text("dialog.router.edit", "Edit Router")
                                             : localizer.text("dialog.router.add", "Add Router"));

    if (initial.has_value()) {
        nameEdit_->setText(initial->name);
        addressEdit_->setText(initial->address);
        loginEdit_->setText(initial->login);
        passwordEdit_->setText(initial->password);
    }

    passwordEdit_->setEchoMode(QLineEdit::Password);

    auto *togglePasswordButton = new QToolButton(this);
    togglePasswordButton->setAutoRaise(true);
    togglePasswordButton->setIconSize(QSize(16, 16));
    togglePasswordButton->setCursor(Qt::PointingHandCursor);
    togglePasswordButton->setToolTip(localizer.text("dialog.password.show", "Show password"));
    togglePasswordButton->setIcon(Icons::eyeIcon(this, false));

    auto *passwordLayout = new QHBoxLayout;
    passwordLayout->setContentsMargins(0, 0, 0, 0);
    passwordLayout->setSpacing(6);
    passwordLayout->addWidget(passwordEdit_);
    passwordLayout->addWidget(togglePasswordButton);

    auto *passwordField = new QWidget(this);
    passwordField->setLayout(passwordLayout);

    connect(togglePasswordButton, &QToolButton::clicked, this, [this, togglePasswordButton]() {
        const bool visible = passwordEdit_->echoMode() == QLineEdit::Normal;
        passwordEdit_->setEchoMode(visible ? QLineEdit::Password : QLineEdit::Normal);

        const bool crossed = !visible;
        togglePasswordButton->setIcon(Icons::eyeIcon(this, crossed));
        togglePasswordButton->setToolTip(Localizer::instance().text(crossed ? "dialog.password.hide" : "dialog.password.show",
                                                                     crossed ? "Hide password" : "Show password"));
    });

    auto *form = new QFormLayout;
    form->addRow(localizer.text("dialog.field.name", "Name"), nameEdit_);
    form->addRow(localizer.text("dialog.field.address", "Address"), addressEdit_);
    form->addRow(localizer.text("dialog.field.login", "Login"), loginEdit_);
    form->addRow(localizer.text("dialog.field.password", "Password"), passwordField);

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    connect(buttons, &QDialogButtonBox::accepted, this, [this]() {
        if (validate()) {
            accept();
        }
    });
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);

    auto *root = new QVBoxLayout(this);
    root->addLayout(form);
    root->addWidget(buttons);
    setLayout(root);
}

/**
 * @brief Show the add/edit router dialog
 * 
 * @param parent The parent widget
 * @param initial The initial router information, if any
 * @return std::optional<RouterInfo> The router information if the dialog was accepted, std::nullopt otherwise
 */
std::optional<RouterInfo> AddEditRouterDialog::showDialog(QWidget *parent, const std::optional<RouterInfo> &initial) {
    AddEditRouterDialog dialog(parent, initial);
    if (dialog.exec() != QDialog::Accepted) {
        return std::nullopt;
    }

    return dialog.toRouter();
}

/**
 * @brief Get the router information from the dialog
 * @return RouterInfo The router information
 */
RouterInfo AddEditRouterDialog::toRouter() const {
    RouterInfo router;
    router.name = nameEdit_->text().trimmed();
    router.address = addressEdit_->text().trimmed();
    router.login = loginEdit_->text().trimmed();
    router.password = passwordEdit_->text();
    return router;
}

/**
 * @brief Validate the dialog fields
 * @return true if the fields are valid, false otherwise
 */
bool AddEditRouterDialog::validate() {
    if (nameEdit_->text().trimmed().isEmpty() ||
        addressEdit_->text().trimmed().isEmpty() ||
        loginEdit_->text().trimmed().isEmpty() ||
        passwordEdit_->text().isEmpty()) {
        const auto &localizer = Localizer::instance();
        QMessageBox::warning(this,
                             localizer.text("dialog.validation.title", "Validation"),
                             localizer.text("dialog.validation.required", "All fields are required."));
        return false;
    }

    return true;
}
