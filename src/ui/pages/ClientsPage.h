#pragma once

#include <QList>
#include <QWidget>
#include <memory>

#include "../../core/KeeneticClient.h"
#include "../../core/Models.h"

class QLineEdit;
class QPushButton;
class QTableWidget;

class ClientsPage : public QWidget {
    Q_OBJECT

public:
    explicit ClientsPage(QWidget *parent = nullptr);

    void setContext(const RouterInfo &router, const std::shared_ptr<KeeneticClient> &client);
    void refresh();
    void setSortState(int column, Qt::SortOrder order);

Q_SIGNALS:
    void tableSortChanged(int column, Qt::SortOrder order);

private:
    void render();

    RouterInfo router_;
    std::shared_ptr<KeeneticClient> client_;
    QList<OnlineClient> clients_;

    QLineEdit *searchEdit_;
    QPushButton *refreshButton_;
    QTableWidget *table_;
};
