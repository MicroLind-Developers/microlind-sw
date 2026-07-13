#include "backend/MlfsImageBackend.h"

#include <QByteArray>
#include <QFile>
#include <QFileInfo>
#include <cstring>
#include <limits>

OperationResult MlfsImageBackend::createImage(const QString& path, uint32_t sizeMiB)
{
    if(path.isEmpty()) {
        return OperationResult::failure(-1, "Image path is empty");
    }
    if(sizeMiB == 0) {
        return OperationResult::failure(-1, "Image size must be greater than zero");
    }

    closeImage();

    QFile file(path);
    if(!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return OperationResult::failure(file.error(), QString("Failed to create '%1': %2").arg(path, file.errorString()));
    }

    const qint64 sizeBytes = static_cast<qint64>(sizeMiB) * 1024 * 1024;
    if(!file.resize(sizeBytes)) {
        const QString error = file.errorString();
        file.close();
        return OperationResult::failure(file.error(), QString("Failed to size '%1': %2").arg(path, error));
    }
    file.close();

    OperationResult openResult = device_.open(path, false);
    if(!openResult.ok) {
        return openResult;
    }

    mlfs_io_t io = device_.io();
    const int rc = mlfs_make_empty_partition_table(&io);
    if(rc != 0) {
        closeImage();
        return OperationResult::failure(rc, QString("Failed to initialize MLPT partition table (error %1)").arg(rc));
    }

    return OperationResult::success(QString("Created '%1' with an empty MLPT").arg(device_.path()));
}

OperationResult MlfsImageBackend::openImage(const QString& path, bool readOnly)
{
    return device_.open(path, readOnly);
}

void MlfsImageBackend::closeImage()
{
    device_.close();
}

bool MlfsImageBackend::isOpen() const
{
    return device_.isOpen();
}

QString MlfsImageBackend::imagePath() const
{
    return device_.path();
}

OperationResult MlfsImageBackend::readPartitions(QVector<PartitionInfo>* partitions)
{
    if(partitions == nullptr) {
        return OperationResult::failure(-1, "Internal error: no partition output container");
    }

    partitions->clear();

    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    mlpt_t table = {};
    mlfs_io_t io = device_.io();
    const int rc = mlfs_read_mlpt(&io, &table);
    if(rc != 0) {
        return OperationResult::failure(
            rc,
            QString("Failed to read MLPT partition table (error %1). "
                    "The image does not contain a valid current-format MLPT header at sector 0.")
                .arg(rc));
    }

    for(uint16_t i = 0; i < table.count && i < MLPT_MAX_PARTS; ++i) {
        const mlpt_entry_t& entry = table.entries[i];
        PartitionInfo info;
        info.index = i;
        info.name = partitionName(entry);
        info.startLba = entry.start_lba;
        info.blockCount = entry.block_count;
        info.type = entry.type;
        info.log2BlockSize = entry.log2_block_size;
        partitions->append(info);
    }

    return OperationResult::success(QString("Read %1 partition(s)").arg(partitions->size()));
}

OperationResult MlfsImageBackend::readDirectory(const PartitionInfo& partition, const QString& path, QVector<DirectoryEntry>* entries)
{
    if(entries == nullptr) {
        return OperationResult::failure(-1, "Internal error: no directory output container");
    }

    entries->clear();

    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    return readCurrentDirectory(partition, path, entries);
}

OperationResult MlfsImageBackend::readFile(const PartitionInfo& partition, const QString& path, size_t maxBytes, QByteArray* data, bool* truncated)
{
    if(data == nullptr || truncated == nullptr) {
        return OperationResult::failure(-1, "Internal error: no file output container");
    }

    data->clear();
    *truncated = false;

    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    return readCurrentFile(partition, path, maxBytes, data, truncated);
}

OperationResult MlfsImageBackend::importFile(const PartitionInfo& partition, const QString& path, const QByteArray& data)
{
    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    return importCurrentFile(partition, path, data);
}

