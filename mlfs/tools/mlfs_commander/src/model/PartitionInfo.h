#ifndef MLFS_COMMANDER_PARTITION_INFO_H
#define MLFS_COMMANDER_PARTITION_INFO_H

#include <QString>
#include <cstdint>

struct PartitionInfo {
    int index = -1;
    QString name;
    uint32_t startLba = 0;
    uint32_t blockCount = 0;
    uint8_t type = 0;
    uint8_t log2BlockSize = 0;

    uint32_t blockSizeBytes() const
    {
        if(log2BlockSize >= 32) {
            return 0;
        }
        return 1U << log2BlockSize;
    }

    uint64_t sizeBytes() const
    {
        return static_cast<uint64_t>(blockCount) * blockSizeBytes();
    }

    uint64_t sectorsPerBlock() const
    {
        const uint32_t bytes = blockSizeBytes();
        return bytes == 0 ? 0 : bytes / 512;
    }

    uint64_t endLbaExclusive() const
    {
        return static_cast<uint64_t>(startLba) + static_cast<uint64_t>(blockCount) * sectorsPerBlock();
    }

    uint64_t endLba() const
    {
        const uint64_t exclusive = endLbaExclusive();
        return exclusive == 0 ? 0 : exclusive - 1;
    }

    bool isMlfs() const
    {
        return type == 1;
    }
};

#endif
