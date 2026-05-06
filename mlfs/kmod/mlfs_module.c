/*
 * MLFS Linux Kernel Module
 * MicroLind File System - Kernel VFS Integration
 * 
 * This module allows mounting MLFS filesystems directly in Linux.
 * 
 * Current status: Read-only implementation
 * TODO: Add write support, caching, and performance optimizations
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/buffer_head.h>
#include <linux/slab.h>
#include <linux/blkdev.h>
#include <linux/parser.h>
#include <linux/statfs.h>
#include <linux/seq_file.h>

#include "mlfs_module.h"
#include "mlfs_proc.h"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("MicroLind Project");
MODULE_DESCRIPTION("MLFS - MicroLind File System");
MODULE_VERSION("0.4.0");

/* Inode cache */
struct kmem_cache *mlfs_inode_cachep;

/* Module parameter for debug messages */
static int debug = 0;
module_param(debug, int, 0644);
MODULE_PARM_DESC(debug, "Enable debug messages (0=off, 1=on)");

#define MLFS_DEBUG(fmt, ...) \
    do { if (debug) pr_info("mlfs: " fmt, ##__VA_ARGS__); } while (0)

/* MLFS magic numbers and constants */
#define MLFS_MAGIC      0x4D4C4653u  /* 'MLFS' */
#define MLPT_MAGIC      0x4D4C5054u  /* 'MLPT' */
#define MLFS_ROOT_INO   1

/* Forward declarations */
static struct dentry *mlfs_mount(struct file_system_type *fs_type,
                                  int flags, const char *dev_name,
                                  void *data);
static void mlfs_kill_sb(struct super_block *sb);

/* File system type structure */
static struct file_system_type mlfs_fs_type = {
    .owner      = THIS_MODULE,
    .name       = "mlfs",
    .mount      = mlfs_mount,
    .kill_sb    = mlfs_kill_sb,
    .fs_flags   = FS_REQUIRES_DEV,
};

/*
 * Super block operations
 */
static struct inode *mlfs_alloc_inode(struct super_block *sb)
{
    struct mlfs_inode_info *mi;
    
    mi = kmem_cache_alloc(mlfs_inode_cachep, GFP_KERNEL);
    if (!mi)
        return NULL;
    
    return &mi->vfs_inode;
}

static void mlfs_destroy_inode(struct inode *inode)
{
    struct mlfs_inode_info *mi = MLFS_I(inode);
    
    kmem_cache_free(mlfs_inode_cachep, mi);
}

static void mlfs_put_super(struct super_block *sb)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    
    MLFS_DEBUG("Unmounting filesystem\n");
    
    if (sbi) {
        /* Remove proc filesystem entry */
        mlfs_proc_destroy(sb);
        
        if (sbi->bitmap_bh)
            brelse(sbi->bitmap_bh);
        kfree(sbi);
        sb->s_fs_info = NULL;
    }
}

static int mlfs_statfs(struct dentry *dentry, struct kstatfs *buf)
{
    struct super_block *sb = dentry->d_sb;
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    
    buf->f_type = MLFS_MAGIC;
    buf->f_bsize = sbi->block_size;
    buf->f_blocks = sbi->total_blocks;
    buf->f_bfree = sbi->free_blocks;  /* TODO: Calculate from bitmap */
    buf->f_bavail = buf->f_bfree;
    buf->f_files = 0;  /* TODO: Count inodes */
    buf->f_ffree = 0;
    buf->f_namelen = MLFS_MAX_NAME;
    
    return 0;
}

static int mlfs_show_options(struct seq_file *seq, struct dentry *root)
{
    struct mlfs_sb_info *sbi = MLFS_SB(root->d_sb);
    
    seq_printf(seq, ",partition=%u", sbi->partition_num);
    seq_printf(seq, ",blocksize=%lu", sbi->block_size);
    
    return 0;
}

static int mlfs_sync_fs(struct super_block *sb, int wait)
{
    MLFS_DEBUG("Syncing filesystem\n");
    
    /* Sync all dirty buffers */
    if (wait)
        return sync_blockdev(sb->s_bdev);
    
    return 0;
}

static const struct super_operations mlfs_super_ops = {
    .alloc_inode    = mlfs_alloc_inode,
    .destroy_inode  = mlfs_destroy_inode,
    .put_super      = mlfs_put_super,
    .statfs         = mlfs_statfs,
    .sync_fs        = mlfs_sync_fs,
    .show_options   = mlfs_show_options,
};

/*
 * Forward declarations
 */
static void *mlfs_read_fs_block_data(struct super_block *sb, __u32 rel_block);
static int mlfs_write_fs_block_data(struct super_block *sb, __u32 rel_block, const void *data);
static int mlfs_alloc_blocks(struct super_block *sb, __u32 blocks_wanted, struct mlfs_extent *out_ext);
static int mlfs_free_blocks(struct super_block *sb, __u32 start, __u32 length);
static int mlfs_dir_add_entry(struct super_block *sb, __u32 dir_block, __u32 dir_blocks, 
                                const char *name, int is_dir, struct mlfs_extent *extent, __u32 size_bytes);
static int mlfs_dir_remove_entry(struct super_block *sb, __u32 dir_block, __u32 dir_blocks, const char *name);

/* Forward declarations for operations structures */
static const struct file_operations mlfs_file_operations;
static const struct file_operations mlfs_dir_operations;
static const struct inode_operations mlfs_file_inode_operations;
static const struct inode_operations mlfs_dir_inode_operations;

/*
 * Inode operations
 */
static struct dentry *mlfs_lookup(struct inode *dir, struct dentry *dentry,
                                   unsigned int flags)
{
    struct super_block *sb = dir->i_sb;
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    struct mlfs_dentry *de;
    struct inode *inode = NULL;
    const char *name = dentry->d_name.name;
    int name_len = dentry->d_name.len;
    unsigned long dir_block;
    int i;
    
    MLFS_DEBUG("Looking up '%s' in directory inode %lu\n", name, dir->i_ino);
    
    /* Track directory lookup */
    mlfs_stats_inc_lookup(&MLFS_SB(sb)->stats);
    
    if (name_len > MLFS_MAX_NAME)
        return ERR_PTR(-ENAMETOOLONG);
    
    /* Get directory block from inode (partition-relative) */
    dir_block = MLFS_I(dir)->first_block;
    
    /* Read directory block using our helper */
    de = (struct mlfs_dentry *)mlfs_read_fs_block_data(sb, dir_block);
    if (!de)
        return ERR_PTR(-EIO);
    
    /* Search for entry */
    for (i = 0; i < sbi->dentries_per_block; i++) {
        if (de[i].in_use && strcmp(de[i].name, name) == 0) {
            /* Found it - create inode */
            struct mlfs_inode_info *dir_mi = MLFS_I(dir);
            inode = mlfs_iget(sb, &de[i], dir_block, i, dir_mi->first_block, dir_mi->block_count);
            if (IS_ERR(inode)) {
                kfree(de);
                return ERR_CAST(inode);
            }
            break;
        }
    }
    
    kfree(de);
    
    /* Return dentry (inode can be NULL for negative dentry) */
    return d_splice_alias(inode, dentry);
}

/*
 * Create a new file
 */
static int mlfs_create(struct mnt_idmap *idmap, struct inode *dir, struct dentry *dentry, umode_t mode, bool excl)
{
    struct super_block *sb = dir->i_sb;
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    struct mlfs_inode_info *dir_mi = MLFS_I(dir);
    struct mlfs_extent extent;
    struct inode *inode;
    char *zero_block;
    const char *name = dentry->d_name.name;
    int ret, i;
    
    MLFS_DEBUG("create: %s in dir inode %lu\n", name, dir->i_ino);
    
    if (dentry->d_name.len >= MLFS_MAX_NAME)
        return -ENAMETOOLONG;
    
    /* Allocate 1 block for the file */
    ret = mlfs_alloc_blocks(sb, 1, &extent);
    if (ret)
        return ret;
    
    /* Zero the allocated block */
    zero_block = kzalloc(MLFS_SB(sb)->block_size, GFP_KERNEL);
    if (!zero_block) {
        mlfs_free_blocks(sb, be32_to_cpu(extent.start), be32_to_cpu(extent.length));
        return -ENOMEM;
    }
    
    for (i = 0; i < be32_to_cpu(extent.length); i++) {
        ret = mlfs_write_fs_block_data(sb, be32_to_cpu(extent.start) + i, zero_block);
        if (ret) {
            kfree(zero_block);
            mlfs_free_blocks(sb, be32_to_cpu(extent.start), be32_to_cpu(extent.length));
            return ret;
        }
    }
    kfree(zero_block);
    
    /* Add directory entry */
    ret = mlfs_dir_add_entry(sb, dir_mi->first_block, dir_mi->block_count, 
                              name, 0, &extent, 0);
    if (ret) {
        mlfs_free_blocks(sb, be32_to_cpu(extent.start), be32_to_cpu(extent.length));
        return ret;
    }
    
    /* Create inode */
    inode = new_inode(sb);
    if (!inode) {
        mlfs_dir_remove_entry(sb, dir_mi->first_block, dir_mi->block_count, name);
        mlfs_free_blocks(sb, be32_to_cpu(extent.start), be32_to_cpu(extent.length));
        return -ENOMEM;
    }
    
    inode->i_ino = (dir_mi->first_block << 16) | 0;  /* Generate unique inode number */
    inode->i_mode = S_IFREG | mode;
    inode->i_op = &mlfs_file_inode_operations;
    inode->i_fop = &mlfs_file_operations;
    inode->i_size = 0;
    set_nlink(inode, 1);
    
    MLFS_I(inode)->first_block = be32_to_cpu(extent.start);
    MLFS_I(inode)->block_count = be32_to_cpu(extent.length);
    MLFS_I(inode)->parent_dir_block = dir_mi->first_block;
    MLFS_I(inode)->parent_dir_blocks = dir_mi->block_count;
    strncpy(MLFS_I(inode)->filename, name, MLFS_MAX_NAME - 1);
    MLFS_I(inode)->filename[MLFS_MAX_NAME - 1] = '\0';
    
    inode_set_mtime_to_ts(inode, inode_set_ctime_current(inode));
    inode_set_atime_to_ts(inode, inode_get_mtime(inode));
    
    mark_inode_dirty(inode);
    d_instantiate(dentry, inode);
    
    /* Track file creation */
    mlfs_stats_inc_file_create(&sbi->stats);
    
    return 0;
}

/*
 * Create a new directory
 */
static int mlfs_mkdir(struct mnt_idmap *idmap, struct inode *dir, struct dentry *dentry, umode_t mode)
{
    struct super_block *sb = dir->i_sb;
    struct mlfs_inode_info *dir_mi = MLFS_I(dir);
    struct mlfs_extent extent;
    struct inode *inode;
    char *zero_block;
    const char *name = dentry->d_name.name;
    int ret, i;
    
    MLFS_DEBUG("mkdir: %s in dir inode %lu\n", name, dir->i_ino);
    
    if (dentry->d_name.len >= MLFS_MAX_NAME)
        return -ENAMETOOLONG;
    
    /* Allocate 1 block for the directory */
    ret = mlfs_alloc_blocks(sb, 1, &extent);
    if (ret)
        return ret;
    
    /* Zero the allocated block */
    zero_block = kzalloc(MLFS_SB(sb)->block_size, GFP_KERNEL);
    if (!zero_block) {
        mlfs_free_blocks(sb, be32_to_cpu(extent.start), be32_to_cpu(extent.length));
        return -ENOMEM;
    }
    
    for (i = 0; i < be32_to_cpu(extent.length); i++) {
        ret = mlfs_write_fs_block_data(sb, be32_to_cpu(extent.start) + i, zero_block);
        if (ret) {
            kfree(zero_block);
            mlfs_free_blocks(sb, be32_to_cpu(extent.start), be32_to_cpu(extent.length));
            return ret;
        }
    }
    kfree(zero_block);
    
    /* Add directory entry */
    ret = mlfs_dir_add_entry(sb, dir_mi->first_block, dir_mi->block_count, 
                              name, 1, &extent, 0);
    if (ret) {
        mlfs_free_blocks(sb, be32_to_cpu(extent.start), be32_to_cpu(extent.length));
        return ret;
    }
    
    /* Create inode */
    inode = new_inode(sb);
    if (!inode) {
        mlfs_dir_remove_entry(sb, dir_mi->first_block, dir_mi->block_count, name);
        mlfs_free_blocks(sb, be32_to_cpu(extent.start), be32_to_cpu(extent.length));
        return -ENOMEM;
    }
    
    inode->i_ino = (dir_mi->first_block << 16) | 0;  /* Generate unique inode number */
    inode->i_mode = S_IFDIR | mode;
    inode->i_op = &mlfs_dir_inode_operations;
    inode->i_fop = &mlfs_dir_operations;
    inode->i_size = MLFS_SB(sb)->block_size;
    set_nlink(inode, 2);
    
    MLFS_I(inode)->first_block = be32_to_cpu(extent.start);
    MLFS_I(inode)->block_count = be32_to_cpu(extent.length);
    
    inode_set_mtime_to_ts(inode, inode_set_ctime_current(inode));
    inode_set_atime_to_ts(inode, inode_get_mtime(inode));
    
    inc_nlink(dir);  /* .. entry in new directory */
    mark_inode_dirty(dir);
    mark_inode_dirty(inode);
    d_instantiate(dentry, inode);
    
    /* Track directory creation */
    mlfs_stats_inc_dir_create(&MLFS_SB(sb)->stats);
    
    return 0;  /* Success */
}

/*
 * Delete a file
 */
static int mlfs_unlink(struct inode *dir, struct dentry *dentry)
{
    struct super_block *sb = dir->i_sb;
    struct mlfs_inode_info *dir_mi = MLFS_I(dir);
    struct inode *inode = d_inode(dentry);
    struct mlfs_inode_info *mi = MLFS_I(inode);
    const char *name = dentry->d_name.name;
    int ret;
    
    MLFS_DEBUG("unlink: %s from dir inode %lu\n", name, dir->i_ino);
    
    /* Free the file's blocks */
    ret = mlfs_free_blocks(sb, mi->first_block, mi->block_count);
    if (ret)
        return ret;
    
    /* Remove directory entry */
    ret = mlfs_dir_remove_entry(sb, dir_mi->first_block, dir_mi->block_count, name);
    if (ret)
        return ret;
    
    drop_nlink(inode);
    mark_inode_dirty(inode);
    mark_inode_dirty(dir);
    
    /* Track file deletion */
    mlfs_stats_inc_file_delete(&MLFS_SB(sb)->stats);
    
    return 0;
}

/*
 * Delete a directory
 */
static int mlfs_rmdir(struct inode *dir, struct dentry *dentry)
{
    struct inode *inode = d_inode(dentry);
    
    MLFS_DEBUG("rmdir: %s from dir inode %lu\n", dentry->d_name.name, dir->i_ino);
    
    /* Check if directory is empty - simplified check */
    if (inode->i_nlink > 2)
        return -ENOTEMPTY;
    
    /* Use unlink to do the work */
    drop_nlink(dir);  /* Remove .. entry */
    
    /* Track directory deletion */
    mlfs_stats_inc_dir_delete(&MLFS_SB(inode->i_sb)->stats);
    
    return mlfs_unlink(dir, dentry);
}

static const struct inode_operations mlfs_dir_inode_operations = {
    .lookup     = mlfs_lookup,
    .create     = mlfs_create,
    .mkdir      = mlfs_mkdir,
    .unlink     = mlfs_unlink,
    .rmdir      = mlfs_rmdir,
};

/*
 * Helper: Read a full filesystem block (rel_block is partition-relative)
 * For multi-sector blocks, aggregates sectors into a temporary buffer
 */
static void *mlfs_read_fs_block_data(struct super_block *sb, __u32 rel_block)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    unsigned long first_sector;
    struct buffer_head *bh;
    char *data;
    unsigned int i;
    
    /* Calculate absolute sector (LBA) for this filesystem block */
    first_sector = sbi->partition_lba + (rel_block * sbi->sectors_per_block);
    
    MLFS_DEBUG("Reading fs_block %u -> LBA %lu (spb=%u)\n",
               rel_block, first_sector, sbi->sectors_per_block);
    
    /* Allocate temp buffer for the full filesystem block */
    data = kmalloc(sbi->block_size, GFP_KERNEL);
    if (!data)
        return NULL;
    
    /* Read each 512-byte sector and aggregate */
    for (i = 0; i < sbi->sectors_per_block; i++) {
        bh = sb_bread(sb, first_sector + i);
        if (!bh) {
            kfree(data);
            return NULL;
        }
        
        memcpy(data + (i * 512), bh->b_data, 512);
        brelse(bh);
    }
    
    return data;
}

