/*
 * MLFS Kernel Module - Proc Filesystem Implementation
 * Provides filesystem statistics through /proc/fs/mlfs/
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>

#include "mlfs_module.h"
#include "mlfs_proc.h"

/* Proc filesystem root directory */
struct proc_dir_entry *mlfs_proc_root = NULL;

/*
 * Display filesystem statistics in proc file
 */
static int mlfs_proc_show(struct seq_file *m, void *v)
{
    struct super_block *sb = m->private;
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    __u32 used_blocks;
    
    if (!sbi)
        return 0;
    
    used_blocks = sbi->total_blocks - sbi->free_blocks;
    
    seq_printf(m, "MLFS Filesystem Statistics\n");
    seq_printf(m, "==========================\n\n");
    
    /* Device Information */
    seq_printf(m, "Device Information:\n");
    seq_printf(m, "-------------------\n");
    seq_printf(m, "Device:           %s\n", sbi->device_name);
    seq_printf(m, "Partition:        %u\n", sbi->partition_num);
    seq_printf(m, "Partition LBA:    %lu\n", sbi->partition_lba);
    seq_printf(m, "\n");
    
    /* Block Configuration */
    seq_printf(m, "Block Configuration:\n");
    seq_printf(m, "--------------------\n");
    seq_printf(m, "Block Size:       %lu bytes\n", sbi->block_size);
    seq_printf(m, "Sectors/Block:    %u\n", sbi->sectors_per_block);
    seq_printf(m, "\n");
    
    /* Space Usage */
    seq_printf(m, "Space Usage:\n");
    seq_printf(m, "------------\n");
    seq_printf(m, "Total Blocks:     %u\n", sbi->total_blocks);
    seq_printf(m, "Used Blocks:      %u\n", used_blocks);
    seq_printf(m, "Free Blocks:      %u\n", sbi->free_blocks);
    seq_printf(m, "Usage:            %u%%\n", 
               sbi->total_blocks ? (used_blocks * 100) / sbi->total_blocks : 0);
    seq_printf(m, "\n");
    
    seq_printf(m, "Total Space:      %llu bytes (%llu KB, %llu MB)\n",
               (u64)sbi->total_blocks * sbi->block_size,
               (u64)sbi->total_blocks * sbi->block_size / 1024,
               (u64)sbi->total_blocks * sbi->block_size / 1024 / 1024);
    seq_printf(m, "Used Space:       %llu bytes (%llu KB, %llu MB)\n",
               (u64)used_blocks * sbi->block_size,
               (u64)used_blocks * sbi->block_size / 1024,
               (u64)used_blocks * sbi->block_size / 1024 / 1024);
    seq_printf(m, "Free Space:       %llu bytes (%llu KB, %llu MB)\n",
               (u64)sbi->free_blocks * sbi->block_size,
               (u64)sbi->free_blocks * sbi->block_size / 1024,
               (u64)sbi->free_blocks * sbi->block_size / 1024 / 1024);
    seq_printf(m, "\n");
    
    /* Filesystem Layout */
    seq_printf(m, "Filesystem Layout:\n");
    seq_printf(m, "------------------\n");
    seq_printf(m, "Bitmap Start:     %u\n", sbi->bitmap_start);
    seq_printf(m, "Bitmap Blocks:    %u\n", sbi->bitmap_blocks);
    seq_printf(m, "Root Dir Block:   %u\n", sbi->root_dir_block);
    seq_printf(m, "Root Dir Blocks:  %u\n", sbi->root_dir_blocks);
    seq_printf(m, "Entries/Block:    %u\n", sbi->dentries_per_block);
    seq_printf(m, "\n");
    
    /* Operation Statistics */
    seq_printf(m, "Operation Statistics:\n");
    seq_printf(m, "---------------------\n");
    seq_printf(m, "Read Operations:  %llu\n", 
               (u64)atomic64_read(&sbi->stats.read_ops));
    seq_printf(m, "Write Operations: %llu\n", 
               (u64)atomic64_read(&sbi->stats.write_ops));
    seq_printf(m, "Read Bytes:       %llu (%llu KB, %llu MB)\n",
               (u64)atomic64_read(&sbi->stats.read_bytes),
               (u64)atomic64_read(&sbi->stats.read_bytes) / 1024,
               (u64)atomic64_read(&sbi->stats.read_bytes) / 1024 / 1024);
    seq_printf(m, "Write Bytes:      %llu (%llu KB, %llu MB)\n",
               (u64)atomic64_read(&sbi->stats.write_bytes),
               (u64)atomic64_read(&sbi->stats.write_bytes) / 1024,
               (u64)atomic64_read(&sbi->stats.write_bytes) / 1024 / 1024);
    seq_printf(m, "Errors:           %llu\n", 
               (u64)atomic64_read(&sbi->stats.errors));
    seq_printf(m, "\n");
    
    /* File/Directory Operations */
    seq_printf(m, "File/Directory Operations:\n");
    seq_printf(m, "--------------------------\n");
    seq_printf(m, "Directory Lookups: %llu\n", 
               (u64)atomic64_read(&sbi->stats.dir_lookups));
    seq_printf(m, "Files Created:     %llu\n", 
               (u64)atomic64_read(&sbi->stats.file_creates));
    seq_printf(m, "Files Deleted:     %llu\n", 
               (u64)atomic64_read(&sbi->stats.file_deletes));
    seq_printf(m, "Dirs Created:      %llu\n", 
               (u64)atomic64_read(&sbi->stats.dir_creates));
    seq_printf(m, "Dirs Deleted:      %llu\n", 
               (u64)atomic64_read(&sbi->stats.dir_deletes));
    
    return 0;
}

