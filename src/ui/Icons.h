#pragma once

#include <QIcon>

class QWidget;

namespace Icons {
QIcon appIcon(int size = 256);
QIcon addIcon(const QWidget *widget, int size = 16);
QIcon refreshIcon(const QWidget *widget, int size = 16);
QIcon statusOnlineIcon(const QWidget *widget, int size = 16);
QIcon statusOfflineIcon(const QWidget *widget, int size = 16);
QIcon eyeIcon(const QWidget *widget, bool crossed, int size = 16);
} // namespace Icons