/*
 * Write a filesystem block (aggregating 512-byte sectors)
 */
static int mlfs_write_fs_block_data(struct super_block *sb, __u32 rel_block, const void *data)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    unsigned long first_sector;
    struct buffer_head *bh;
    unsigned int i;
    
    /* Calculate absolute sector (LBA) for this filesystem block */
    first_sector = sbi->partition_lba + (rel_block * sbi->sectors_per_block);
    
    MLFS_DEBUG("Writing fs_block %u -> LBA %lu (spb=%u)\n",
               rel_block, first_sector, sbi->sectors_per_block);
    
    /* Write each 512-byte sector */
    for (i = 0; i < sbi->sectors_per_block; i++) {
        bh = sb_bread(sb, first_sector + i);
        if (!bh)
            return -EIO;
        
        memcpy(bh->b_data, data + (i * 512), 512);
        mark_buffer_dirty(bh);
        sync_dirty_buffer(bh);  /* Write immediately for safety */
        brelse(bh);
    }
    
    return 0;
}

/*
 * Bitmap operations for block allocation
 */

/* Get a single bit from the bitmap */
static int mlfs_bitmap_get(struct super_block *sb, __u32 bit_index, int *out_set)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    __u32 bits_per_block = sbi->block_size * 8;
    __u32 map_block = sbi->bitmap_start + (bit_index / bits_per_block);
    __u32 within = bit_index % bits_per_block;
    char *block_data;
    __u8 byte_val;
    
    /* Read bitmap block */
    block_data = mlfs_read_fs_block_data(sb, map_block);
    if (!block_data)
        return -EIO;
    
    /* Extract bit */
    byte_val = block_data[within >> 3];
    *out_set = (byte_val >> (within & 7)) & 1;
    
    kfree(block_data);
    return 0;
}

