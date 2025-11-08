/*
 * MLFS Kernel Module Header
 * Data structures and definitions for the MLFS kernel driver
 */

#ifndef _MLFS_MODULE_H
#define _MLFS_MODULE_H

#include <linux/types.h>
#include <linux/fs.h>

/* Include proc filesystem support */
#include "mlfs_proc.h"

/* MLFS constants */
#define MLFS_MAX_NAME 48
#define MLPT_MAX_PARTS 16

/* MLFS flags */
#define MLFS_FLAG_DIR  (1 << 0)
#define MLFS_FLAG_FILE (1 << 1)

/*
 * On-disk structures
 * These match the userspace MLFS format
 */

/* Extent: contiguous run of blocks */
struct mlfs_extent {
    __le32 start;
    __le32 length;
} __packed;

/* Directory entry (128 bytes) */
struct mlfs_dentry {
    __u8  in_use;
    __u8  flags;
    __le32 size_bytes;
    __le32 mtime;
    __le32 ctime;
    __u8  extents_used;
    __u8  extents_total;
    char  name[MLFS_MAX_NAME];
    struct mlfs_extent extents[4];
    __le32 first_indirect;
    __u8  reserved[4];
} __packed;

/* Superblock structure (512 bytes) */
struct mlfs_superblock {
    __le32 magic;
    __u8   major;
    __u8   minor;
    __u8   patch;
    __u8   log2_block_size;
    __u8   reserved0;
    __le32 total_blocks;
    __le32 bitmap_start;
    __le32 bitmap_blocks;
    __le32 root_dir_block;
    __le32 root_dir_blocks;
    __le32 uuid[4];
    __le32 checksum;
    __u8   reserved[512 - 4 - 3 - 1 - 1 - 4 - 4 - 4 - 4 - 4 - 16 - 4];
} __packed;

/* Partition table entry */
struct mlpt_entry {
    __le32 start_lba;
    __le32 block_count;
    __u8   type;
    __u8   log2_block_size;
    char   name[14];
} __packed;

/* Partition table (512 bytes) */
struct mlpt {
    __le32 magic;
    __u8   major;
    __u8   minor;
    __u8   patch;
    __le16 count;
    struct mlpt_entry entries[MLPT_MAX_PARTS];
    __u8   reserved[512 - 4 - 1 - 1 - 1 - 2 - (sizeof(struct mlpt_entry) * MLPT_MAX_PARTS)];
} __packed;

/*
 * In-memory structures
 */

/* Per-superblock information */
struct mlfs_sb_info {
    unsigned long block_size;
    __u32 total_blocks;
    __u32 free_blocks;
    __u32 bitmap_start;
    __u32 bitmap_blocks;
    __u32 root_dir_block;
    __u32 root_dir_blocks;
    unsigned long partition_lba;
    unsigned int partition_num;
    unsigned int dentries_per_block;
    unsigned int sectors_per_block;  /* 512-byte sectors per filesystem block */
    struct buffer_head *bitmap_bh;  /* Cached bitmap */
    struct proc_dir_entry *proc_dir; /* Proc filesystem directory */
    char device_name[64];             /* Device name for proc */
    struct mlfs_stats stats;          /* Operation statistics */
};

/* Per-inode information */
struct mlfs_inode_info {
    unsigned long first_block;
    __u32 block_count;
    __u32 parent_dir_block;     /* Parent directory's first block */
    __u32 parent_dir_blocks;    /* Parent directory's block count */
    char filename[MLFS_MAX_NAME]; /* Filename in parent directory */
    struct inode vfs_inode;
};

/* Inode cache */
extern struct kmem_cache *mlfs_inode_cachep;

/* Helper macros */
#define MLFS_SB(sb) ((struct mlfs_sb_info *)(sb)->s_fs_info)
#define MLFS_I(inode) container_of(inode, struct mlfs_inode_info, vfs_inode)

/* Function declarations */
struct inode *mlfs_iget(struct super_block *sb, struct mlfs_dentry *de,
                         unsigned long dir_block, int dentry_idx,
                         __u32 parent_dir_block, __u32 parent_dir_blocks);

#endif /* _MLFS_MODULE_H */

