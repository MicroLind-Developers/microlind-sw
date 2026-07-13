#ifndef MLFS_COMMANDER_FILE_BLOCK_DEVICE_H
#define MLFS_COMMANDER_FILE_BLOCK_DEVICE_H

#include "support/OperationResult.h"

#include <QString>
#include <cstdio>
#include <cstdint>

extern "C" {
#include "mlfs.h"
}

class FileBlockDevice {
public:
    FileBlockDevice() = default;
    ~FileBlockDevice();

    FileBlockDevice(const FileBlockDevice&) = delete;
    FileBlockDevice& operator=(const FileBlockDevice&) = delete;

    OperationResult open(const QString& path, bool readOnly);
    void close();

    bool isOpen() const;
    QString path() const;
    mlfs_io_t io();

private:
    static constexpr uint32_t SectorSize = 512;

    static int readSectors(void* ctx, uint64_t lba, uint32_t count, void* buf);
    static int writeSectors(void* ctx, uint64_t lba, uint32_t count, const void* buf);

    int read(uint64_t lba, uint32_t count, void* buf);
    int write(uint64_t lba, uint32_t count, const void* buf);

    FILE* file_ = nullptr;
    QString path_;
    bool readOnly_ = false;
};

#endif
