#include "ui/MainWindow.h"

#include <QAction>
#include <QApplication>
#include <QFileDialog>
#include <QFile>
#include <QFileInfo>
#include <QHeaderView>
#include <QInputDialog>
#include <QLabel>
#include <QMenuBar>
#include <QMenu>
#include <QMessageBox>
#include <QByteArray>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QSplitter>
#include <QStatusBar>
#include <QStyle>
#include <QTableWidget>
#include <QTextEdit>
#include <QToolBar>
#include <QTreeWidget>
#include <QMimeData>
#include <QPushButton>
#include <QUrl>
#include <QVBoxLayout>
#include <QDateTime>
#include <QCheckBox>
#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QLineEdit>
#include <QSpinBox>

#include <algorithm>
#include <limits>

namespace {
constexpr int RoleNodeType = Qt::UserRole;
constexpr int RolePartitionIndex = Qt::UserRole + 1;
constexpr int RolePath = Qt::UserRole + 2;
constexpr int RoleEntryIndex = Qt::UserRole + 3;
}

MainWindow::MainWindow(QWidget* parent)
    : QMainWindow(parent)
{
    setupActions();
    setupLayout();
    resetNavigation();
    setAcceptDrops(true);

    setWindowTitle("MLFS Commander");
    resize(1080, 680);
    setStatus("Ready");
}

void MainWindow::setupActions()
{
    newImageAction_ = new QAction(style()->standardIcon(QStyle::SP_FileIcon), "New Image...", this);
    openImageAction_ = new QAction(style()->standardIcon(QStyle::SP_DialogOpenButton), "Open Image...", this);
    closeImageAction_ = new QAction(style()->standardIcon(QStyle::SP_DialogCloseButton), "Close Image", this);
    refreshAction_ = new QAction(style()->standardIcon(QStyle::SP_BrowserReload), "Refresh", this);
    createPartitionAction_ = new QAction(style()->standardIcon(QStyle::SP_FileDialogNewFolder), "New Partition...", this);
    renamePartitionAction_ = new QAction("Rename Selected Partition...", this);
    deletePartitionAction_ = new QAction(style()->standardIcon(QStyle::SP_TrashIcon), "Delete Selected Partition", this);
    formatPartitionAction_ = new QAction("Format Selected Partition", this);
    createFileAction_ = new QAction(style()->standardIcon(QStyle::SP_FileIcon), "New File...", this);
    createDirectoryAction_ = new QAction(style()->standardIcon(QStyle::SP_FileDialogNewFolder), "New Directory...", this);
    importFileAction_ = new QAction(style()->standardIcon(QStyle::SP_ArrowDown), "Import File...", this);
    exportFileAction_ = new QAction(style()->standardIcon(QStyle::SP_DialogSaveButton), "Export Selected File...", this);
    renameEntryAction_ = new QAction("Rename Selected...", this);
    deleteEntryAction_ = new QAction(style()->standardIcon(QStyle::SP_TrashIcon), "Delete Selected", this);
    quitAction_ = new QAction("Quit", this);

    closeImageAction_->setEnabled(false);
    refreshAction_->setEnabled(false);
    createPartitionAction_->setEnabled(false);
    renamePartitionAction_->setEnabled(false);
    deletePartitionAction_->setEnabled(false);
    formatPartitionAction_->setEnabled(false);
    createFileAction_->setEnabled(false);
    createDirectoryAction_->setEnabled(false);
    importFileAction_->setEnabled(false);
    exportFileAction_->setEnabled(false);
    renameEntryAction_->setEnabled(false);
    deleteEntryAction_->setEnabled(false);

    connect(newImageAction_, &QAction::triggered, this, [this]() { newImage(); });
    connect(openImageAction_, &QAction::triggered, this, [this]() { openImage(); });
    connect(closeImageAction_, &QAction::triggered, this, [this]() { closeImage(); });
    connect(refreshAction_, &QAction::triggered, this, [this]() { refreshImage(); });
    connect(createPartitionAction_, &QAction::triggered, this, [this]() { createPartition(); });
    connect(renamePartitionAction_, &QAction::triggered, this, [this]() { renameSelectedPartition(); });
    connect(deletePartitionAction_, &QAction::triggered, this, [this]() { deleteSelectedPartition(); });
    connect(formatPartitionAction_, &QAction::triggered, this, [this]() { formatSelectedPartition(); });
    connect(createFileAction_, &QAction::triggered, this, [this]() { createEmptyFile(); });
    connect(createDirectoryAction_, &QAction::triggered, this, [this]() { createDirectory(); });
    connect(importFileAction_, &QAction::triggered, this, [this]() { importFiles(); });
    connect(exportFileAction_, &QAction::triggered, this, [this]() { exportSelectedFile(); });
    connect(renameEntryAction_, &QAction::triggered, this, [this]() { renameSelectedEntry(); });
    connect(deleteEntryAction_, &QAction::triggered, this, [this]() { deleteSelectedEntry(); });
    connect(quitAction_, &QAction::triggered, qApp, &QApplication::quit);
}

