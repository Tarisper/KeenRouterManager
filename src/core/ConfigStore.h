#pragma once

#include <QList>

#include "Models.h"

class ConfigStore {
public:
    static QList<RouterInfo> loadRouters();
    static bool saveRouters(const QList<RouterInfo> &routers);
    static QList<RouterInfo> importRoutersFromFile(const QString &filePath, bool *ok = nullptr);
    static bool exportRoutersToFile(const QList<RouterInfo> &routers, const QString &filePath);

    static AppSettings loadAppSettings();
    static bool saveAppSettings(const AppSettings &settings);
};
