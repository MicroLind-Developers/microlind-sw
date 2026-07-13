#ifndef MLFS_COMMANDER_DIRECTORY_ENTRY_H
#define MLFS_COMMANDER_DIRECTORY_ENTRY_H

#include <QString>
#include <cstdint>

struct DirectoryEntry {
    QString name;
    uint8_t flags = 0;
    uint32_t sizeBytes = 0;
    uint32_t modifiedTime = 0;
    uint32_t createdTime = 0;
    uint32_t firstBlock = 0;
    uint32_t blockCount = 0;

    bool isDirectory() const
    {
        return (flags & 1U) != 0;
    }

    bool isFile() const
    {
        return (flags & 2U) != 0;
    }
};

#endif