/* Set a single bit in the bitmap */
static int mlfs_bitmap_set(struct super_block *sb, __u32 bit_index, int value)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    __u32 bits_per_block = sbi->block_size * 8;
    __u32 map_block = sbi->bitmap_start + (bit_index / bits_per_block);
    __u32 within = bit_index % bits_per_block;
    char *block_data;
    __u8 *byte_ptr, mask;
    int ret;
    
    /* Read bitmap block */
    block_data = mlfs_read_fs_block_data(sb, map_block);
    if (!block_data)
        return -EIO;
    
    /* Modify bit */
    byte_ptr = (__u8 *)&block_data[within >> 3];
    mask = 1u << (within & 7);
    if (value)
        *byte_ptr |= mask;
    else
        *byte_ptr &= ~mask;
    
    /* Write back */
    ret = mlfs_write_fs_block_data(sb, map_block, block_data);
    kfree(block_data);
    
    return ret;
}

/* Find a contiguous run of free blocks */
static int mlfs_bitmap_find_run(struct super_block *sb, __u32 start_bit, 
                                  __u32 want, __u32 *out_start)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    __u32 free_run = 0, run_start = 0;
    __u32 b;
    
    for (b = start_bit; b < sbi->total_blocks; b++) {
        int set = 0;
        int ret = mlfs_bitmap_get(sb, b, &set);
        
        if (ret)
            return ret;
        
        if (!set) {  /* Free block */
            if (!free_run)
                run_start = b;
            if (++free_run >= want) {
                *out_start = run_start;
                return 0;  /* Found! */
            }
        } else {
            free_run = 0;
        }
    }
    
    return -ENOSPC;  /* No space */
}