OperationResult MlfsImageBackend::addPartition(uint32_t startLba, uint32_t sizeMiB, uint32_t blockSizeBytes, const QString& name)
{
    if(sizeMiB == 0) {
        return OperationResult::failure(-1, "Partition size must be greater than zero");
    }
    const int log2Block = log2BlockSize(blockSizeBytes);
    if(log2Block < 9 || log2Block > 16) {
        return OperationResult::failure(-1, "Block size must be a power of two from 512 to 65536 bytes");
    }

    const uint64_t sizeBytes = static_cast<uint64_t>(sizeMiB) * 1024 * 1024;
    const uint64_t blockCount64 = sizeBytes / blockSizeBytes;
    if(blockCount64 > std::numeric_limits<uint32_t>::max()) {
        return OperationResult::failure(-1, "Partition is too large for MLFS");
    }

    return addPartitionBlocks(startLba, static_cast<uint32_t>(blockCount64), blockSizeBytes, name);
}

OperationResult MlfsImageBackend::addPartitionBlocks(uint32_t startLba, uint32_t blockCount, uint32_t blockSizeBytes, const QString& name)
{
    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }
    if(startLba == 0) {
        return OperationResult::failure(-1, "Start LBA must be non-zero");
    }
    if(blockCount == 0) {
        return OperationResult::failure(-1, "Partition block count must be greater than zero");
    }

    const int log2Block = log2BlockSize(blockSizeBytes);
    if(log2Block < 9 || log2Block > 16) {
        return OperationResult::failure(-1, "Block size must be a power of two from 512 to 65536 bytes");
    }

    const QByteArray nameBytes = name.toUtf8();
    if(nameBytes.isEmpty() || nameBytes.size() >= static_cast<int>(sizeof(mlpt_entry_t::name))) {
        return OperationResult::failure(-1, QString("Partition name must be 1-%1 bytes").arg(sizeof(mlpt_entry_t::name) - 1));
    }

    const uint64_t sectorsPerBlock = blockSizeBytes / 512;
    const uint64_t endLbaExclusive = static_cast<uint64_t>(startLba) + static_cast<uint64_t>(blockCount) * sectorsPerBlock;
    if(endLbaExclusive > std::numeric_limits<uint32_t>::max()) {
        return OperationResult::failure(-1, "Partition end LBA is too large for MLPT");
    }

    const qint64 imageBytes = QFileInfo(device_.path()).size();
    if(imageBytes <= 0) {
        return OperationResult::failure(-1, "Could not determine image size");
    }
    const uint64_t imageSectors = static_cast<uint64_t>(imageBytes) / 512;
    if(endLbaExclusive > imageSectors) {
        return OperationResult::failure(
            -1,
            QString("Partition would end at LBA %1, beyond image end LBA %2")
                .arg(endLbaExclusive - 1)
                .arg(imageSectors == 0 ? 0 : imageSectors - 1));
    }

    mlfs_io_t io = device_.io();
    const int rc = mlfs_add_partition(&io, startLba, blockCount, static_cast<uint8_t>(log2Block), nameBytes.constData());
    if(rc != 0) {
        return OperationResult::failure(rc, QString("Failed to create partition '%1' (error %2)").arg(name).arg(rc));
    }

    return OperationResult::success(QString("Created partition '%1'").arg(name));
}

OperationResult MlfsImageBackend::formatPartition(uint16_t partitionIndex)
{
    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    mlfs_t fs = {};
    mlfs_io_t io = device_.io();
    const int rc = mlfs_mkfs(&io, partitionIndex, &fs);
    if(rc != 0) {
        return OperationResult::failure(rc, QString("Failed to format partition %1 (error %2)").arg(partitionIndex).arg(rc));
    }

    return OperationResult::success(QString("Formatted partition %1").arg(partitionIndex));
}

