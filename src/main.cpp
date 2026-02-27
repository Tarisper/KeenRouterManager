#include <QApplication>

#include "ui/Icons.h"
#include "ui/MainWindow.h"

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    QCoreApplication::setApplicationName("KeenRouterManager");
    QCoreApplication::setOrganizationName("Tarisper");
    const auto icon = Icons::appIcon();
    QApplication::setWindowIcon(icon);

    MainWindow window;
    window.setWindowIcon(icon);
    window.resize(1100, 700);
    window.show();

    return app.exec();
}