void MainWindow::setupLayout()
{
    auto* fileMenu = menuBar()->addMenu("File");
    fileMenu->addAction(newImageAction_);
    fileMenu->addAction(openImageAction_);
    fileMenu->addAction(closeImageAction_);
    fileMenu->addSeparator();
    fileMenu->addAction(createPartitionAction_);
    fileMenu->addAction(renamePartitionAction_);
    fileMenu->addAction(deletePartitionAction_);
    fileMenu->addAction(formatPartitionAction_);
    fileMenu->addSeparator();
    fileMenu->addAction(createFileAction_);
    fileMenu->addAction(createDirectoryAction_);
    fileMenu->addAction(importFileAction_);
    fileMenu->addAction(exportFileAction_);
    fileMenu->addAction(renameEntryAction_);
    fileMenu->addAction(deleteEntryAction_);
    fileMenu->addSeparator();
    fileMenu->addAction(quitAction_);

    auto* viewMenu = menuBar()->addMenu("View");
    viewMenu->addAction(refreshAction_);

    auto* toolbar = addToolBar("Main");
    toolbar->setMovable(false);
    toolbar->addAction(newImageAction_);
    toolbar->addAction(openImageAction_);
    toolbar->addAction(refreshAction_);
    toolbar->addAction(createPartitionAction_);
    toolbar->addAction(formatPartitionAction_);
    toolbar->addAction(createFileAction_);
    toolbar->addAction(createDirectoryAction_);
    toolbar->addAction(importFileAction_);
    toolbar->addAction(exportFileAction_);
    toolbar->addAction(renameEntryAction_);
    toolbar->addAction(deleteEntryAction_);
    toolbar->addAction(closeImageAction_);

    tree_ = new QTreeWidget(this);
    tree_->setHeaderHidden(true);
    tree_->setMinimumWidth(260);
    tree_->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(tree_, &QTreeWidget::itemSelectionChanged, this, [this]() { handleSelectionChanged(); });
    connect(tree_, &QTreeWidget::customContextMenuRequested, this, [this](const QPoint& pos) { showTreeContextMenu(pos); });

    list_ = new QTableWidget(this);
    list_->setColumnCount(7);
    list_->setHorizontalHeaderLabels({"Name", "Type", "Start LBA", "End LBA", "Blocks", "Block Size", "Size"});
    list_->horizontalHeader()->setStretchLastSection(true);
    list_->verticalHeader()->setVisible(false);
    list_->setEditTriggers(QAbstractItemView::NoEditTriggers);
    list_->setSelectionBehavior(QAbstractItemView::SelectRows);
    list_->setSelectionMode(QAbstractItemView::SingleSelection);
    list_->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(list_, &QTableWidget::cellDoubleClicked, this, [this](int row, int) { handleListActivated(row); });
    connect(list_, &QTableWidget::itemSelectionChanged, this, [this]() { updateEntryActions(); });
    connect(list_, &QTableWidget::customContextMenuRequested, this, [this](const QPoint& pos) { showListContextMenu(pos); });

    details_ = new QTextEdit(this);
    details_->setReadOnly(true);
    details_->setMinimumHeight(150);

    auto* rightSplitter = new QSplitter(Qt::Vertical, this);
    rightSplitter->addWidget(list_);
    rightSplitter->addWidget(details_);
    rightSplitter->setStretchFactor(0, 4);
    rightSplitter->setStretchFactor(1, 1);

    auto* mainSplitter = new QSplitter(Qt::Horizontal, this);
    mainSplitter->addWidget(tree_);
    mainSplitter->addWidget(rightSplitter);
    mainSplitter->setStretchFactor(0, 1);
    mainSplitter->setStretchFactor(1, 4);
    setCentralWidget(mainSplitter);

    status_ = new QLabel(this);
    statusBar()->addPermanentWidget(status_, 1);
}

void MainWindow::resetNavigation()
{
    tree_->clear();

    imagesRoot_ = new QTreeWidgetItem(tree_, {"Images"});
    imagesRoot_->setData(0, RoleNodeType, static_cast<int>(NodeType::Section));
    imagesRoot_->setIcon(0, style()->standardIcon(QStyle::SP_FileDialogDetailedView));

    tree_->expandAll();
    list_->setRowCount(0);
    updateEntryActions();
    setDetails("Open an MLFS image to begin.");
}

void MainWindow::newImage()
{
    const QString path = QFileDialog::getSaveFileName(
        this,
        "New MLFS Image",
        QString(),
        "Disk images (*.img *.mlfs);;All files (*)");
    if(path.isEmpty()) {
        return;
    }

    bool accepted = false;
    const int sizeMiB = QInputDialog::getInt(
        this,
        "New MLFS Image",
        "Image size (MiB):",
        64,
        1,
        2048,
        1,
        &accepted);
    if(!accepted) {
        return;
    }

    const OperationResult result = imageBackend_.createImage(path, static_cast<uint32_t>(sizeMiB));
    if(!result.ok) {
        showError("Create Image Failed", result);
        return;
    }

    loadImageIntoViews();
    setStatus(result.message);
}

void MainWindow::dragEnterEvent(QDragEnterEvent* event)
{
    if(event->mimeData()->hasUrls() && canImportIntoCurrentDirectory()) {
        event->acceptProposedAction();
        return;
    }

    event->ignore();
}

void MainWindow::dropEvent(QDropEvent* event)
{
    if(!event->mimeData()->hasUrls() || !canImportIntoCurrentDirectory()) {
        event->ignore();
        return;
    }

    QStringList paths;
    for(const QUrl& url : event->mimeData()->urls()) {
        if(url.isLocalFile()) {
            paths.append(url.toLocalFile());
        }
    }

    if(paths.isEmpty()) {
        event->ignore();
        return;
    }

    event->acceptProposedAction();
    importFiles(paths);
}

void MainWindow::openImage()
{
    const QString path = QFileDialog::getOpenFileName(
        this,
        "Open MLFS Image",
        QString(),
        "Disk images (*.img *.mlfs);;All files (*)");
    if(path.isEmpty()) {
        return;
    }

    const OperationResult openResult = imageBackend_.openImage(path, false);
    if(!openResult.ok) {
        showError("Open Image Failed", openResult);
        return;
    }

    loadImageIntoViews();
}

void MainWindow::closeImage()
{
    imageBackend_.closeImage();
    partitions_.clear();
    currentEntries_.clear();
    currentPartitionIndex_ = -1;
    currentPath_ = "/";
    currentDirectoryItem_ = nullptr;
    closeImageAction_->setEnabled(false);
    refreshAction_->setEnabled(false);
    createPartitionAction_->setEnabled(false);
    renamePartitionAction_->setEnabled(false);
    deletePartitionAction_->setEnabled(false);
    formatPartitionAction_->setEnabled(false);
    createFileAction_->setEnabled(false);
    createDirectoryAction_->setEnabled(false);
    importFileAction_->setEnabled(false);
    exportFileAction_->setEnabled(false);
    renameEntryAction_->setEnabled(false);
    deleteEntryAction_->setEnabled(false);
    resetNavigation();
    setStatus("Image closed");
}

void MainWindow::refreshImage()
{
    if(!imageBackend_.isOpen()) {
        return;
    }

    loadImageIntoViews();
}

