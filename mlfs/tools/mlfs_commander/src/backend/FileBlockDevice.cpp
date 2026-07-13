#include "backend/FileBlockDevice.h"

#include <QFileInfo>
#include <cerrno>
#include <cstring>

FileBlockDevice::~FileBlockDevice()
{
    close();
}

OperationResult FileBlockDevice::open(const QString& path, bool readOnly)
{
    close();

    const QByteArray localPath = QFileInfo(path).absoluteFilePath().toLocal8Bit();
    file_ = std::fopen(localPath.constData(), readOnly ? "rb" : "r+b");
    if(file_ == nullptr) {
        return OperationResult::failure(errno, QString("Failed to open '%1': %2")
                                                   .arg(path, QString::fromLocal8Bit(std::strerror(errno))));
    }

    path_ = QFileInfo(path).absoluteFilePath();
    readOnly_ = readOnly;
    return OperationResult::success(QString("Opened '%1'").arg(path_));
}

void FileBlockDevice::close()
{
    if(file_ != nullptr) {
        std::fclose(file_);
        file_ = nullptr;
    }

    path_.clear();
    readOnly_ = false;
}

bool FileBlockDevice::isOpen() const
{
    return file_ != nullptr;
}

QString FileBlockDevice::path() const
{
    return path_;
}

mlfs_io_t FileBlockDevice::io()
{
    mlfs_io_t io = {};
    io.ctx = this;
    io.read = &FileBlockDevice::readSectors;
    io.write = &FileBlockDevice::writeSectors;
    io.sector_size = SectorSize;
    return io;
}

int FileBlockDevice::readSectors(void* ctx, uint64_t lba, uint32_t count, void* buf)
{
    auto* device = static_cast<FileBlockDevice*>(ctx);
    return device != nullptr ? device->read(lba, count, buf) : -1;
}

int FileBlockDevice::writeSectors(void* ctx, uint64_t lba, uint32_t count, const void* buf)
{
    auto* device = static_cast<FileBlockDevice*>(ctx);
    return device != nullptr ? device->write(lba, count, buf) : -1;
}

int FileBlockDevice::read(uint64_t lba, uint32_t count, void* buf)
{
    if(file_ == nullptr || buf == nullptr) {
        return -1;
    }

    const uint64_t offset = lba * SectorSize;
    const size_t bytesToRead = static_cast<size_t>(count) * SectorSize;

    if(std::fseek(file_, static_cast<long>(offset), SEEK_SET) != 0) {
        return -1;
    }

    const size_t bytesRead = std::fread(buf, 1, bytesToRead, file_);
    if(bytesRead != bytesToRead) {
        if(std::feof(file_)) {
            std::memset(static_cast<unsigned char*>(buf) + bytesRead, 0, bytesToRead - bytesRead);
            std::clearerr(file_);
            return 0;
        }
        return -1;
    }

    return 0;
}

int FileBlockDevice::write(uint64_t lba, uint32_t count, const void* buf)
{
    if(file_ == nullptr || buf == nullptr || readOnly_) {
        return -1;
    }

    const uint64_t offset = lba * SectorSize;
    const size_t bytesToWrite = static_cast<size_t>(count) * SectorSize;

    if(std::fseek(file_, static_cast<long>(offset), SEEK_SET) != 0) {
        return -1;
    }

    const size_t bytesWritten = std::fwrite(buf, 1, bytesToWrite, file_);
    if(bytesWritten != bytesToWrite) {
        return -1;
    }

    return std::fflush(file_) == 0 ? 0 : -1;
}
