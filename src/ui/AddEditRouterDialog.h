#pragma once

#include <QDialog>
#include <optional>

#include "../core/Models.h"

class QLineEdit;

class AddEditRouterDialog : public QDialog {
public:
    static std::optional<RouterInfo> showDialog(QWidget *parent, const std::optional<RouterInfo> &initial = std::nullopt);

private:
    explicit AddEditRouterDialog(QWidget *parent, const std::optional<RouterInfo> &initial);

    RouterInfo toRouter() const;
    bool validate();

    QLineEdit *nameEdit_;
    QLineEdit *addressEdit_;
    QLineEdit *loginEdit_;
    QLineEdit *passwordEdit_;
};