void MainWindow::createPartition()
{
    if(!canCreatePartition()) {
        return;
    }

    QDialog dialog(this);
    dialog.setWindowTitle("New MLFS Partition");

    auto* layout = new QFormLayout(&dialog);
    auto* nameEdit = new QLineEdit("main", &dialog);
    auto* startSpin = new QSpinBox(&dialog);
    startSpin->setRange(1, std::numeric_limits<int>::max());

    auto* sizeSpin = new QSpinBox(&dialog);
    sizeSpin->setRange(1, 2048);
    sizeSpin->setValue(32);

    auto* sizeModeCombo = new QComboBox(&dialog);
    sizeModeCombo->addItem("MiB", "mib");
    sizeModeCombo->addItem("Blocks", "blocks");

    auto* blockSizeCombo = new QComboBox(&dialog);
    for(int size : {512, 1024, 2048, 4096, 8192, 16384, 32768, 65536}) {
        blockSizeCombo->addItem(QString::number(size), size);
    }
    blockSizeCombo->setCurrentText("4096");

    auto* formatCheck = new QCheckBox("Format partition after creation", &dialog);
    formatCheck->setChecked(true);

    auto* validationLabel = new QLabel(&dialog);
    validationLabel->setWordWrap(true);

    layout->addRow("Name:", nameEdit);
    layout->addRow("Start LBA:", startSpin);
    layout->addRow("Size mode:", sizeModeCombo);
    layout->addRow("Size:", sizeSpin);
    layout->addRow("Block size:", blockSizeCombo);
    layout->addRow(QString(), formatCheck);
    layout->addRow("End LBA:", validationLabel);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    layout->addRow(buttons);
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);

    auto blockCountFromDialog = [sizeSpin, sizeModeCombo, blockSizeCombo]() -> uint64_t {
        const uint64_t sizeValue = static_cast<uint64_t>(sizeSpin->value());
        const uint64_t blockSize = static_cast<uint64_t>(blockSizeCombo->currentData().toUInt());
        if(sizeModeCombo->currentData().toString() == "blocks") {
            return sizeValue;
        }
        return blockSize == 0 ? 0 : (sizeValue * 1024 * 1024) / blockSize;
    };

    auto validatePartition = [this, startSpin, sizeSpin, sizeModeCombo, blockSizeCombo, validationLabel, buttons, blockCountFromDialog]() {
        const uint64_t startLba = static_cast<uint64_t>(startSpin->value());
        const uint64_t sizeValue = static_cast<uint64_t>(sizeSpin->value());
        const bool sizeInBlocks = sizeModeCombo->currentData().toString() == "blocks";
        const uint64_t blockSize = static_cast<uint64_t>(blockSizeCombo->currentData().toUInt());
        const uint64_t requestedBytes = sizeInBlocks ? 0 : sizeValue * 1024 * 1024;
        const uint64_t blockCount = blockCountFromDialog();
        const uint64_t sizeBytes = blockCount * blockSize;
        const uint64_t sectorsPerBlock = blockSize == 0 ? 0 : blockSize / 512;
        const uint64_t sectorCount = blockCount * sectorsPerBlock;
        const uint64_t endExclusive = startLba + sectorCount;
        const uint64_t imageSectors = imageSectorCount();

        QString message;
        bool valid = true;
        if(blockSize == 0 || sectorsPerBlock == 0) {
            valid = false;
            message = "Invalid block size.";
        } else if(blockCount == 0) {
            valid = false;
            message = "Selected size is too small for the selected block size.";
        } else if(blockCount > std::numeric_limits<uint32_t>::max()) {
            valid = false;
            message = "Partition block count is too large for MLPT.";
        } else if(!sizeInBlocks && requestedBytes % blockSize != 0) {
            valid = false;
            message = "Selected size must be an exact multiple of the selected block size.";
        } else if(endExclusive > std::numeric_limits<uint32_t>::max()) {
            valid = false;
            message = "Partition end LBA is too large for MLPT.";
        } else if(imageSectors == 0 || endExclusive > imageSectors) {
            valid = false;
            message = QString("Partition would end at LBA %1, beyond image end LBA %2.")
                          .arg(endExclusive == 0 ? 0 : endExclusive - 1)
                          .arg(imageSectors == 0 ? 0 : imageSectors - 1);
        } else {
            for(const PartitionInfo& partition : partitions_) {
                const uint64_t existingStart = partition.startLba;
                const uint64_t existingEnd = partition.endLbaExclusive();
                if(startLba < existingEnd && endExclusive > existingStart) {
                    valid = false;
                    message = QString("Partition overlaps partition %1 (%2-%3).")
                                  .arg(partition.index)
                                  .arg(existingStart)
                                  .arg(partition.endLba());
                    break;
                }
            }
        }

        if(valid) {
            message = QString("%1 blocks, %2, end LBA %3.")
                          .arg(blockCount)
                          .arg(formatBytes(sizeBytes))
                          .arg(endExclusive - 1);
        }

        validationLabel->setText(message);
        buttons->button(QDialogButtonBox::Ok)->setEnabled(valid);
    };

    auto configureSizeSpin = [sizeSpin, sizeModeCombo, blockSizeCombo]() {
        const uint64_t mib = 1024 * 1024;
        const uint64_t blockSize = static_cast<uint64_t>(blockSizeCombo->currentData().toUInt());
        if(sizeModeCombo->currentData().toString() == "blocks") {
            const uint64_t currentMiB = static_cast<uint64_t>(sizeSpin->value());
            const uint64_t blocks = blockSize == 0 ? 1 : (currentMiB * mib) / blockSize;
            sizeSpin->setRange(1, std::numeric_limits<int>::max());
            sizeSpin->setValue(static_cast<int>(std::min<uint64_t>(std::max<uint64_t>(1, blocks), static_cast<uint64_t>(std::numeric_limits<int>::max()))));
            return;
        }

        const uint64_t currentBlocks = static_cast<uint64_t>(sizeSpin->value());
        const uint64_t bytes = currentBlocks * blockSize;
        const uint64_t roundedMiB = std::max<uint64_t>(1, (bytes + mib - 1) / mib);
        sizeSpin->setRange(1, 2048);
        sizeSpin->setValue(static_cast<int>(std::min<uint64_t>(roundedMiB, 2048)));
    };

    auto setFirstAvailableStart = [this, startSpin, blockSizeCombo, validatePartition, blockCountFromDialog]() {
        const uint32_t firstAvailable = firstAvailableStartLba(
            static_cast<uint32_t>(std::min<uint64_t>(blockCountFromDialog(), static_cast<uint64_t>(std::numeric_limits<uint32_t>::max()))),
            static_cast<uint32_t>(blockSizeCombo->currentData().toUInt()));
        startSpin->setValue(static_cast<int>(std::min<uint32_t>(firstAvailable, static_cast<uint32_t>(std::numeric_limits<int>::max()))));
        validatePartition();
    };

    connect(sizeSpin, qOverload<int>(&QSpinBox::valueChanged), &dialog, [setFirstAvailableStart](int) { setFirstAvailableStart(); });
    connect(sizeModeCombo, &QComboBox::currentIndexChanged, &dialog, [configureSizeSpin, setFirstAvailableStart](int) {
        configureSizeSpin();
        setFirstAvailableStart();
    });
    connect(blockSizeCombo, &QComboBox::currentIndexChanged, &dialog, [setFirstAvailableStart](int) { setFirstAvailableStart(); });
    connect(startSpin, qOverload<int>(&QSpinBox::valueChanged), &dialog, [validatePartition](int) { validatePartition(); });
    setFirstAvailableStart();

    if(dialog.exec() != QDialog::Accepted) {
        return;
    }

    const QString name = nameEdit->text().trimmed();
    if(name.isEmpty() || name.contains('/')) {
        showError("Create Partition Failed", OperationResult::failure(-1, "Partition name must be non-empty and cannot contain '/'"));
        return;
    }

    const uint16_t newIndex = static_cast<uint16_t>(partitions_.size());
    OperationResult result = imageBackend_.addPartitionBlocks(
        static_cast<uint32_t>(startSpin->value()),
        static_cast<uint32_t>(blockCountFromDialog()),
        static_cast<uint32_t>(blockSizeCombo->currentData().toUInt()),
        name);
    if(!result.ok) {
        showError("Create Partition Failed", result);
        return;
    }

    if(formatCheck->isChecked()) {
        result = imageBackend_.formatPartition(newIndex);
        if(!result.ok) {
            loadImageIntoViews();
            showError("Format Partition Failed", result);
            return;
        }
    }

    loadImageIntoViews();
    setStatus(QString("Created partition '%1'").arg(name));
}