OperationResult MlfsImageBackend::renamePartition(uint16_t partitionIndex, const QString& name)
{
    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    const QByteArray nameBytes = name.toUtf8();
    if(nameBytes.isEmpty() || nameBytes.size() >= static_cast<int>(sizeof(mlpt_entry_t::name))) {
        return OperationResult::failure(-1, QString("Partition name must be 1-%1 bytes").arg(sizeof(mlpt_entry_t::name) - 1));
    }

    mlpt_t table = {};
    mlfs_io_t io = device_.io();
    int rc = mlfs_read_mlpt(&io, &table);
    if(rc != 0) {
        return OperationResult::failure(rc, QString("Failed to read MLPT partition table (error %1)").arg(rc));
    }
    if(partitionIndex >= table.count) {
        return OperationResult::failure(-1, QString("Partition %1 does not exist").arg(partitionIndex));
    }

    std::memset(table.entries[partitionIndex].name, 0, sizeof(table.entries[partitionIndex].name));
    std::strncpy(table.entries[partitionIndex].name, nameBytes.constData(), sizeof(table.entries[partitionIndex].name) - 1);

    rc = mlfs_write_mlpt(&io, &table);
    if(rc != 0) {
        return OperationResult::failure(rc, QString("Failed to rename partition %1 (error %2)").arg(partitionIndex).arg(rc));
    }

    return OperationResult::success(QString("Renamed partition %1 to '%2'").arg(partitionIndex).arg(name));
}

OperationResult MlfsImageBackend::deletePartition(uint16_t partitionIndex)
{
    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    mlpt_t table = {};
    mlfs_io_t io = device_.io();
    int rc = mlfs_read_mlpt(&io, &table);
    if(rc != 0) {
        return OperationResult::failure(rc, QString("Failed to read MLPT partition table (error %1)").arg(rc));
    }
    if(partitionIndex >= table.count) {
        return OperationResult::failure(-1, QString("Partition %1 does not exist").arg(partitionIndex));
    }

    for(uint16_t i = partitionIndex; i + 1 < table.count; ++i) {
        table.entries[i] = table.entries[i + 1];
    }
    if(table.count > 0) {
        std::memset(&table.entries[table.count - 1], 0, sizeof(table.entries[table.count - 1]));
        --table.count;
    }

    rc = mlfs_write_mlpt(&io, &table);
    if(rc != 0) {
        return OperationResult::failure(rc, QString("Failed to delete partition %1 (error %2)").arg(partitionIndex).arg(rc));
    }

    return OperationResult::success(QString("Deleted partition %1 from MLPT").arg(partitionIndex));
}

OperationResult MlfsImageBackend::createEmptyFile(const PartitionInfo& partition, const QString& path)
{
    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    return createCurrentEmptyFile(partition, path);
}

OperationResult MlfsImageBackend::createDirectory(const PartitionInfo& partition, const QString& path)
{
    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    return createCurrentDirectory(partition, path);
}

OperationResult MlfsImageBackend::deleteEntry(const PartitionInfo& partition, const QString& path, const DirectoryEntry& entry)
{
    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    return deleteCurrentEntry(partition, path, entry);
}

OperationResult MlfsImageBackend::renameEntry(const PartitionInfo& partition, const QString& oldPath, const QString& newPath)
{
    if(!device_.isOpen()) {
        return OperationResult::failure(-1, "No image is open");
    }

    return renameCurrentEntry(partition, oldPath, newPath);
}

QString MlfsImageBackend::partitionName(const mlpt_entry_t& entry)
{
    return partitionName(entry.name, sizeof(entry.name));
}

QString MlfsImageBackend::partitionName(const char* name, size_t maxLength)
{
    size_t len = 0;
    while(len < maxLength && name[len] != '\0') {
        ++len;
    }

    if(len == 0) {
        return QString("(unnamed)");
    }

    return QString::fromLatin1(name, static_cast<int>(len));
}

int MlfsImageBackend::log2BlockSize(uint32_t blockSizeBytes)
{
    if(blockSizeBytes == 0) {
        return -1;
    }

    int log2 = 0;
    uint32_t value = blockSizeBytes;
    while(value > 1) {
        if((value & 1U) != 0) {
            return -1;
        }
        value >>= 1;
        ++log2;
    }
    return (1U << log2) == blockSizeBytes ? log2 : -1;
}

