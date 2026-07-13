#include "backend/MlfsImageBackend.h"

#include <QByteArray>
#include <QString>
#include <QTemporaryDir>
#include <QVector>

#include <iostream>

namespace {

bool check(bool condition, const char* message)
{
    if(!condition) {
        std::cerr << message << '\n';
        return false;
    }
    return true;
}

bool checkResult(const OperationResult& result, const char* operation)
{
    if(!result.ok) {
        std::cerr << operation << " failed: " << result.message.toStdString() << '\n';
        return false;
    }
    return true;
}

} // namespace

int main()
{
    QTemporaryDir dir;
    if(!check(dir.isValid(), "failed to create temporary directory")) {
        return 1;
    }

    const QString imagePath = dir.filePath("commander_backend.img");

    MlfsImageBackend backend;
    if(!checkResult(backend.createImage(imagePath, 16), "createImage")) {
        return 1;
    }

    QVector<PartitionInfo> partitions;
    if(!checkResult(backend.readPartitions(&partitions), "readPartitions empty")) {
        return 1;
    }
    if(!check(partitions.isEmpty(), "new image should start with no partitions")) {
        return 1;
    }

    if(!checkResult(backend.addPartition(1, 4, 4096, "main"), "addPartition")) {
        return 1;
    }
    if(!checkResult(backend.formatPartition(0), "formatPartition")) {
        return 1;
    }
    if(!checkResult(backend.readPartitions(&partitions), "readPartitions one")) {
        return 1;
    }
    if(!check(partitions.size() == 1, "image should contain one partition")) {
        return 1;
    }
    if(!check(partitions.first().name == "main", "partition name should be main")) {
        return 1;
    }

    const PartitionInfo partition = partitions.first();
    if(!checkResult(backend.createEmptyFile(partition, "/empty.bin"), "createEmptyFile")) {
        return 1;
    }
    if(!checkResult(backend.importFile(partition, "/hello.txt", QByteArray("hello\n")), "importFile")) {
        return 1;
    }
    if(!checkResult(backend.createDirectory(partition, "/docs"), "createDirectory")) {
        return 1;
    }

    QVector<DirectoryEntry> entries;
    if(!checkResult(backend.readDirectory(partition, "/", &entries), "readDirectory")) {
        return 1;
    }
    if(!check(entries.size() == 3, "root directory should contain three entries")) {
        return 1;
    }

    if(!checkResult(backend.renameEntry(partition, "/hello.txt", "/greeting.txt"), "renameEntry file")) {
        return 1;
    }

    QByteArray data;
    bool truncated = true;
    if(!checkResult(backend.readFile(partition, "/greeting.txt", 64, &data, &truncated), "readFile renamed")) {
        return 1;
    }
    if(!check(!truncated, "readFile should not truncate small files")) {
        return 1;
    }
    if(!check(data == QByteArray("hello\n"), "readFile returned unexpected contents")) {
        return 1;
    }

    if(!checkResult(backend.renameEntry(partition, "/docs", "/manuals"), "renameEntry directory")) {
        return 1;
    }
    if(!checkResult(backend.readDirectory(partition, "/", &entries), "readDirectory renamed entries")) {
        return 1;
    }
    bool foundGreeting = false;
    bool foundManuals = false;
    for(const DirectoryEntry& entry : entries) {
        foundGreeting = foundGreeting || (entry.name == "greeting.txt" && entry.isFile());
        foundManuals = foundManuals || (entry.name == "manuals" && entry.isDirectory());
    }
    if(!check(foundGreeting, "renamed file should be listed")) {
        return 1;
    }
    if(!check(foundManuals, "renamed directory should be listed")) {
        return 1;
    }

    if(!checkResult(backend.renameEntry(partition, "/greeting.txt", "/manuals/greeting.txt"), "renameEntry move file")) {
        return 1;
    }
    data.clear();
    truncated = true;
    if(!checkResult(backend.readFile(partition, "/manuals/greeting.txt", 64, &data, &truncated), "readFile moved")) {
        return 1;
    }
    if(!check(!truncated, "readFile should not truncate moved small files")) {
        return 1;
    }
    if(!check(data == QByteArray("hello\n"), "moved file returned unexpected contents")) {
        return 1;
    }

    if(!checkResult(backend.renamePartition(0, "boot"), "renamePartition")) {
        return 1;
    }
    if(!checkResult(backend.readPartitions(&partitions), "readPartitions renamed")) {
        return 1;
    }
    if(!check(partitions.size() == 1 && partitions.first().name == "boot", "partition should be renamed to boot")) {
        return 1;
    }

    if(!checkResult(backend.deletePartition(0), "deletePartition")) {
        return 1;
    }
    if(!checkResult(backend.readPartitions(&partitions), "readPartitions deleted")) {
        return 1;
    }
    if(!check(partitions.isEmpty(), "partition table should be empty after deletion")) {
        return 1;
    }

    if(!checkResult(backend.addPartitionBlocks(1, 128, 4096, "blocks"), "addPartitionBlocks")) {
        return 1;
    }
    if(!checkResult(backend.readPartitions(&partitions), "readPartitions block partition")) {
        return 1;
    }
    if(!check(partitions.size() == 1, "image should contain one block-count partition")) {
        return 1;
    }
    if(!check(partitions.first().blockCount == 128, "block-count partition should have 128 blocks")) {
        return 1;
    }

    return 0;
}