void MainWindow::formatSelectedPartition()
{
    const int index = selectedPartitionIndex();
    if(index < 0 || index >= partitions_.size()) {
        return;
    }

    const QMessageBox::StandardButton answer = QMessageBox::question(
        this,
        "Format Partition",
        QString("Format partition %1? Existing filesystem data in this partition will be erased.").arg(index),
        QMessageBox::Yes | QMessageBox::No,
        QMessageBox::No);
    if(answer != QMessageBox::Yes) {
        return;
    }

    const OperationResult result = imageBackend_.formatPartition(static_cast<uint16_t>(index));
    if(!result.ok) {
        showError("Format Partition Failed", result);
        return;
    }

    loadImageIntoViews();
    setStatus(result.message);
}

void MainWindow::renameSelectedPartition()
{
    const int index = selectedPartitionIndex();
    if(index < 0 || index >= partitions_.size()) {
        return;
    }

    bool accepted = false;
    const QString name = QInputDialog::getText(
        this,
        "Rename Partition",
        "Partition name:",
        QLineEdit::Normal,
        partitions_.at(index).name,
        &accepted).trimmed();
    if(!accepted || name.isEmpty()) {
        return;
    }
    if(name.contains('/')) {
        showError("Rename Partition Failed", OperationResult::failure(-1, "Partition name cannot contain '/'"));
        return;
    }

    const OperationResult result = imageBackend_.renamePartition(static_cast<uint16_t>(index), name);
    if(!result.ok) {
        showError("Rename Partition Failed", result);
        return;
    }

    loadImageIntoViews();
    setStatus(result.message);
}

void MainWindow::deleteSelectedPartition()
{
    const int index = selectedPartitionIndex();
    if(index < 0 || index >= partitions_.size()) {
        return;
    }

    const QMessageBox::StandardButton answer = QMessageBox::question(
        this,
        "Delete Partition",
        QString("Remove partition %1 (%2) from the MLPT? Filesystem data is not wiped, but the partition will no longer be listed.")
            .arg(index)
            .arg(partitions_.at(index).name),
        QMessageBox::Yes | QMessageBox::No,
        QMessageBox::No);
    if(answer != QMessageBox::Yes) {
        return;
    }

    const OperationResult result = imageBackend_.deletePartition(static_cast<uint16_t>(index));
    if(!result.ok) {
        showError("Delete Partition Failed", result);
        return;
    }

    loadImageIntoViews();
    setStatus(result.message);
}

void MainWindow::handleSelectionChanged()
{
    const QList<QTreeWidgetItem*> selected = tree_->selectedItems();
    if(selected.isEmpty()) {
        return;
    }

    const QTreeWidgetItem* item = selected.first();
    switch(nodeType(item)) {
    case NodeType::Image:
        populatePartitionTable();
        showImageDetails();
        break;
    case NodeType::Partition: {
        const int index = partitionIndex(item);
        if(index >= 0 && index < partitions_.size()) {
            loadDirectory(const_cast<QTreeWidgetItem*>(item), partitions_.at(index), "/");
        }
        break;
    }
    case NodeType::Directory: {
        const int index = partitionIndex(item);
        if(index >= 0 && index < partitions_.size()) {
            loadDirectory(const_cast<QTreeWidgetItem*>(item), partitions_.at(index), itemPath(item));
        }
        break;
    }
    case NodeType::Section:
        break;
    }
}

void MainWindow::handleListActivated(int row)
{
    if(currentPartitionIndex_ < 0) {
        if(row < 0 || row >= partitions_.size()) {
            return;
        }

        QTreeWidgetItem* partitionItem = findPartitionItem(partitions_.at(row).index);
        if(partitionItem != nullptr) {
            tree_->setCurrentItem(partitionItem);
            return;
        }

        loadDirectory(nullptr, partitions_.at(row), "/");
        return;
    }

    if(row < 0 || row >= currentEntries_.size() || currentPartitionIndex_ < 0 || currentPartitionIndex_ >= partitions_.size()) {
        return;
    }

    const DirectoryEntry& entry = currentEntries_.at(row);
    const PartitionInfo& partition = partitions_.at(currentPartitionIndex_);
    const QString path = joinPath(currentPath_, entry.name);

    if(entry.isDirectory()) {
        QTreeWidgetItem* target = nullptr;
        if(currentDirectoryItem_ != nullptr) {
            for(int i = 0; i < currentDirectoryItem_->childCount(); ++i) {
                QTreeWidgetItem* child = currentDirectoryItem_->child(i);
                if(itemPath(child) == path) {
                    target = child;
                    break;
                }
            }
        }

        if(target != nullptr) {
            tree_->setCurrentItem(target);
        } else {
            loadDirectory(currentDirectoryItem_, partition, path);
        }
        return;
    }

    if(entry.isFile()) {
        previewFile(partition, entry, path);
    }
}

void MainWindow::showTreeContextMenu(const QPoint& pos)
{
    QTreeWidgetItem* item = tree_->itemAt(pos);
    if(item != nullptr) {
        tree_->setCurrentItem(item);
    }

    QMenu menu(this);
    const NodeType type = nodeType(item);
    if(type == NodeType::Image || type == NodeType::Section) {
        menu.addAction(createPartitionAction_);
    } else if(type == NodeType::Partition) {
        menu.addAction(renamePartitionAction_);
        menu.addAction(formatPartitionAction_);
        menu.addAction(deletePartitionAction_);
    } else if(type == NodeType::Directory) {
        menu.addAction(createFileAction_);
        menu.addAction(createDirectoryAction_);
        menu.addAction(importFileAction_);
    }
    menu.addSeparator();
    menu.addAction(refreshAction_);

    menu.exec(tree_->viewport()->mapToGlobal(pos));
}

