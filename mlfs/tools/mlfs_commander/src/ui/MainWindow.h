#ifndef MLFS_COMMANDER_MAIN_WINDOW_H
#define MLFS_COMMANDER_MAIN_WINDOW_H

#include "backend/MlfsImageBackend.h"
#include "model/DirectoryEntry.h"
#include "model/PartitionInfo.h"

#include <QMainWindow>
#include <QVector>

class QAction;
class QByteArray;
class QDragEnterEvent;
class QDropEvent;
class QLabel;
class QPoint;
class QTableWidget;
class QTextEdit;
class QTreeWidget;
class QTreeWidgetItem;

class MainWindow : public QMainWindow {
public:
    explicit MainWindow(QWidget* parent = nullptr);

private:
    void dragEnterEvent(QDragEnterEvent* event) override;
    void dropEvent(QDropEvent* event) override;

    enum class NodeType {
        Section,
        Image,
        Partition,
        Directory,
    };

    void setupActions();
    void setupLayout();
    void resetNavigation();

    void newImage();
    void openImage();
    void closeImage();
    void refreshImage();
    void createPartition();
    void renameSelectedPartition();
    void deleteSelectedPartition();
    void formatSelectedPartition();
    void handleSelectionChanged();
    void handleListActivated(int row);
    void showTreeContextMenu(const QPoint& pos);
    void showListContextMenu(const QPoint& pos);
    void exportSelectedFile();
    void importFiles();
    void importFiles(const QStringList& paths);
    void createEmptyFile();
    void createDirectory();
    void renameSelectedEntry();
    void deleteSelectedEntry();
    void updateEntryActions();

    void loadImageIntoViews();
    void populatePartitionTable();
    void populateDirectoryTable(const QVector<DirectoryEntry>& entries);
    void loadDirectory(QTreeWidgetItem* item, const PartitionInfo& partition, const QString& path);
    QTreeWidgetItem* findPartitionItem(int partitionIndex) const;
    void rebuildDirectoryChildren(QTreeWidgetItem* parent, const QVector<DirectoryEntry>& entries, int partitionIndex, const QString& path);
    void showImageDetails();
    void showPartitionDetails(const PartitionInfo& partition);
    void showDirectoryDetails(const PartitionInfo& partition, const QString& path, const QVector<DirectoryEntry>& entries);
    void previewFile(const PartitionInfo& partition, const DirectoryEntry& entry, const QString& path);
    void setDetails(const QString& text);
    void setStatus(const QString& text);
    void showError(const QString& title, const OperationResult& result);

    int selectedEntryIndex() const;
    int selectedPartitionIndex() const;
    bool canCreatePartition() const;
    uint32_t suggestedStartLba() const;
    uint32_t firstAvailableStartLba(uint32_t blockCount, uint32_t blockSizeBytes) const;
    uint64_t imageSectorCount() const;
    bool canImportIntoCurrentDirectory() const;
    bool canModifyCurrentDirectory() const;
    bool currentDirectoryContains(const QString& name) const;

    static QString formatBytes(uint64_t bytes);
    static QString formatTimestamp(uint32_t timestamp);
    static QString partitionTypeName(const PartitionInfo& partition);
    static QString entryTypeName(const DirectoryEntry& entry);
    static QString joinPath(const QString& parent, const QString& child);
    static QString previewText(const QByteArray& data);
    static NodeType nodeType(const QTreeWidgetItem* item);
    static int partitionIndex(const QTreeWidgetItem* item);
    static QString itemPath(const QTreeWidgetItem* item);

    MlfsImageBackend imageBackend_;
    QVector<PartitionInfo> partitions_;
    QVector<DirectoryEntry> currentEntries_;
    int currentPartitionIndex_ = -1;
    QString currentPath_ = "/";
    QTreeWidgetItem* currentDirectoryItem_ = nullptr;

    QTreeWidget* tree_ = nullptr;
    QTableWidget* list_ = nullptr;
    QTextEdit* details_ = nullptr;
    QLabel* status_ = nullptr;
    QTreeWidgetItem* imagesRoot_ = nullptr;

    QAction* openImageAction_ = nullptr;
    QAction* newImageAction_ = nullptr;
    QAction* closeImageAction_ = nullptr;
    QAction* refreshAction_ = nullptr;
    QAction* createPartitionAction_ = nullptr;
    QAction* renamePartitionAction_ = nullptr;
    QAction* deletePartitionAction_ = nullptr;
    QAction* formatPartitionAction_ = nullptr;
    QAction* createFileAction_ = nullptr;
    QAction* createDirectoryAction_ = nullptr;
    QAction* importFileAction_ = nullptr;
    QAction* exportFileAction_ = nullptr;
    QAction* renameEntryAction_ = nullptr;
    QAction* deleteEntryAction_ = nullptr;
    QAction* quitAction_ = nullptr;
};

#endif