QString MlfsImageBackend::entryName(const char* name, size_t maxLength)
{
    size_t len = 0;
    while(len < maxLength && name[len] != '\0') {
        ++len;
    }
    return QString::fromLatin1(name, static_cast<int>(len));
}

QStringList MlfsImageBackend::splitPath(const QString& path)
{
    QString normalized = path;
    if(normalized.startsWith('/')) {
        normalized.remove(0, 1);
    }
    if(normalized.endsWith('/')) {
        normalized.chop(1);
    }
    if(normalized.isEmpty()) {
        return {};
    }
    return normalized.split('/', Qt::SkipEmptyParts);
}

DirectoryEntry MlfsImageBackend::fromMlfsDentry(const mlfs_dentry_t& dentry)
{
    DirectoryEntry entry;
    entry.name = entryName(dentry.name, sizeof(dentry.name));
    entry.flags = dentry.flags;
    entry.sizeBytes = dentry.size_bytes;
    entry.modifiedTime = dentry.mtime;
    entry.createdTime = dentry.ctime;
    if(dentry.extents_used > 0) {
        entry.firstBlock = dentry.extents[0].start;
        entry.blockCount = dentry.extents[0].length;
    }
    return entry;
}

OperationResult MlfsImageBackend::readCurrentDirectory(const PartitionInfo& partition, const QString& path, QVector<DirectoryEntry>* entries)
{
    mlfs_t fs = {};
    mlfs_io_t io = device_.io();
    const int mountResult = mlfs_mount(&io, static_cast<uint16_t>(partition.index), &fs);
    if(mountResult != 0) {
        return OperationResult::failure(mountResult, QString("Failed to mount partition %1 (error %2)")
                                                         .arg(partition.index)
                                                         .arg(mountResult));
    }

    mlfs_dentry_t rawEntries[256] = {};
    uint32_t count = 0;
    const QByteArray pathBytes = path.isEmpty() ? QByteArray("/") : path.toUtf8();
    const int readResult = mlfs_read_directory(&fs, pathBytes.constData(), rawEntries, 256, &count);
    if(readResult != 0) {
        return OperationResult::failure(readResult, QString("Failed to read directory '%1' (error %2)")
                                                        .arg(path)
                                                        .arg(readResult));
    }

    entries->clear();
    for(uint32_t i = 0; i < count; ++i) {
        entries->append(fromMlfsDentry(rawEntries[i]));
    }

    return OperationResult::success(QString("Read %1 item(s) from %2").arg(entries->size()).arg(path));
}

OperationResult MlfsImageBackend::readCurrentFile(const PartitionInfo& partition, const QString& path, size_t maxBytes, QByteArray* data, bool* truncated)
{
    if(maxBytes > static_cast<size_t>(std::numeric_limits<int>::max())) {
        return OperationResult::failure(-1, "File is too large to read into memory in this version");
    }

    mlfs_t fs = {};
    mlfs_io_t io = device_.io();
    const int mountResult = mlfs_mount(&io, static_cast<uint16_t>(partition.index), &fs);
    if(mountResult != 0) {
        return OperationResult::failure(mountResult, QString("Failed to mount partition %1 (error %2)")
                                                         .arg(partition.index)
                                                         .arg(mountResult));
    }

    QByteArray buffer;
    buffer.resize(static_cast<int>(maxBytes));
    const QByteArray pathBytes = path.toUtf8();
    const ssize_t readBytes = mlfs_pread_file(&fs, pathBytes.constData(), buffer.data(), maxBytes, 0);
    if(readBytes < 0) {
        return OperationResult::failure(static_cast<int>(readBytes), QString("Failed to read file '%1' (error %2)")
                                                                  .arg(path)
                                                                  .arg(readBytes));
    }

    buffer.resize(static_cast<int>(readBytes));
    *data = buffer;
    *truncated = static_cast<size_t>(readBytes) == maxBytes;
    return OperationResult::success(QString("Read %1 byte(s) from %2").arg(readBytes).arg(path));
}