void MainWindow::showListContextMenu(const QPoint& pos)
{
    QTableWidgetItem* item = list_->itemAt(pos);
    if(item != nullptr) {
        list_->selectRow(item->row());
    }
    updateEntryActions();

    QMenu menu(this);
    if(currentPartitionIndex_ < 0) {
        menu.addAction(createPartitionAction_);
        menu.addAction(renamePartitionAction_);
        menu.addAction(formatPartitionAction_);
        menu.addAction(deletePartitionAction_);
    } else {
        menu.addAction(createFileAction_);
        menu.addAction(createDirectoryAction_);
        menu.addAction(importFileAction_);
        menu.addSeparator();
        menu.addAction(exportFileAction_);
        menu.addAction(renameEntryAction_);
        menu.addAction(deleteEntryAction_);
    }
    menu.exec(list_->viewport()->mapToGlobal(pos));
}

void MainWindow::exportSelectedFile()
{
    const int entryIndex = selectedEntryIndex();
    if(entryIndex < 0 || entryIndex >= currentEntries_.size() ||
       currentPartitionIndex_ < 0 || currentPartitionIndex_ >= partitions_.size()) {
        return;
    }

    const DirectoryEntry& entry = currentEntries_.at(entryIndex);
    if(!entry.isFile()) {
        return;
    }

    const PartitionInfo& partition = partitions_.at(currentPartitionIndex_);
    const QString sourcePath = joinPath(currentPath_, entry.name);
    const QString targetPath = QFileDialog::getSaveFileName(this, "Export MLFS File", entry.name);
    if(targetPath.isEmpty()) {
        return;
    }

    QByteArray data;
    bool truncated = false;
    const OperationResult result = imageBackend_.readFile(partition, sourcePath, entry.sizeBytes, &data, &truncated);
    if(!result.ok) {
        showError("Export Failed", result);
        return;
    }
    if(truncated) {
        showError("Export Failed", OperationResult::failure(-1, "Internal export limit truncated the file"));
        return;
    }

    QFile output(targetPath);
    if(!output.open(QIODevice::WriteOnly)) {
        showError("Export Failed", OperationResult::failure(output.error(), output.errorString()));
        return;
    }

    const qint64 written = output.write(data);
    if(written != data.size()) {
        showError("Export Failed", OperationResult::failure(output.error(), output.errorString()));
        return;
    }

    setStatus(QString("Exported '%1' to '%2'").arg(sourcePath, targetPath));
}

void MainWindow::importFiles()
{
    if(!canImportIntoCurrentDirectory()) {
        return;
    }

    const QStringList paths = QFileDialog::getOpenFileNames(this, "Import File Into MLFS");
    if(paths.isEmpty()) {
        return;
    }

    importFiles(paths);
}

void MainWindow::importFiles(const QStringList& paths)
{
    if(!canImportIntoCurrentDirectory()) {
        showError("Import Failed", OperationResult::failure(-1, "Select a writable current-format MLFS image directory first"));
        return;
    }

    const PartitionInfo& partition = partitions_.at(currentPartitionIndex_);
    int imported = 0;

    for(const QString& hostPath : paths) {
        QFileInfo fileInfo(hostPath);
        if(!fileInfo.exists() || !fileInfo.isFile()) {
            showError("Import Failed", OperationResult::failure(-1, QString("'%1' is not a regular file").arg(hostPath)));
            continue;
        }

        const QString targetName = fileInfo.fileName();
        if(currentDirectoryContains(targetName)) {
            showError("Import Failed", OperationResult::failure(-1, QString("'%1' already exists in %2").arg(targetName, currentPath_)));
            continue;
        }

        QFile input(hostPath);
        if(!input.open(QIODevice::ReadOnly)) {
            showError("Import Failed", OperationResult::failure(input.error(), input.errorString()));
            continue;
        }

        const QByteArray data = input.readAll();
        if(input.error() != QFile::NoError) {
            showError("Import Failed", OperationResult::failure(input.error(), input.errorString()));
            continue;
        }

        const QString targetPath = joinPath(currentPath_, targetName);
        const OperationResult result = imageBackend_.importFile(partition, targetPath, data);
        if(!result.ok) {
            showError("Import Failed", result);
            continue;
        }

        ++imported;
        setStatus(result.message);
    }

    if(imported > 0) {
        loadDirectory(currentDirectoryItem_, partition, currentPath_);
        setStatus(QString("Imported %1 file(s) into %2").arg(imported).arg(currentPath_));
    }
}

void MainWindow::createDirectory()
{
    if(!canModifyCurrentDirectory()) {
        return;
    }

    bool accepted = false;
    const QString name = QInputDialog::getText(this, "New Directory", "Directory name:", QLineEdit::Normal, QString(), &accepted).trimmed();
    if(!accepted || name.isEmpty()) {
        return;
    }

    if(name.contains('/')) {
        showError("Create Directory Failed", OperationResult::failure(-1, "Directory name cannot contain '/'"));
        return;
    }

    if(currentDirectoryContains(name)) {
        showError("Create Directory Failed", OperationResult::failure(-1, QString("'%1' already exists in %2").arg(name, currentPath_)));
        return;
    }

    const PartitionInfo& partition = partitions_.at(currentPartitionIndex_);
    const QString targetPath = joinPath(currentPath_, name);
    const OperationResult result = imageBackend_.createDirectory(partition, targetPath);
    if(!result.ok) {
        showError("Create Directory Failed", result);
        return;
    }

    loadDirectory(currentDirectoryItem_, partition, currentPath_);
    setStatus(result.message);
}

void MainWindow::createEmptyFile()
{
    if(!canModifyCurrentDirectory()) {
        return;
    }

    bool accepted = false;
    const QString name = QInputDialog::getText(this, "New File", "File name:", QLineEdit::Normal, QString(), &accepted).trimmed();
    if(!accepted || name.isEmpty()) {
        return;
    }

    if(name.contains('/')) {
        showError("Create File Failed", OperationResult::failure(-1, "File name cannot contain '/'"));
        return;
    }

    if(currentDirectoryContains(name)) {
        showError("Create File Failed", OperationResult::failure(-1, QString("'%1' already exists in %2").arg(name, currentPath_)));
        return;
    }

    const PartitionInfo& partition = partitions_.at(currentPartitionIndex_);
    const QString targetPath = joinPath(currentPath_, name);
    const OperationResult result = imageBackend_.createEmptyFile(partition, targetPath);
    if(!result.ok) {
        showError("Create File Failed", result);
        return;
    }

    loadDirectory(currentDirectoryItem_, partition, currentPath_);
    setStatus(result.message);
}