/*
 * Open callback for proc file
 */
static int mlfs_proc_open(struct inode *inode, struct file *file)
{
    return single_open(file, mlfs_proc_show, pde_data(inode));
}

/*
 * Proc file operations
 */
static const struct proc_ops mlfs_proc_ops = {
    .proc_open    = mlfs_proc_open,
    .proc_read    = seq_read,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};

/*
 * Initialize proc filesystem
 */
int mlfs_proc_init(void)
{
    /* Create /proc/fs/mlfs/ directory */
    mlfs_proc_root = proc_mkdir("fs/mlfs", NULL);
    if (!mlfs_proc_root) {
        pr_err("mlfs: Failed to create /proc/fs/mlfs\n");
        return -ENOMEM;
    }
    
    pr_info("mlfs: Created /proc/fs/mlfs\n");
    return 0;
}

/*
 * Cleanup proc filesystem
 */
void mlfs_proc_exit(void)
{
    if (mlfs_proc_root) {
        proc_remove(mlfs_proc_root);
        mlfs_proc_root = NULL;
        pr_info("mlfs: Removed /proc/fs/mlfs\n");
    }
}

/*
 * Create proc entry for a mounted filesystem
 */
int mlfs_proc_create(struct super_block *sb)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    char *slash;
    
    if (!mlfs_proc_root)
        return -ENOENT;
    
    /* Create sanitized device name (replace / with _) */
    strncpy(sbi->device_name, sb->s_id, sizeof(sbi->device_name) - 1);
    sbi->device_name[sizeof(sbi->device_name) - 1] = '\0';
    
    /* Replace slashes with underscores */
    while ((slash = strchr(sbi->device_name, '/')) != NULL)
        *slash = '_';
    
    /* Create proc directory for this filesystem */
    sbi->proc_dir = proc_mkdir(sbi->device_name, mlfs_proc_root);
    if (!sbi->proc_dir) {
        pr_err("mlfs: Failed to create proc directory for %s\n", sbi->device_name);
        return -ENOMEM;
    }
    
    /* Create stats file */
    if (!proc_create_data("stats", 0444, sbi->proc_dir, &mlfs_proc_ops, sb)) {
        pr_err("mlfs: Failed to create proc stats file\n");
        proc_remove(sbi->proc_dir);
        sbi->proc_dir = NULL;
        return -ENOMEM;
    }
    
    pr_info("mlfs: Created /proc/fs/mlfs/%s/stats\n", sbi->device_name);
    
    return 0;
}

/*
 * Remove proc entry for a filesystem
 */
void mlfs_proc_destroy(struct super_block *sb)
{
    struct mlfs_sb_info *sbi = MLFS_SB(sb);
    
    if (sbi && sbi->proc_dir) {
        proc_remove(sbi->proc_dir);
        sbi->proc_dir = NULL;
        pr_info("mlfs: Removed /proc/fs/mlfs/%s/\n", sbi->device_name);
    }
}