OperationResult MlfsImageBackend::importCurrentFile(const PartitionInfo& partition, const QString& path, const QByteArray& data)
{
    if(path.toUtf8().size() == 0) {
        return OperationResult::failure(-1, "Import target path is empty");
    }

    const QStringList components = splitPath(path);
    if(components.isEmpty()) {
        return OperationResult::failure(-1, "Import target path must name a file");
    }

    const QByteArray fileNameBytes = components.last().toUtf8();
    if(fileNameBytes.isEmpty() || fileNameBytes.size() >= MLFS_MAX_NAME) {
        return OperationResult::failure(-1, QString("File name '%1' is too long for MLFS").arg(components.last()));
    }

    mlfs_t fs = {};
    mlfs_io_t io = device_.io();
    const int mountResult = mlfs_mount(&io, static_cast<uint16_t>(partition.index), &fs);
    if(mountResult != 0) {
        return OperationResult::failure(mountResult, QString("Failed to mount partition %1 (error %2)")
                                                         .arg(partition.index)
                                                         .arg(mountResult));
    }

    const uint32_t blocksWanted = data.isEmpty()
        ? 1U
        : static_cast<uint32_t>((static_cast<uint64_t>(data.size()) + fs.bytes_per_block - 1) / fs.bytes_per_block);

    const QByteArray pathBytes = path.toUtf8();
    const int createResult = mlfs_create_empty_file(&fs, pathBytes.constData(), blocksWanted);
    if(createResult != 0) {
        return OperationResult::failure(createResult, QString("Failed to create '%1' (error %2)")
                                                          .arg(path)
                                                          .arg(createResult));
    }

    if(!data.isEmpty()) {
        const ssize_t written = mlfs_pwrite_file(&fs, pathBytes.constData(), data.constData(), static_cast<size_t>(data.size()), 0);
        if(written < 0 || written != data.size()) {
            return OperationResult::failure(static_cast<int>(written), QString("Failed to write '%1' (wrote %2 of %3 bytes)")
                                                                      .arg(path)
                                                                      .arg(written)
                                                                      .arg(data.size()));
        }
    }

    return OperationResult::success(QString("Imported %1 byte(s) to %2").arg(data.size()).arg(path));
}

OperationResult MlfsImageBackend::createCurrentEmptyFile(const PartitionInfo& partition, const QString& path)
{
    const QStringList components = splitPath(path);
    if(components.isEmpty()) {
        return OperationResult::failure(-1, "File path must name a file");
    }

    const QByteArray fileNameBytes = components.last().toUtf8();
    if(fileNameBytes.isEmpty() || fileNameBytes.size() >= MLFS_MAX_NAME) {
        return OperationResult::failure(-1, QString("File name '%1' is too long for MLFS").arg(components.last()));
    }

    mlfs_t fs = {};
    mlfs_io_t io = device_.io();
    const int mountResult = mlfs_mount(&io, static_cast<uint16_t>(partition.index), &fs);
    if(mountResult != 0) {
        return OperationResult::failure(mountResult, QString("Failed to mount partition %1 (error %2)")
                                                         .arg(partition.index)
                                                         .arg(mountResult));
    }

    const QByteArray pathBytes = path.toUtf8();
    const int createResult = mlfs_create_empty_file(&fs, pathBytes.constData(), 1);
    if(createResult != 0) {
        return OperationResult::failure(createResult, QString("Failed to create file '%1' (error %2)")
                                                          .arg(path)
                                                          .arg(createResult));
    }

    return OperationResult::success(QString("Created file %1").arg(path));
}