void MainWindow::renameSelectedEntry()
{
    const int entryIndex = selectedEntryIndex();
    if(!canModifyCurrentDirectory() || entryIndex < 0 || entryIndex >= currentEntries_.size()) {
        return;
    }

    const DirectoryEntry entry = currentEntries_.at(entryIndex);
    bool accepted = false;
    const QString newName = QInputDialog::getText(
        this,
        "Rename Selected",
        "New name:",
        QLineEdit::Normal,
        entry.name,
        &accepted).trimmed();
    if(!accepted || newName.isEmpty() || newName == entry.name) {
        return;
    }

    if(newName.contains('/')) {
        showError("Rename Failed", OperationResult::failure(-1, "Name cannot contain '/'"));
        return;
    }

    if(currentDirectoryContains(newName)) {
        showError("Rename Failed", OperationResult::failure(-1, QString("'%1' already exists in %2").arg(newName, currentPath_)));
        return;
    }

    const PartitionInfo& partition = partitions_.at(currentPartitionIndex_);
    const QString oldPath = joinPath(currentPath_, entry.name);
    const QString newPath = joinPath(currentPath_, newName);
    const OperationResult result = imageBackend_.renameEntry(partition, oldPath, newPath);
    if(!result.ok) {
        showError("Rename Failed", result);
        return;
    }

    loadDirectory(currentDirectoryItem_, partition, currentPath_);
    setStatus(result.message);
}

void MainWindow::deleteSelectedEntry()
{
    const int entryIndex = selectedEntryIndex();
    if(!canModifyCurrentDirectory() || entryIndex < 0 || entryIndex >= currentEntries_.size()) {
        return;
    }

    const DirectoryEntry entry = currentEntries_.at(entryIndex);
    const PartitionInfo& partition = partitions_.at(currentPartitionIndex_);
    const QString targetPath = joinPath(currentPath_, entry.name);

    const QString kind = entry.isDirectory() ? "directory" : "file";
    const QMessageBox::StandardButton answer = QMessageBox::question(
        this,
        "Delete Selected",
        QString("Delete %1 '%2'?").arg(kind, targetPath),
        QMessageBox::Yes | QMessageBox::No,
        QMessageBox::No);
    if(answer != QMessageBox::Yes) {
        return;
    }

    const OperationResult result = imageBackend_.deleteEntry(partition, targetPath, entry);
    if(!result.ok) {
        showError("Delete Failed", result);
        return;
    }

    loadDirectory(currentDirectoryItem_, partition, currentPath_);
    setStatus(result.message);
}

void MainWindow::updateEntryActions()
{
    const int partitionIndex = selectedPartitionIndex();
    const int entryIndex = selectedEntryIndex();
    const bool canExport = entryIndex >= 0 &&
                           entryIndex < currentEntries_.size() &&
                           currentEntries_.at(entryIndex).isFile() &&
                           currentPartitionIndex_ >= 0 &&
                           currentPartitionIndex_ < partitions_.size();
    const bool canDelete = entryIndex >= 0 &&
                           entryIndex < currentEntries_.size() &&
                           canModifyCurrentDirectory();
    const bool canRename = canDelete;
    if(createPartitionAction_ != nullptr) {
        createPartitionAction_->setEnabled(canCreatePartition());
    }
    if(renamePartitionAction_ != nullptr) {
        renamePartitionAction_->setEnabled(partitionIndex >= 0 && partitionIndex < partitions_.size());
    }
    if(deletePartitionAction_ != nullptr) {
        deletePartitionAction_->setEnabled(partitionIndex >= 0 && partitionIndex < partitions_.size());
    }
    if(formatPartitionAction_ != nullptr) {
        formatPartitionAction_->setEnabled(partitionIndex >= 0 && partitionIndex < partitions_.size());
    }
    if(createFileAction_ != nullptr) {
        createFileAction_->setEnabled(canModifyCurrentDirectory());
    }
    if(createDirectoryAction_ != nullptr) {
        createDirectoryAction_->setEnabled(canModifyCurrentDirectory());
    }
    if(importFileAction_ != nullptr) {
        importFileAction_->setEnabled(canImportIntoCurrentDirectory());
    }
    if(exportFileAction_ != nullptr) {
        exportFileAction_->setEnabled(canExport);
    }
    if(renameEntryAction_ != nullptr) {
        renameEntryAction_->setEnabled(canRename);
    }
    if(deleteEntryAction_ != nullptr) {
        deleteEntryAction_->setEnabled(canDelete);
    }
}

void MainWindow::loadImageIntoViews()
{
    const OperationResult result = imageBackend_.readPartitions(&partitions_);
    if(!result.ok) {
        showError("Read Partitions Failed", result);
        return;
    }

    resetNavigation();

    auto* imageItem = new QTreeWidgetItem(imagesRoot_, {QFileInfo(imageBackend_.imagePath()).fileName()});
    imageItem->setData(0, RoleNodeType, static_cast<int>(NodeType::Image));
    imageItem->setToolTip(0, imageBackend_.imagePath());
    imageItem->setIcon(0, style()->standardIcon(QStyle::SP_FileIcon));

    for(const PartitionInfo& partition : partitions_) {
        const QString label = QString("Partition %1: %2").arg(partition.index).arg(partition.name);
        auto* partitionItem = new QTreeWidgetItem(imageItem, {label});
        partitionItem->setData(0, RoleNodeType, static_cast<int>(NodeType::Partition));
        partitionItem->setData(0, RolePartitionIndex, partition.index);
        partitionItem->setData(0, RolePath, "/");
        partitionItem->setIcon(0, style()->standardIcon(partition.isMlfs() ? QStyle::SP_DriveHDIcon : QStyle::SP_MessageBoxWarning));
    }

    imagesRoot_->setExpanded(true);
    imageItem->setExpanded(true);
    tree_->setCurrentItem(imageItem);

    populatePartitionTable();
    showImageDetails();

    closeImageAction_->setEnabled(true);
    refreshAction_->setEnabled(true);
    setStatus(result.message);
    updateEntryActions();
}

void MainWindow::populatePartitionTable()
{
    currentEntries_.clear();
    currentPartitionIndex_ = -1;
    currentPath_ = "/";
    currentDirectoryItem_ = nullptr;

    list_->setColumnCount(7);
    list_->setHorizontalHeaderLabels({"Name", "Type", "Start LBA", "End LBA", "Blocks", "Block Size", "Size"});
    list_->setRowCount(partitions_.size());

    for(int row = 0; row < partitions_.size(); ++row) {
        const PartitionInfo& partition = partitions_.at(row);
        const QStringList values = {
            partition.name,
            partitionTypeName(partition),
            QString::number(partition.startLba),
            QString::number(partition.endLba()),
            QString::number(partition.blockCount),
            formatBytes(partition.blockSizeBytes()),
            formatBytes(partition.sizeBytes()),
        };

        for(int col = 0; col < values.size(); ++col) {
            auto* item = new QTableWidgetItem(values.at(col));
            item->setData(Qt::UserRole, partition.index);
            list_->setItem(row, col, item);
        }
    }

    list_->resizeColumnsToContents();
    updateEntryActions();
}

