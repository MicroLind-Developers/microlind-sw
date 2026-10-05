#ifndef MICROLIND_FILESYSTEM_H
#define MICROLIND_FILESYSTEM_H

/* CMOC/6809 target header. Link modules/filesystem/filesystem_c_shim.asm
 * into the application; calls require an initialized, mounted biosfs module. */
#include "integer.h"

typedef struct {
    const char *path;
    void *buffer;
    uint16_t count;
    uint32_t offset;
    uint16_t transferred;
} FsRequest;

typedef struct {
    uint32_t used_blocks;
    uint32_t free_blocks;
} FsStats;

int16_t fs_mount(uint16_t partition);
int16_t fs_stat(FsRequest *request);
int16_t fs_list(FsRequest *request);
int16_t fs_read(FsRequest *request);
int16_t fs_stats(FsStats *stats);
int16_t fs_write(FsRequest *request);
int16_t fs_create(FsRequest *request);
int16_t fs_unlink(FsRequest *request);
int16_t fs_mkdir(FsRequest *request);
int16_t fs_rmdir(FsRequest *request);
int16_t fs_rename(FsRequest *request);

/* Services return 0 or these negative errors. Read/write offsets are unchanged.
 * Writes report chunks confirmed on media and, when growing size, in metadata.
 * List advances its slot cursor. Create/mkdir use offset as initial blocks
 * (zero means one), ignoring buffer/count. Unlink/rmdir use only path.
 * Rename uses path as source and buffer as a NUL-terminated destination path. */
#define FS_EIO           (-1)
#define FS_EINVAL        (-2)
#define FS_ENOMOUNT      (-3)
#define FS_ECORRUPT      (-4)
#define FS_ENOENT        (-5)
#define FS_ENOTDIR       (-6)
#define FS_EISDIR        (-7)
#define FS_EUNSUPPORTED  (-8)
#define FS_EABI          (-9)
#define FS_ENAMETOOLONG  (-10)
#define FS_ERANGE        (-11)
#define FS_EEXIST        (-12)
#define FS_ENOSPC        (-13)
#define FS_ENOTEMPTY     (-14)

#endif
