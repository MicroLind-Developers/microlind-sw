#ifndef MLFS_COMMANDER_MLFS_IMAGE_BACKEND_H
#define MLFS_COMMANDER_MLFS_IMAGE_BACKEND_H

#include "backend/FileBlockDevice.h"
#include "model/DirectoryEntry.h"
#include "model/PartitionInfo.h"
#include "support/OperationResult.h"

#include <QByteArray>
#include <QVector>

class MlfsImageBackend {
public:
    OperationResult createImage(const QString& path, uint32_t sizeMiB);
    OperationResult openImage(const QString& path, bool readOnly);
    void closeImage();

    bool isOpen() const;
    QString imagePath() const;
    OperationResult readPartitions(QVector<PartitionInfo>* partitions);
    OperationResult readDirectory(const PartitionInfo& partition, const QString& path, QVector<DirectoryEntry>* entries);
    OperationResult readFile(const PartitionInfo& partition, const QString& path, size_t maxBytes, QByteArray* data, bool* truncated);
    OperationResult importFile(const PartitionInfo& partition, const QString& path, const QByteArray& data);
    OperationResult addPartition(uint32_t startLba, uint32_t sizeMiB, uint32_t blockSizeBytes, const QString& name);
    OperationResult addPartitionBlocks(uint32_t startLba, uint32_t blockCount, uint32_t blockSizeBytes, const QString& name);
    OperationResult renamePartition(uint16_t partitionIndex, const QString& name);
    OperationResult deletePartition(uint16_t partitionIndex);
    OperationResult formatPartition(uint16_t partitionIndex);
    OperationResult createEmptyFile(const PartitionInfo& partition, const QString& path);
    OperationResult createDirectory(const PartitionInfo& partition, const QString& path);
    OperationResult renameEntry(const PartitionInfo& partition, const QString& oldPath, const QString& newPath);
    OperationResult deleteEntry(const PartitionInfo& partition, const QString& path, const DirectoryEntry& entry);

private:
    static QString partitionName(const mlpt_entry_t& entry);
    static QString partitionName(const char* name, size_t maxLength);
    static int log2BlockSize(uint32_t blockSizeBytes);
    static QString entryName(const char* name, size_t maxLength);
    static QStringList splitPath(const QString& path);
    static DirectoryEntry fromMlfsDentry(const mlfs_dentry_t& dentry);

    OperationResult readCurrentDirectory(const PartitionInfo& partition, const QString& path, QVector<DirectoryEntry>* entries);
    OperationResult readCurrentFile(const PartitionInfo& partition, const QString& path, size_t maxBytes, QByteArray* data, bool* truncated);
    OperationResult importCurrentFile(const PartitionInfo& partition, const QString& path, const QByteArray& data);
    OperationResult createCurrentEmptyFile(const PartitionInfo& partition, const QString& path);
    OperationResult createCurrentDirectory(const PartitionInfo& partition, const QString& path);
    OperationResult renameCurrentEntry(const PartitionInfo& partition, const QString& oldPath, const QString& newPath);
    OperationResult deleteCurrentEntry(const PartitionInfo& partition, const QString& path, const DirectoryEntry& entry);

    FileBlockDevice device_;
};

#endif