void MainWindow::populateDirectoryTable(const QVector<DirectoryEntry>& entries)
{
    currentEntries_ = entries;

    list_->setColumnCount(7);
    list_->setHorizontalHeaderLabels({"Name", "Type", "Size", "Modified", "Created", "First Block", "Blocks"});
    list_->setRowCount(entries.size());

    for(int row = 0; row < entries.size(); ++row) {
        const DirectoryEntry& entry = entries.at(row);
        const QStringList values = {
            entry.name,
            entryTypeName(entry),
            entry.isDirectory() ? QString() : formatBytes(entry.sizeBytes),
            formatTimestamp(entry.modifiedTime),
            formatTimestamp(entry.createdTime),
            entry.blockCount > 0 ? QString::number(entry.firstBlock) : QString(),
            entry.blockCount > 0 ? QString::number(entry.blockCount) : QString(),
        };

        for(int col = 0; col < values.size(); ++col) {
            auto* item = new QTableWidgetItem(values.at(col));
            item->setData(RoleEntryIndex, row);
            list_->setItem(row, col, item);
        }
    }

    list_->resizeColumnsToContents();
    updateEntryActions();
}

void MainWindow::loadDirectory(QTreeWidgetItem* item, const PartitionInfo& partition, const QString& path)
{
    QVector<DirectoryEntry> entries;
    const OperationResult result = imageBackend_.readDirectory(partition, path, &entries);
    if(!result.ok) {
        showPartitionDetails(partition);
        showError("Read Directory Failed", result);
        return;
    }

    currentPartitionIndex_ = partition.index;
    currentPath_ = path;
    currentDirectoryItem_ = item;
    populateDirectoryTable(entries);
    rebuildDirectoryChildren(item, entries, partition.index, path);
    showDirectoryDetails(partition, path, entries);
    setStatus(result.message);
}

QTreeWidgetItem* MainWindow::findPartitionItem(int partitionIndex) const
{
    if(imagesRoot_ == nullptr) {
        return nullptr;
    }

    for(int imageRow = 0; imageRow < imagesRoot_->childCount(); ++imageRow) {
        QTreeWidgetItem* imageItem = imagesRoot_->child(imageRow);
        for(int partitionRow = 0; partitionRow < imageItem->childCount(); ++partitionRow) {
            QTreeWidgetItem* item = imageItem->child(partitionRow);
            if(nodeType(item) == NodeType::Partition && MainWindow::partitionIndex(item) == partitionIndex) {
                return item;
            }
        }
    }

    return nullptr;
}

void MainWindow::rebuildDirectoryChildren(QTreeWidgetItem* parent, const QVector<DirectoryEntry>& entries, int partitionIndex, const QString& path)
{
    if(parent == nullptr) {
        return;
    }

    parent->takeChildren();

    for(const DirectoryEntry& entry : entries) {
        if(!entry.isDirectory()) {
            continue;
        }

        const QString childPath = path == "/" ? QString("/%1").arg(entry.name) : QString("%1/%2").arg(path, entry.name);
        auto* child = new QTreeWidgetItem(parent, {entry.name});
        child->setData(0, RoleNodeType, static_cast<int>(NodeType::Directory));
        child->setData(0, RolePartitionIndex, partitionIndex);
        child->setData(0, RolePath, childPath);
        child->setIcon(0, style()->standardIcon(QStyle::SP_DirIcon));
    }

    parent->setExpanded(true);
}

void MainWindow::showImageDetails()
{
    QString details = QString("Image\n\nPath: %1\nPartitions: %2\nMode: read/write")
                          .arg(imageBackend_.imagePath())
                          .arg(partitions_.size());
    if(partitions_.isEmpty()) {
        details += "\n\nThis image has an empty MLPT partition table.";
    }
    setDetails(details);
}

void MainWindow::showPartitionDetails(const PartitionInfo& partition)
{
    QString title = QString("Partition %1").arg(partition.index);
    QString details = QString("%1\n\nName: %2\nType: %3\nStart LBA: %4\nEnd LBA: %5\nBlocks: %6\nBlock size: %7\nTotal size: %8")
                          .arg(title)
                          .arg(partition.name)
                          .arg(partitionTypeName(partition))
                          .arg(partition.startLba)
                          .arg(partition.endLba())
                          .arg(partition.blockCount)
                          .arg(formatBytes(partition.blockSizeBytes()))
                          .arg(formatBytes(partition.sizeBytes()));

    setDetails(details);
}

void MainWindow::showDirectoryDetails(const PartitionInfo& partition, const QString& path, const QVector<DirectoryEntry>& entries)
{
    uint32_t directories = 0;
    uint32_t files = 0;
    for(const DirectoryEntry& entry : entries) {
        if(entry.isDirectory()) {
            ++directories;
        } else {
            ++files;
        }
    }

    setDetails(QString("Directory\n\nImage: %1\nPartition: %2 (%3)\nPath: %4\nItems: %5\nDirectories: %6\nFiles: %7")
                   .arg(imageBackend_.imagePath())
                   .arg(partition.index)
                   .arg(partition.name)
                   .arg(path)
                   .arg(entries.size())
                   .arg(directories)
                   .arg(files));
}

void MainWindow::previewFile(const PartitionInfo& partition, const DirectoryEntry& entry, const QString& path)
{
    QByteArray data;
    bool truncated = false;
    const OperationResult result = imageBackend_.readFile(partition, path, 16 * 1024, &data, &truncated);
    if(!result.ok) {
        showError("Read File Failed", result);
        return;
    }

    QString details = QString("File\n\nImage: %1\nPartition: %2 (%3)\nPath: %4\nSize: %5\nPreview bytes: %6%7\n\n%8")
                          .arg(imageBackend_.imagePath())
                          .arg(partition.index)
                          .arg(partition.name)
                          .arg(path)
                          .arg(formatBytes(entry.sizeBytes))
                          .arg(formatBytes(static_cast<uint64_t>(data.size())))
                          .arg(truncated ? " (truncated)" : "")
                          .arg(previewText(data));
    setDetails(details);
    setStatus(result.message);
}

void MainWindow::setDetails(const QString& text)
{
    details_->setPlainText(text);
}

void MainWindow::setStatus(const QString& text)
{
    status_->setText(text);
}