OperationResult MlfsImageBackend::createCurrentDirectory(const PartitionInfo& partition, const QString& path)
{
    const QStringList components = splitPath(path);
    if(components.isEmpty()) {
        return OperationResult::failure(-1, "Directory path must name a directory");
    }

    const QByteArray dirNameBytes = components.last().toUtf8();
    if(dirNameBytes.isEmpty() || dirNameBytes.size() >= MLFS_MAX_NAME) {
        return OperationResult::failure(-1, QString("Directory name '%1' is too long for MLFS").arg(components.last()));
    }

    mlfs_t fs = {};
    mlfs_io_t io = device_.io();
    const int mountResult = mlfs_mount(&io, static_cast<uint16_t>(partition.index), &fs);
    if(mountResult != 0) {
        return OperationResult::failure(mountResult, QString("Failed to mount partition %1 (error %2)")
                                                         .arg(partition.index)
                                                         .arg(mountResult));
    }

    const QByteArray pathBytes = path.toUtf8();
    const int createResult = mlfs_create_directory(&fs, pathBytes.constData(), 1);
    if(createResult != 0) {
        return OperationResult::failure(createResult, QString("Failed to create directory '%1' (error %2)")
                                                          .arg(path)
                                                          .arg(createResult));
    }

    return OperationResult::success(QString("Created directory %1").arg(path));
}

OperationResult MlfsImageBackend::deleteCurrentEntry(const PartitionInfo& partition, const QString& path, const DirectoryEntry& entry)
{
    mlfs_t fs = {};
    mlfs_io_t io = device_.io();
    const int mountResult = mlfs_mount(&io, static_cast<uint16_t>(partition.index), &fs);
    if(mountResult != 0) {
        return OperationResult::failure(mountResult, QString("Failed to mount partition %1 (error %2)")
                                                         .arg(partition.index)
                                                         .arg(mountResult));
    }

    const QByteArray pathBytes = path.toUtf8();
    int deleteResult = 0;
    if(entry.isDirectory()) {
        deleteResult = mlfs_delete_directory(&fs, pathBytes.constData());
    } else if(entry.isFile()) {
        deleteResult = mlfs_delete_file(&fs, pathBytes.constData());
    } else {
        return OperationResult::failure(-1, QString("Unsupported entry type for '%1'").arg(path));
    }

    if(deleteResult != 0) {
        return OperationResult::failure(deleteResult, QString("Failed to delete '%1' (error %2)")
                                                          .arg(path)
                                                          .arg(deleteResult));
    }

    return OperationResult::success(QString("Deleted %1").arg(path));
}

OperationResult MlfsImageBackend::renameCurrentEntry(const PartitionInfo& partition, const QString& oldPath, const QString& newPath)
{
    const QStringList newComponents = splitPath(newPath);
    if(newComponents.isEmpty()) {
        return OperationResult::failure(-1, "Rename target path must name a file or directory");
    }

    const QByteArray newNameBytes = newComponents.last().toUtf8();
    if(newNameBytes.isEmpty() || newNameBytes.size() >= MLFS_MAX_NAME) {
        return OperationResult::failure(-1, QString("Name '%1' is too long for MLFS").arg(newComponents.last()));
    }

    mlfs_t fs = {};
    mlfs_io_t io = device_.io();
    const int mountResult = mlfs_mount(&io, static_cast<uint16_t>(partition.index), &fs);
    if(mountResult != 0) {
        return OperationResult::failure(mountResult, QString("Failed to mount partition %1 (error %2)")
                                                         .arg(partition.index)
                                                         .arg(mountResult));
    }

    const QByteArray oldPathBytes = oldPath.toUtf8();
    const QByteArray newPathBytes = newPath.toUtf8();
    const int renameResult = mlfs_rename(&fs, oldPathBytes.constData(), newPathBytes.constData());
    if(renameResult != 0) {
        return OperationResult::failure(renameResult, QString("Failed to rename '%1' to '%2' (error %3)")
                                                          .arg(oldPath)
                                                          .arg(newPath)
                                                          .arg(renameResult));
    }

    return OperationResult::success(QString("Renamed %1 to %2").arg(oldPath, newPath));
}
