/****************************** mlfs.h **************************************/
#ifndef MLFS_H
#define MLFS_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

// -----------------------------
// Forward declarations and constants (must be before mlfs_types.h)
// -----------------------------

#define MLPT_MAGIC 0x4D4C5054u /* 'MLPT' */
#define MLPT_VERSION_MAJOR 0
#define MLPT_VERSION_MINOR 1
#define MLPT_VERSION_PATCH 0
#define MLPT_VERSION ((MLPT_VERSION_MAJOR << 16) | (MLPT_VERSION_MINOR << 8) | MLPT_VERSION_PATCH)
#define MLPT_MAX_PARTS 16

#define MLFS_MAGIC 0x4D4C4653u /* 'MLFS' */
#define MLFS_VERSION_MAJOR 0
#define MLFS_VERSION_MINOR 1
#define MLFS_VERSION_PATCH 0
#define MLFS_VERSION ((MLFS_VERSION_MAJOR << 16) | (MLFS_VERSION_MINOR << 8) | MLFS_VERSION_PATCH)

// Directory entry sizes/limits
#define MLFS_MAX_NAME 48

// I/O abstraction (host driver provides these)
typedef int (*mlfs_read_fn)(void* ctx, uint64_t lba, uint32_t count, void* buf);
typedef int (*mlfs_write_fn)(void* ctx, uint64_t lba, uint32_t count, const void* buf);

// Now we can include the types that depend on the above definitions
#include "mlfs_types.h"

// -----------------------------
// Disk/Partition format (public)
// -----------------------------

// -----------------------------
// Public API
// -----------------------------

// Partition-table helpers
int mlfs_read_mlpt(const mlfs_io_t* io, mlpt_t* out);
int mlfs_write_mlpt(const mlfs_io_t* io, const mlpt_t* pt);
int mlfs_make_single_partition(const mlfs_io_t* io, uint32_t start_lba, uint32_t sectors_total, uint8_t log2_block_bytes);
int mlfs_make_empty_partition_table(const mlfs_io_t* io);
int mlfs_add_partition(const mlfs_io_t* io, uint32_t start_lba, uint32_t block_count, uint8_t log2_block_size, const char* name);

// Format & mount
int mlfs_mkfs(const mlfs_io_t* io, uint16_t part_index, mlfs_t* out_fs);
int mlfs_mount(const mlfs_io_t* io, uint16_t part_index, mlfs_t* out_fs);

// Simple allocator & file ops (root only; single-extent files)
int     mlfs_alloc_run(mlfs_t* fs, uint32_t blocks_wanted, mlfs_extent_t* out_ext);
int     mlfs_create_empty_file(mlfs_t* fs, const char* name, uint32_t initial_blocks);
ssize_t mlfs_pwrite_file(mlfs_t* fs, const char* name, const void* src, size_t count, size_t offset);
ssize_t mlfs_pread_file(mlfs_t* fs, const char* name, void* dst, size_t count, size_t offset);

// Directory operations
int mlfs_create_directory(mlfs_t* fs, const char* path, uint32_t initial_blocks);
int mlfs_delete_directory(mlfs_t* fs, const char* path);
int mlfs_delete_file(mlfs_t* fs, const char* path);
int mlfs_read_directory(mlfs_t* fs, const char* path, mlfs_dentry_t* entries, uint32_t max_entries, uint32_t* count_out);

#endif  // MLFS_H