/* Mark a run of blocks as allocated/free */
static int mlfs_bitmap_mark_run(struct super_block *sb, __u32 start, 
                                 __u32 length, int value)
{
    __u32 i;
    int ret;
    
    for (i = 0; i < length; i++) {
        ret = mlfs_bitmap_set(sb, start + i, value);
        if (ret)
            return ret;
    }
    
    return 0;
}

/* Count free blocks in bitmap */
static __u32 mlfs_count_free_blocks(struct super_block *sb)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    __u32 free_count = 0;
    __u32 b;
    int set;
    
    for (b = 0; b < sbi->total_blocks; b++) {
        if (mlfs_bitmap_get(sb, b, &set) == 0 && !set) {
            free_count++;
        }
    }
    
    return free_count;
}

/* Allocate a run of blocks (returns extent) */
static int mlfs_alloc_blocks(struct super_block *sb, __u32 blocks_wanted,
                              struct mlfs_extent *out_ext)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    __u32 start_search = sbi->root_dir_block + sbi->root_dir_blocks;
    __u32 start = 0;
    int ret;
    
    MLFS_DEBUG("Allocating %u blocks (free: %u)\n", blocks_wanted, sbi->free_blocks);
    
    /* Find free run */
    ret = mlfs_bitmap_find_run(sb, start_search, blocks_wanted, &start);
    if (ret)
        return ret;
    
    /* Mark as allocated */
    ret = mlfs_bitmap_mark_run(sb, start, blocks_wanted, 1);
    if (ret)
        return ret;
    
    out_ext->start = cpu_to_be32(start);
    out_ext->length = cpu_to_be32(blocks_wanted);
    
    /* Update free block count */
    sbi->free_blocks -= blocks_wanted;
    
    MLFS_DEBUG("Allocated blocks %u-%u (free: %u)\n", start, start + blocks_wanted - 1, sbi->free_blocks);
    
    return 0;
}

/* Free a run of blocks */
static int mlfs_free_blocks(struct super_block *sb, __u32 start, __u32 length)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    int ret;
    
    MLFS_DEBUG("Freeing blocks %u-%u\n", start, start + length - 1);
    
    ret = mlfs_bitmap_mark_run(sb, start, length, 0);
    if (ret)
        return ret;
    
    /* Update free block count */
    sbi->free_blocks += length;
    
    return 0;
}

/*
 * Directory entry management
 */

/* Add a new entry to a directory */
static int mlfs_dir_add_entry(struct super_block *sb, __u32 dir_block,
                                __u32 dir_blocks, const char *name, int is_dir,
                                struct mlfs_extent *extent, __u32 size_bytes)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    __u32 entries_per_block = sbi->dentries_per_block;
    struct mlfs_dentry *dentries;
    char *block_data;
    __u32 blk, i;
    int ret = -ENOSPC;
    
    MLFS_DEBUG("Adding '%s' to directory (is_dir=%d)\n", name, is_dir);
    
    /* Search for free slot */
    for (blk = 0; blk < dir_blocks; blk++) {
        block_data = mlfs_read_fs_block_data(sb, dir_block + blk);
        if (!block_data)
            return -EIO;
        
        dentries = (struct mlfs_dentry *)block_data;
        
        for (i = 0; i < entries_per_block; i++) {
            if (!dentries[i].in_use) {
                /* Found free slot */
                memset(&dentries[i], 0, sizeof(struct mlfs_dentry));
                dentries[i].in_use = 1;
                dentries[i].flags = is_dir ? MLFS_FLAG_DIR : MLFS_FLAG_FILE;
                dentries[i].size_bytes = cpu_to_be32(size_bytes);
                dentries[i].ctime = dentries[i].mtime = cpu_to_be32(ktime_get_real_seconds());
                dentries[i].extents_used = 1;
                strncpy(dentries[i].name, name, MLFS_MAX_NAME - 1);
                dentries[i].name[MLFS_MAX_NAME - 1] = '\0';
                dentries[i].extents[0] = *extent;
                
                ret = mlfs_write_fs_block_data(sb, dir_block + blk, block_data);
                kfree(block_data);
                
                MLFS_DEBUG("Added '%s' at block %u, entry %u\n", name, dir_block + blk, i);
                return ret;
            }
        }
        
        kfree(block_data);
    }
    
    return ret;  /* No free slots */
}

