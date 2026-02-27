#pragma once

#include <QWidget>
#include <memory>

#include "../../core/KeeneticClient.h"
#include "../../core/Models.h"

class QLabel;
class QTableWidget;

class MePage : public QWidget {
    Q_OBJECT

public:
    explicit MePage(QWidget *parent = nullptr);

    void setContext(const RouterInfo &router, const std::shared_ptr<KeeneticClient> &client);
    void refresh();
    void setSortState(int column, Qt::SortOrder order);

Q_SIGNALS:
    void tableSortChanged(int column, Qt::SortOrder order);

private:
    RouterInfo router_;
    std::shared_ptr<KeeneticClient> client_;

    QLabel *statusLabel_;
    QTableWidget *table_;
};
