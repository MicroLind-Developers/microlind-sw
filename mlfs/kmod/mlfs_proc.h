/*
 * MLFS Kernel Module - Proc Filesystem Interface
 * Provides filesystem statistics through /proc/fs/mlfs/
 */

#ifndef _MLFS_PROC_H
#define _MLFS_PROC_H

#include <linux/types.h>
#include <linux/proc_fs.h>

struct super_block;

/* Proc filesystem root directory */
extern struct proc_dir_entry *mlfs_proc_root;

/*
 * Statistics counters for monitoring filesystem operations
 */
struct mlfs_stats {
    atomic64_t read_ops;       /* Number of read operations */
    atomic64_t write_ops;      /* Number of write operations */
    atomic64_t read_bytes;     /* Total bytes read */
    atomic64_t write_bytes;    /* Total bytes written */
    atomic64_t errors;         /* Number of errors encountered */
    atomic64_t dir_lookups;    /* Number of directory lookups */
    atomic64_t file_creates;   /* Number of files created */
    atomic64_t file_deletes;   /* Number of files deleted */
    atomic64_t dir_creates;    /* Number of directories created */
    atomic64_t dir_deletes;    /* Number of directories deleted */
};

/*
 * Initialize statistics counters
 */
static inline void mlfs_stats_init(struct mlfs_stats *stats)
{
    atomic64_set(&stats->read_ops, 0);
    atomic64_set(&stats->write_ops, 0);
    atomic64_set(&stats->read_bytes, 0);
    atomic64_set(&stats->write_bytes, 0);
    atomic64_set(&stats->errors, 0);
    atomic64_set(&stats->dir_lookups, 0);
    atomic64_set(&stats->file_creates, 0);
    atomic64_set(&stats->file_deletes, 0);
    atomic64_set(&stats->dir_creates, 0);
    atomic64_set(&stats->dir_deletes, 0);
}

/*
 * Increment statistics counters
 */
static inline void mlfs_stats_inc_read(struct mlfs_stats *stats, size_t bytes)
{
    atomic64_inc(&stats->read_ops);
    atomic64_add(bytes, &stats->read_bytes);
}

static inline void mlfs_stats_inc_write(struct mlfs_stats *stats, size_t bytes)
{
    atomic64_inc(&stats->write_ops);
    atomic64_add(bytes, &stats->write_bytes);
}

static inline void mlfs_stats_inc_error(struct mlfs_stats *stats)
{
    atomic64_inc(&stats->errors);
}

static inline void mlfs_stats_inc_lookup(struct mlfs_stats *stats)
{
    atomic64_inc(&stats->dir_lookups);
}

static inline void mlfs_stats_inc_file_create(struct mlfs_stats *stats)
{
    atomic64_inc(&stats->file_creates);
}

static inline void mlfs_stats_inc_file_delete(struct mlfs_stats *stats)
{
    atomic64_inc(&stats->file_deletes);
}

static inline void mlfs_stats_inc_dir_create(struct mlfs_stats *stats)
{
    atomic64_inc(&stats->dir_creates);
}

static inline void mlfs_stats_inc_dir_delete(struct mlfs_stats *stats)
{
    atomic64_inc(&stats->dir_deletes);
}

/*
 * Proc filesystem functions
 */

/**
 * mlfs_proc_init - Initialize proc filesystem root directory
 * 
 * Creates /proc/fs/mlfs/ directory.
 * Must be called during module initialization.
 * 
 * Returns: 0 on success, negative error code on failure
 */
int mlfs_proc_init(void);

/**
 * mlfs_proc_exit - Cleanup proc filesystem
 * 
 * Removes /proc/fs/mlfs/ directory and all subdirectories.
 * Must be called during module cleanup.
 */
void mlfs_proc_exit(void);

/**
 * mlfs_proc_create - Create proc entry for a mounted filesystem
 * @sb: Super block of the mounted filesystem
 * 
 * Creates /proc/fs/mlfs/<device>/stats for the mounted filesystem.
 * Called automatically during mount.
 * 
 * Returns: 0 on success, negative error code on failure
 */
int mlfs_proc_create(struct super_block *sb);

/**
 * mlfs_proc_destroy - Remove proc entry for a filesystem
 * @sb: Super block of the filesystem
 * 
 * Removes /proc/fs/mlfs/<device>/ and all its contents.
 * Called automatically during unmount.
 */
void mlfs_proc_destroy(struct super_block *sb);

#endif /* _MLFS_PROC_H */