/* Remove an entry from a directory */
static int mlfs_dir_remove_entry(struct super_block *sb, __u32 dir_block,
                                   __u32 dir_blocks, const char *name)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    __u32 entries_per_block = sbi->dentries_per_block;
    struct mlfs_dentry *dentries;
    char *block_data;
    __u32 blk, i;
    int ret = -ENOENT;
    
    MLFS_DEBUG("Removing '%s' from directory\n", name);
    
    /* Search for entry */
    for (blk = 0; blk < dir_blocks; blk++) {
        block_data = mlfs_read_fs_block_data(sb, dir_block + blk);
        if (!block_data)
            return -EIO;
        
        dentries = (struct mlfs_dentry *)block_data;
        
        for (i = 0; i < entries_per_block; i++) {
            if (dentries[i].in_use && 
                strncmp(dentries[i].name, name, MLFS_MAX_NAME) == 0) {
                /* Found it - clear the entry */
                memset(&dentries[i], 0, sizeof(struct mlfs_dentry));
                
                ret = mlfs_write_fs_block_data(sb, dir_block + blk, block_data);
                kfree(block_data);
                
                MLFS_DEBUG("Removed '%s' from block %u, entry %u\n", name, dir_block + blk, i);
                return ret;
            }
        }
        
        kfree(block_data);
    }
    
    return ret;  /* Not found */
}

/* Update an entry's size in a directory */
static int mlfs_dir_update_size(struct super_block *sb, __u32 dir_block,
                                  __u32 dir_blocks, const char *name, __u32 new_size)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    __u32 entries_per_block = sbi->dentries_per_block;
    struct mlfs_dentry *dentries;
    char *block_data;
    __u32 blk, i;
    int ret = -ENOENT;
    
    MLFS_DEBUG("Updating size of '%s' to %u bytes\n", name, new_size);
    
    /* Search for entry */
    for (blk = 0; blk < dir_blocks; blk++) {
        block_data = mlfs_read_fs_block_data(sb, dir_block + blk);
        if (!block_data)
            return -EIO;
        
        dentries = (struct mlfs_dentry *)block_data;
        
        for (i = 0; i < entries_per_block; i++) {
            if (dentries[i].in_use && 
                strncmp(dentries[i].name, name, MLFS_MAX_NAME) == 0) {
                /* Found it - update size and mtime */
                dentries[i].size_bytes = cpu_to_be32(new_size);
                dentries[i].mtime = cpu_to_be32(ktime_get_real_seconds());
                
                ret = mlfs_write_fs_block_data(sb, dir_block + blk, block_data);
                kfree(block_data);
                
                MLFS_DEBUG("Updated '%s' size to %u at block %u, entry %u\n", 
                           name, new_size, dir_block + blk, i);
                return ret;
            }
        }
        
        kfree(block_data);
    }
    
    return ret;  /* Not found */
}

/*
 * File operations
 */
static int mlfs_readdir(struct file *file, struct dir_context *ctx)
{
    struct inode *inode = file_inode(file);
    struct super_block *sb = inode->i_sb;
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    struct mlfs_dentry *de;
    unsigned long dir_block;
    int i;
    
    MLFS_DEBUG("Reading directory inode %lu at pos %lld\n", inode->i_ino, ctx->pos);
    
    /* Handle . and .. */
    if (!dir_emit_dots(file, ctx))
        return 0;
    
    /* Get directory block from inode (partition-relative) */
    dir_block = MLFS_I(inode)->first_block;
    
    /* Read directory block using our helper */
    de = (struct mlfs_dentry *)mlfs_read_fs_block_data(sb, dir_block);
    if (!de)
        return -EIO;
    
    /* Emit entries */
    for (i = ctx->pos - 2; i < sbi->dentries_per_block; i++) {
        if (de[i].in_use) {
            unsigned char d_type = (de[i].flags & MLFS_FLAG_DIR) ? DT_DIR : DT_REG;
            unsigned long ino = (dir_block << 16) | i;  /* Match mlfs_iget logic */
            
            if (!dir_emit(ctx, de[i].name, strlen(de[i].name),
                         ino, d_type)) {
                kfree(de);
                return 0;
            }
            ctx->pos++;
        }
    }
    
    kfree(de);
    return 0;
}

static const struct file_operations mlfs_dir_operations = {
    .read           = generic_read_dir,
    .iterate_shared = mlfs_readdir,
    .llseek         = generic_file_llseek,
};

/*
 * File operations (regular files)
 */