void MainWindow::showError(const QString& title, const OperationResult& result)
{
    QMessageBox::critical(this, title, result.message);
    setStatus(result.message);
}

int MainWindow::selectedEntryIndex() const
{
    if(list_ == nullptr || list_->selectedItems().isEmpty()) {
        return -1;
    }

    const int row = list_->selectedItems().first()->row();
    if(row < 0) {
        return -1;
    }

    QTableWidgetItem* item = list_->item(row, 0);
    if(item == nullptr) {
        return -1;
    }
    return item->data(RoleEntryIndex).toInt();
}

int MainWindow::selectedPartitionIndex() const
{
    if(tree_ != nullptr && !tree_->selectedItems().isEmpty()) {
        QTreeWidgetItem* item = tree_->selectedItems().first();
        const NodeType type = nodeType(item);
        if(type == NodeType::Partition || type == NodeType::Directory) {
            return partitionIndex(item);
        }
    }

    if(currentPartitionIndex_ < 0 && list_ != nullptr && !list_->selectedItems().isEmpty()) {
        const int row = list_->selectedItems().first()->row();
        if(row >= 0 && row < list_->rowCount()) {
            QTableWidgetItem* item = list_->item(row, 0);
            bool ok = false;
            const int index = item != nullptr ? item->data(Qt::UserRole).toInt(&ok) : -1;
            if(ok) {
                return index;
            }
        }
    }

    return -1;
}

bool MainWindow::canCreatePartition() const
{
    return imageBackend_.isOpen() && partitions_.size() < MLPT_MAX_PARTS;
}

uint32_t MainWindow::suggestedStartLba() const
{
    uint32_t next = 1;
    for(const PartitionInfo& partition : partitions_) {
        if(partition.sectorsPerBlock() == 0) {
            continue;
        }
        const uint64_t endLba = partition.endLbaExclusive();
        if(endLba > next && endLba <= std::numeric_limits<uint32_t>::max()) {
            next = static_cast<uint32_t>(endLba);
        }
    }
    return next;
}

uint32_t MainWindow::firstAvailableStartLba(uint32_t blockCount, uint32_t blockSizeBytes) const
{
    if(blockCount == 0 || blockSizeBytes == 0 || blockSizeBytes % 512 != 0) {
        return suggestedStartLba();
    }

    const uint64_t sectorsPerBlock = blockSizeBytes / 512;
    const uint64_t sectorCount = static_cast<uint64_t>(blockCount) * sectorsPerBlock;
    if(sectorCount == 0) {
        return suggestedStartLba();
    }

    uint64_t candidate = 1;
    bool moved = true;
    while(moved) {
        moved = false;
        for(const PartitionInfo& partition : partitions_) {
            const uint64_t existingStart = partition.startLba;
            const uint64_t existingEnd = partition.endLbaExclusive();
            const uint64_t candidateEnd = candidate + sectorCount;
            if(existingEnd == 0) {
                continue;
            }
            if(candidate < existingEnd && candidateEnd > existingStart) {
                candidate = existingEnd;
                moved = true;
            }
        }
    }

    if(candidate > std::numeric_limits<uint32_t>::max()) {
        return std::numeric_limits<uint32_t>::max();
    }
    return static_cast<uint32_t>(candidate);
}

uint64_t MainWindow::imageSectorCount() const
{
    if(!imageBackend_.isOpen()) {
        return 0;
    }

    const qint64 imageBytes = QFileInfo(imageBackend_.imagePath()).size();
    return imageBytes <= 0 ? 0 : static_cast<uint64_t>(imageBytes) / 512;
}

bool MainWindow::canImportIntoCurrentDirectory() const
{
    return canModifyCurrentDirectory();
}

bool MainWindow::canModifyCurrentDirectory() const
{
    return currentPartitionIndex_ >= 0 &&
           currentPartitionIndex_ < partitions_.size() &&
           currentDirectoryItem_ != nullptr;
}

bool MainWindow::currentDirectoryContains(const QString& name) const
{
    for(const DirectoryEntry& entry : currentEntries_) {
        if(entry.name == name) {
            return true;
        }
    }
    return false;
}

QString MainWindow::formatBytes(uint64_t bytes)
{
    static const char* units[] = {"B", "KB", "MB", "GB", "TB"};
    double value = static_cast<double>(bytes);
    int unit = 0;
    while(value >= 1024.0 && unit < 4) {
        value /= 1024.0;
        ++unit;
    }

    if(unit == 0) {
        return QString("%1 B").arg(bytes);
    }
    return QString("%1 %2").arg(value, 0, 'f', 1).arg(units[unit]);
}

QString MainWindow::formatTimestamp(uint32_t timestamp)
{
    if(timestamp == 0) {
        return QString();
    }
    return QDateTime::fromSecsSinceEpoch(timestamp).toString("yyyy-MM-dd HH:mm:ss");
}

QString MainWindow::partitionTypeName(const PartitionInfo& partition)
{
    if(partition.isMlfs()) {
        return "MLFS";
    }
    if(partition.type == 0) {
        return "Unused";
    }
    return QString("Type %1").arg(partition.type);
}

QString MainWindow::entryTypeName(const DirectoryEntry& entry)
{
    if(entry.isDirectory()) {
        return "Directory";
    }
    if(entry.isFile()) {
        return "File";
    }
    return QString("Flags %1").arg(entry.flags);
}

QString MainWindow::joinPath(const QString& parent, const QString& child)
{
    if(parent.isEmpty() || parent == "/") {
        return "/" + child;
    }
    return parent + "/" + child;
}

QString MainWindow::previewText(const QByteArray& data)
{
    if(data.isEmpty()) {
        return "(empty file)";
    }

    int textLike = 0;
    for(char ch : data) {
        const unsigned char c = static_cast<unsigned char>(ch);
        if(c == '\n' || c == '\r' || c == '\t' || (c >= 32 && c < 127)) {
            ++textLike;
        }
    }

    if(textLike >= data.size() * 9 / 10) {
        return QString::fromUtf8(data);
    }

    return data.toHex(' ');
}

MainWindow::NodeType MainWindow::nodeType(const QTreeWidgetItem* item)
{
    if(item == nullptr) {
        return NodeType::Section;
    }
    return static_cast<NodeType>(item->data(0, RoleNodeType).toInt());
}

int MainWindow::partitionIndex(const QTreeWidgetItem* item)
{
    if(item == nullptr) {
        return -1;
    }
    return item->data(0, RolePartitionIndex).toInt();
}

QString MainWindow::itemPath(const QTreeWidgetItem* item)
{
    if(item == nullptr) {
        return "/";
    }
    const QString path = item->data(0, RolePath).toString();
    return path.isEmpty() ? QString("/") : path;
}
