#include "Icons.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QStringList>
#include <QWidget>

namespace {
QIcon loadNamedIcon(const QString &resourceName, const QString &fallbackPngName) {
    QIcon resourceIcon(QStringLiteral(":/icons/") + resourceName);
    if (!resourceIcon.isNull()) {
        return resourceIcon;
    }

    const auto appDir = QCoreApplication::applicationDirPath();
    const QStringList candidates = {
        QDir(appDir).absoluteFilePath(QString("../Resources/icons_png/%1").arg(fallbackPngName)),
        QDir(appDir).absoluteFilePath(QString("../icons_png/%1").arg(fallbackPngName)),
        QDir(QDir::currentPath()).absoluteFilePath(QString("resources/icons_png/%1").arg(fallbackPngName)),
        QDir(QDir::currentPath()).absoluteFilePath(QString("icons_png/%1").arg(fallbackPngName))
    };

    for (const auto &path : candidates) {
        if (!QFileInfo::exists(path)) {
            continue;
        }
        QIcon fileIcon(path);
        if (!fileIcon.isNull()) {
            return fileIcon;
        }
    }

    return {};
}
} // namespace

namespace Icons {
QIcon appIcon(int size) {
    Q_UNUSED(size);
    QIcon icon = loadNamedIcon(QStringLiteral("app_router_m.svg"), QStringLiteral("app_router_m.png"));
    return icon;
}

QIcon addIcon(const QWidget *widget, int size) {
    Q_UNUSED(widget);
    Q_UNUSED(size);
    QIcon icon = loadNamedIcon(QStringLiteral("action_add.png"), QStringLiteral("action_add.png"));
    return icon;
}

QIcon refreshIcon(const QWidget *widget, int size) {
    Q_UNUSED(widget);
    Q_UNUSED(size);
    return loadNamedIcon(QStringLiteral("action_refresh.png"), QStringLiteral("action_refresh.png"));
}

QIcon statusOnlineIcon(const QWidget *widget, int size) {
    Q_UNUSED(widget);
    Q_UNUSED(size);
    return loadNamedIcon(QStringLiteral("status_online.png"), QStringLiteral("status_online.png"));
}

QIcon statusOfflineIcon(const QWidget *widget, int size) {
    Q_UNUSED(widget);
    Q_UNUSED(size);
    return loadNamedIcon(QStringLiteral("status_offline.png"), QStringLiteral("status_offline.png"));
}

QIcon eyeIcon(const QWidget *widget, bool crossed, int size) {
    Q_UNUSED(widget);
    Q_UNUSED(size);
    return crossed
               ? loadNamedIcon(QStringLiteral("eye_off.png"), QStringLiteral("eye_off.png"))
               : loadNamedIcon(QStringLiteral("eye.png"), QStringLiteral("eye.png"));
}
} // namespace Icons