static ssize_t mlfs_read(struct file *filp, char __user *buf, size_t len, loff_t *ppos)
{
    struct inode *inode = file_inode(filp);
    struct mlfs_inode_info *mi = MLFS_I(inode);
    struct super_block *sb = inode->i_sb;
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    size_t total_read = 0;
    loff_t pos = *ppos;
    
    /* Check bounds */
    if (pos >= inode->i_size)
        return 0;
    if (pos + len > inode->i_size)
        len = inode->i_size - pos;
    
    MLFS_DEBUG("Reading %zu bytes from inode %lu at offset %lld\n", 
               len, inode->i_ino, pos);
    
    /* Read data from extents */
    while (total_read < len && pos < inode->i_size) {
        unsigned long block_num;
        unsigned int block_offset;
        size_t to_read;
        char *block_data;
        
        /* Calculate which block and offset within block (partition-relative) */
        block_num = mi->first_block + (pos / sbi->block_size);
        block_offset = pos % sbi->block_size;
        to_read = min(len - total_read, sbi->block_size - block_offset);
        
        /* Read block using our helper */
        block_data = mlfs_read_fs_block_data(sb, block_num);
        if (!block_data)
            return total_read ? total_read : -EIO;
        
        /* Copy to user space */
        if (copy_to_user(buf + total_read, block_data + block_offset, to_read)) {
            kfree(block_data);
            return total_read ? total_read : -EFAULT;
        }
        
        kfree(block_data);
        
        total_read += to_read;
        pos += to_read;
    }
    
    *ppos = pos;
    
    /* Track read operation */
    if (total_read > 0)
        mlfs_stats_inc_read(&sbi->stats, total_read);
    
    return total_read;
}

/*
 * Write to a file
 */
static ssize_t mlfs_write(struct file *filp, const char __user *buf, size_t len, loff_t *ppos)
{
    struct inode *inode = file_inode(filp);
    struct mlfs_inode_info *mi = MLFS_I(inode);
    struct super_block *sb = inode->i_sb;
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    size_t total_written = 0;
    loff_t pos = *ppos;
    loff_t new_size;
    
    MLFS_DEBUG("Writing %zu bytes to inode %lu at offset %lld (current size: %lld)\n", 
               len, inode->i_ino, pos, inode->i_size);
    
    /* Calculate new file size and max size based on allocated blocks */
    new_size = pos + len;
    loff_t max_size = (loff_t)mi->block_count * sbi->block_size;
    
    /* Check if write would exceed allocated space */
    if (new_size > max_size) {
        /* TODO: Implement block allocation for growing files beyond initial allocation */
        MLFS_DEBUG("Write would exceed allocated space (%lld > %lld)\n", new_size, max_size);
        return -ENOSPC;
    }
    
    /* Write data to extents */
    while (total_written < len) {
        unsigned long block_num;
        unsigned int block_offset;
        size_t to_write;
        char *block_data;
        int ret;
        
        /* Calculate which block and offset within block (partition-relative) */
        block_num = mi->first_block + (pos / sbi->block_size);
        block_offset = pos % sbi->block_size;
        to_write = min(len - total_written, sbi->block_size - block_offset);
        
        /* Read existing block first (for partial writes) */
        block_data = mlfs_read_fs_block_data(sb, block_num);
        if (!block_data)
            return total_written ? total_written : -EIO;
        
        /* Copy from user space into block buffer */
        if (copy_from_user(block_data + block_offset, buf + total_written, to_write)) {
            kfree(block_data);
            return total_written ? total_written : -EFAULT;
        }
        
        /* Write block back */
        ret = mlfs_write_fs_block_data(sb, block_num, block_data);
        kfree(block_data);
        
        if (ret < 0)
            return total_written ? total_written : ret;
        
        total_written += to_write;
        pos += to_write;
    }
    
    /* Update file size if needed */
    if (pos > inode->i_size) {
        int update_ret;
        inode->i_size = pos;
        mark_inode_dirty(inode);
        
        /* Update directory entry with new size */
        update_ret = mlfs_dir_update_size(sb, mi->parent_dir_block, mi->parent_dir_blocks,
                                           mi->filename, (u32)pos);
        if (update_ret < 0) {
            MLFS_DEBUG("Warning: Failed to update directory entry size\n");
            /* Continue anyway - inode has the correct size */
        }
    }
    
    *ppos = pos;
    
    /* Track write operation */
    if (total_written > 0)
        mlfs_stats_inc_write(&sbi->stats, total_written);
    
    return total_written;
}

/*
 * Sync file data to disk
 */
static int mlfs_fsync(struct file *file, loff_t start, loff_t end, int datasync)
{
    struct inode *inode = file->f_inode;
    int ret;
    
    MLFS_DEBUG("fsync inode %lu\n", inode->i_ino);
    
    /* Sync all dirty buffers for this device */
    ret = sync_blockdev(inode->i_sb->s_bdev);
    if (ret)
        return ret;
    
    /* Mark inode as clean */
    mark_inode_dirty_sync(inode);
    
    return 0;
}

static const struct file_operations mlfs_file_operations = {
    .read       = mlfs_read,
    .write      = mlfs_write,
    .fsync      = mlfs_fsync,
    .llseek     = generic_file_llseek,
};

static const struct inode_operations mlfs_file_inode_operations = {
    /* Minimal operations for regular files */
};

/*
 * Inode creation/initialization
 */
struct inode *mlfs_iget(struct super_block *sb, struct mlfs_dentry *de,
                         unsigned long dir_block, int dentry_idx,
                         __u32 parent_dir_block, __u32 parent_dir_blocks)
{
    struct inode *inode;
    struct mlfs_inode_info *mi;
    unsigned long ino;
    
    /* Generate inode number from directory block and entry index */
    ino = (dir_block << 16) | dentry_idx;
    
    MLFS_DEBUG("Creating inode %lu for '%s'\n", ino, de->name);
    
    /* Allocate inode */
    inode = iget_locked(sb, ino);
    if (!inode)
        return ERR_PTR(-ENOMEM);
    
    if (!(inode->i_state & I_NEW))
        return inode;
    
    /* Initialize inode */
    mi = MLFS_I(inode);
    mi->first_block = be32_to_cpu(de->extents[0].start);
    mi->block_count = be32_to_cpu(de->extents[0].length);
    mi->parent_dir_block = parent_dir_block;
    mi->parent_dir_blocks = parent_dir_blocks;
    strncpy(mi->filename, de->name, MLFS_MAX_NAME - 1);
    mi->filename[MLFS_MAX_NAME - 1] = '\0';
    
    inode->i_size = be32_to_cpu(de->size_bytes);
    inode->i_blocks = mi->block_count;
    
    /* Set timestamps - kernel 6.6+ uses inode_set_* functions */
    struct timespec64 mtime = { .tv_sec = be32_to_cpu(de->mtime), .tv_nsec = 0 };
    struct timespec64 ctime = { .tv_sec = be32_to_cpu(de->ctime), .tv_nsec = 0 };
    inode_set_mtime_to_ts(inode, mtime);
    inode_set_atime_to_ts(inode, mtime);
    inode_set_ctime_to_ts(inode, ctime);
    
    if (de->flags & MLFS_FLAG_DIR) {
        inode->i_mode = S_IFDIR | 0755;
        inode->i_op = &mlfs_dir_inode_operations;
        inode->i_fop = &mlfs_dir_operations;
        set_nlink(inode, 2);
    } else {
        inode->i_mode = S_IFREG | 0644;
        inode->i_op = &mlfs_file_inode_operations;
        inode->i_fop = &mlfs_file_operations;
        set_nlink(inode, 1);
    }
    
    unlock_new_inode(inode);
    return inode;
}

/*
 * Read and parse MLFS superblock
 */
static int mlfs_read_super(struct super_block *sb, unsigned long partition_lba,
                             struct mlfs_sb_info *sbi)
{
    struct buffer_head *bh;
    struct mlfs_superblock *mlfs_sb;
    
    MLFS_DEBUG("Reading superblock from LBA %lu\n", partition_lba);
    
    /* Read superblock (first 512 bytes of partition) */
    bh = sb_bread(sb, partition_lba);
    if (!bh) {
        pr_err("mlfs: Failed to read superblock\n");
        return -EIO;
    }
    
    mlfs_sb = (struct mlfs_superblock *)bh->b_data;
    
    /* Verify magic */
    if (be32_to_cpu(mlfs_sb->magic) != MLFS_MAGIC) {
        pr_err("mlfs: Invalid superblock magic: 0x%x\n", be32_to_cpu(mlfs_sb->magic));
        brelse(bh);
        return -EINVAL;
    }
    
    /* Validate log2_block_size before using it */
    if (mlfs_sb->log2_block_size < 9 || mlfs_sb->log2_block_size > 16) {
        pr_err("mlfs: Invalid log2_block_size: %u (must be 9-16)\n", 
               mlfs_sb->log2_block_size);
        brelse(bh);
        return -EINVAL;
    }
    
    /* Copy superblock info */
    sbi->block_size = 1U << mlfs_sb->log2_block_size;
    sbi->total_blocks = be32_to_cpu(mlfs_sb->total_blocks);
    sbi->bitmap_start = be32_to_cpu(mlfs_sb->bitmap_start);
    sbi->bitmap_blocks = be32_to_cpu(mlfs_sb->bitmap_blocks);
    sbi->root_dir_block = be32_to_cpu(mlfs_sb->root_dir_block);
    sbi->root_dir_blocks = be32_to_cpu(mlfs_sb->root_dir_blocks);
    sbi->partition_lba = partition_lba;
    
    /* Validate critical fields */
    if (sbi->total_blocks == 0) {
        pr_err("mlfs: Invalid total_blocks: 0\n");
        brelse(bh);
        return -EINVAL;
    }
    
    if (sbi->root_dir_blocks == 0) {
        pr_err("mlfs: Invalid root_dir_blocks: 0\n");
        brelse(bh);
        return -EINVAL;
    }
    
    sbi->dentries_per_block = sbi->block_size / sizeof(struct mlfs_dentry);
    sbi->sectors_per_block = sbi->block_size / 512;
    
    brelse(bh);
    
    /* Count free blocks from bitmap (do this after brelse) */
    sbi->free_blocks = mlfs_count_free_blocks(sb);
    
    MLFS_DEBUG("Superblock: block_size=%lu, total_blocks=%u, free_blocks=%u, root_dir=%u, spb=%u\n",
               sbi->block_size, sbi->total_blocks, sbi->free_blocks, sbi->root_dir_block, sbi->sectors_per_block);
    
    return 0;
}

/*
 * Read and parse partition table
 */
static int mlfs_read_partition_table(struct super_block *sb, unsigned int partition_num,
                                       unsigned long *out_lba)
{
    struct buffer_head *bh;
    struct mlpt *pt;
    
    MLFS_DEBUG("Reading partition table (partition %u)\n", partition_num);
    
    /* Read partition table from LBA 0 */
    bh = sb_bread(sb, 0);
    if (!bh) {
        pr_err("mlfs: Failed to read partition table\n");
        return -EIO;
    }
    
    pt = (struct mlpt *)bh->b_data;
    
    /* Verify magic */
    if (be32_to_cpu(pt->magic) != MLPT_MAGIC) {
        pr_err("mlfs: Invalid partition table magic: 0x%x\n", be32_to_cpu(pt->magic));
        brelse(bh);
        return -EINVAL;
    }
    
    /* Check partition exists */
    if (partition_num >= be16_to_cpu(pt->count)) {
        pr_err("mlfs: Partition %u does not exist (count=%u)\n", 
               partition_num, be16_to_cpu(pt->count));
        brelse(bh);
        return -EINVAL;
    }
    
    /* Get partition start LBA */
    *out_lba = be32_to_cpu(pt->entries[partition_num].start_lba);
    
    MLFS_DEBUG("Partition %u starts at LBA %lu\n", partition_num, *out_lba);
    
    brelse(bh);
    return 0;
}

/*
 * Mount options parsing
 */
enum {
    Opt_partition,
    Opt_err
};

static const match_table_t tokens = {
    {Opt_partition, "partition=%u"},
    {Opt_err, NULL}
};

static int mlfs_parse_options(char *options, unsigned int *partition)
{
    substring_t args[MAX_OPT_ARGS];
    char *p;
    int option;
    
    *partition = 0;  /* Default to partition 0 */
    
    if (!options)
        return 0;
    
    while ((p = strsep(&options, ",")) != NULL) {
        int token;
        
        if (!*p)
            continue;
        
        token = match_token(p, tokens, args);
        switch (token) {
        case Opt_partition:
            if (match_int(&args[0], &option))
                return -EINVAL;
            *partition = option;
            break;
        default:
            pr_err("mlfs: Unrecognized mount option \"%s\"\n", p);
            return -EINVAL;
        }
    }
    
    return 0;
}

/*
 * Fill super block
 */
static int mlfs_fill_super(struct super_block *sb, void *data, int silent)
{
    struct mlfs_sb_info *sbi;
    struct inode *root_inode;
    unsigned int partition_num;
    unsigned long partition_lba;
    int ret;
    
    MLFS_DEBUG("Filling super block\n");
    
    /* Parse mount options */
    ret = mlfs_parse_options(data, &partition_num);
    if (ret)
        return ret;
    
    /* Allocate superblock info */
    sbi = kzalloc(sizeof(*sbi), GFP_KERNEL);
    if (!sbi)
        return -ENOMEM;
    
    sbi->partition_num = partition_num;
    sb->s_fs_info = sbi;
    
    /* Initialize statistics counters */
    mlfs_stats_init(&sbi->stats);
    
    /* Set initial block size for reading partition table */
    sb_set_blocksize(sb, 512);
    
    /* Read partition table */
    ret = mlfs_read_partition_table(sb, partition_num, &partition_lba);
    if (ret)
        goto failed_mount;
    
    /* Read superblock */
    ret = mlfs_read_super(sb, partition_lba, sbi);
    if (ret)
        goto failed_mount;
    
    /* Keep using 512-byte blocks to handle misaligned partitions */
    /* We'll aggregate sectors when reading filesystem blocks */
    
    MLFS_DEBUG("Partition at LBA %lu, block_size=%lu, sectors_per_block=%u\n",
               partition_lba, sbi->block_size, sbi->sectors_per_block);
    
    /* Setup super block */
    sb->s_magic = MLFS_MAGIC;
    sb->s_op = &mlfs_super_ops;
    sb->s_maxbytes = MAX_LFS_FILESIZE;
    /* Write support enabled */
    
    /* Create root inode */
    root_inode = new_inode(sb);
    if (!root_inode) {
        ret = -ENOMEM;
        goto failed_mount;
    }
    
    root_inode->i_ino = MLFS_ROOT_INO;
    root_inode->i_mode = S_IFDIR | 0755;
    root_inode->i_op = &mlfs_dir_inode_operations;
    root_inode->i_fop = &mlfs_dir_operations;
    set_nlink(root_inode, 2);
    
    /* Store partition-relative block number (we'll add partition offset when reading) */
    MLFS_I(root_inode)->first_block = sbi->root_dir_block;
    MLFS_I(root_inode)->block_count = sbi->root_dir_blocks;
    MLFS_I(root_inode)->parent_dir_block = sbi->root_dir_block;  /* Root is its own parent */
    MLFS_I(root_inode)->parent_dir_blocks = sbi->root_dir_blocks;
    strncpy(MLFS_I(root_inode)->filename, "/", MLFS_MAX_NAME - 1);
    
    sb->s_root = d_make_root(root_inode);
    if (!sb->s_root) {
        ret = -ENOMEM;
        goto failed_mount;
    }
    
    pr_info("mlfs: Mounted partition %u (block size %lu, %u blocks)\n",
            partition_num, sbi->block_size, sbi->total_blocks);
    
    /* Create proc filesystem entry */
    ret = mlfs_proc_create(sb);
    if (ret) {
        pr_warn("mlfs: Failed to create proc entry (non-fatal)\n");
        /* Continue anyway - this is not fatal */
    }
    
    return 0;
    
failed_mount:
    kfree(sbi);
    sb->s_fs_info = NULL;
    return ret;
}

/*
 * Mount filesystem
 */
static struct dentry *mlfs_mount(struct file_system_type *fs_type,
                                  int flags, const char *dev_name,
                                  void *data)
{
    MLFS_DEBUG("Mounting %s\n", dev_name);
    return mount_bdev(fs_type, flags, dev_name, data, mlfs_fill_super);
}

/*
 * Unmount filesystem
 */
static void mlfs_kill_sb(struct super_block *sb)
{
    MLFS_DEBUG("Killing super block\n");
    kill_block_super(sb);
}

/*
 * Inode cache constructor - called once when slab objects are allocated
 * This is REQUIRED to initialize the VFS inode's internal list structures
 */
static void mlfs_init_once(void *foo)
{
    struct mlfs_inode_info *mi = (struct mlfs_inode_info *)foo;
    
    /* Initialize the VFS inode's list heads and other fields */
    inode_init_once(&mi->vfs_inode);
}

/*
 * Module initialization
 */
static int __init mlfs_init(void)
{
    int ret;
    
    pr_info("mlfs: MicroLind File System v0.4.0 (full read-write with statistics)\n");
    
    /* Create proc filesystem root directory */
    ret = mlfs_proc_init();
    if (ret)
        return ret;
    
    /* Register inode cache with constructor */
    mlfs_inode_cachep = kmem_cache_create("mlfs_inode_cache",
                                           sizeof(struct mlfs_inode_info),
                                           0,
                                           SLAB_RECLAIM_ACCOUNT,  /* SLAB_MEM_SPREAD removed in kernel 6.9+ */
                                           mlfs_init_once);
    if (!mlfs_inode_cachep) {
        mlfs_proc_exit();
        return -ENOMEM;
    }
    
    /* Register filesystem */
    ret = register_filesystem(&mlfs_fs_type);
    if (ret) {
        pr_err("mlfs: Failed to register filesystem\n");
        kmem_cache_destroy(mlfs_inode_cachep);
        mlfs_proc_exit();
        return ret;
    }
    
    pr_info("mlfs: Filesystem registered successfully\n");
    return 0;
}

/*
 * Module cleanup
 */
static void __exit mlfs_exit(void)
{
    unregister_filesystem(&mlfs_fs_type);
    kmem_cache_destroy(mlfs_inode_cachep);
    
    /* Remove proc filesystem root */
    mlfs_proc_exit();
    
    pr_info("mlfs: Filesystem unregistered\n");
}

module_init(mlfs_init);
module_exit(mlfs_exit);
