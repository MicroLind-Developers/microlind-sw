/****************************** mlfs.c **************************************/
#include "mlfs.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef MLFS_ASSERT
#define MLFS_ASSERT(x)                                                          \
    do {                                                                        \
        if(!(x)) {                                                              \
            fprintf(stderr, "MLFS ASSERT %s:%d: %s\n", __FILE__, __LINE__, #x); \
            abort();                                                            \
        }                                                                       \
    } while(0)
#endif

// ---- Forward declarations for static functions ----
static int mlfs_split_path(const char* path, char components[][MLFS_MAX_NAME], int max_components);
static int mlfs_resolve_path(mlfs_t* fs, const char* path, uint32_t* target_dir_block, uint32_t* target_dir_blocks, char* filename);
static int mlfs_path_is_descendant(const char* parent_path, const char* child_path);
static int mlfs_dir_lookup_in_dir(const mlfs_t* fs, uint32_t dir_first_block, uint32_t dir_num_blocks, const char* name, mlfs_dentry_t* out,
                                  uint32_t* out_block, uint32_t* out_index);
static int mlfs_dir_add_entry_to_dir(const mlfs_t* fs, uint32_t dir_first_block, uint32_t dir_num_blocks, const char* name, int is_dir,
                                     mlfs_extent_t first_ext, uint32_t size_bytes);
static int mlfs_dir_add_existing_entry_to_dir(const mlfs_t* fs, uint32_t dir_first_block, uint32_t dir_num_blocks, const mlfs_dentry_t* entry);
static int mlfs_dir_write_entry_at(const mlfs_t* fs, uint32_t block_addr, uint32_t index, const mlfs_dentry_t* entry);
static int mlfs_dir_remove_entry_from_dir(const mlfs_t* fs, uint32_t dir_first_block, uint32_t dir_num_blocks, const char* name);
static int mlfs_dir_count_entries_in_dir(const mlfs_t* fs, uint32_t dir_first_block, uint32_t dir_num_blocks, uint32_t* count_out);

// ---- utils ----
static uint32_t mlfs_now_unix(void)
{
    return (uint32_t)time(NULL);
}

static uint32_t mlfs_cksum32(const void* p, size_t n)
{
    const uint8_t* b = (const uint8_t*)p;
    uint32_t       s = 0;
    for(size_t i = 0; i < n; i++)
        s += b[i];
    return s;
}

static void mlfs_fill_uuid(uint32_t out[4])
{
    for(int i = 0; i < 4; i++)
        out[i] = (uint32_t)rand() ^ ((uint32_t)rand() << 16) ^ (uint32_t)clock();
}

// ---- on-disk big-endian encoding helpers ----
static uint16_t mlfs_get_be16(const uint8_t* p)
{
    return ((uint16_t)p[0] << 8) | (uint16_t)p[1];
}

static uint32_t mlfs_get_be32(const uint8_t* p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static void mlfs_put_be16(uint8_t* p, uint16_t v)
{
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)v;
}

static void mlfs_put_be32(uint8_t* p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static void mlfs_decode_extent(const uint8_t* src, mlfs_extent_t* dst)
{
    dst->start  = mlfs_get_be32(src + 0);
    dst->length = mlfs_get_be32(src + 4);
}

static void mlfs_encode_extent(uint8_t* dst, const mlfs_extent_t* src)
{
    mlfs_put_be32(dst + 0, src->start);
    mlfs_put_be32(dst + 4, src->length);
}

static void mlfs_decode_dentry(const uint8_t* src, mlfs_dentry_t* dst)
{
    memset(dst, 0, sizeof(*dst));
    dst->in_use        = src[0];
    dst->flags         = src[1];
    dst->size_bytes    = mlfs_get_be32(src + 2);
    dst->mtime         = mlfs_get_be32(src + 6);
    dst->ctime         = mlfs_get_be32(src + 10);
    dst->extents_used  = src[14];
    dst->extents_total = src[15];
    memcpy(dst->name, src + 16, MLFS_MAX_NAME);
    for(size_t i = 0; i < 4; i++)
        mlfs_decode_extent(src + 64 + (i * sizeof(mlfs_extent_t)), &dst->extents[i]);
    dst->first_indirect = mlfs_get_be32(src + 96);
    memcpy(dst->reserved, src + 100, sizeof(dst->reserved));
}

static void mlfs_encode_dentry(uint8_t* dst, const mlfs_dentry_t* src)
{
    memset(dst, 0, sizeof(mlfs_dentry_t));
    dst[0]  = src->in_use;
    dst[1]  = src->flags;
    dst[14] = src->extents_used;
    dst[15] = src->extents_total;
    mlfs_put_be32(dst + 2, src->size_bytes);
    mlfs_put_be32(dst + 6, src->mtime);
    mlfs_put_be32(dst + 10, src->ctime);
    memcpy(dst + 16, src->name, MLFS_MAX_NAME);
    for(size_t i = 0; i < 4; i++)
        mlfs_encode_extent(dst + 64 + (i * sizeof(mlfs_extent_t)), &src->extents[i]);
    mlfs_put_be32(dst + 96, src->first_indirect);
    memcpy(dst + 100, src->reserved, sizeof(src->reserved));
}

static void mlfs_decode_dentry_block(void* block, uint32_t bytes_per_block)
{
    uint8_t*       raw = (uint8_t*)block;
    mlfs_dentry_t* de  = (mlfs_dentry_t*)block;
    uint32_t       per = bytes_per_block / sizeof(mlfs_dentry_t);
    for(uint32_t i = 0; i < per; i++) {
        mlfs_dentry_t tmp;
        mlfs_decode_dentry(raw + (i * sizeof(mlfs_dentry_t)), &tmp);
        de[i] = tmp;
    }
}

static void mlfs_encode_dentry_block(void* block, uint32_t bytes_per_block)
{
    uint8_t*       raw = (uint8_t*)block;
    mlfs_dentry_t* de  = (mlfs_dentry_t*)block;
    uint32_t       per = bytes_per_block / sizeof(mlfs_dentry_t);
    for(uint32_t i = 0; i < per; i++) {
        mlfs_dentry_t tmp = de[i];
        mlfs_encode_dentry(raw + (i * sizeof(mlfs_dentry_t)), &tmp);
    }
}

static void mlfs_decode_mlpt(const uint8_t sec[512], mlpt_t* out)
{
    memset(out, 0, sizeof(*out));
    out->magic = mlfs_get_be32(sec + 0);
    out->major = sec[4];
    out->minor = sec[5];
    out->patch = sec[6];
    out->count = mlfs_get_be16(sec + 7);
    for(uint16_t i = 0; i < MLPT_MAX_PARTS; i++) {
        const uint8_t* src       = sec + 9 + (i * sizeof(mlpt_entry_t));
        out->entries[i].start_lba       = mlfs_get_be32(src + 0);
        out->entries[i].block_count     = mlfs_get_be32(src + 4);
        out->entries[i].type            = src[8];
        out->entries[i].log2_block_size = src[9];
        memcpy(out->entries[i].name, src + 10, sizeof(out->entries[i].name));
    }
}

static void mlfs_encode_mlpt(uint8_t sec[512], const mlpt_t* pt)
{
    memset(sec, 0, 512);
    mlfs_put_be32(sec + 0, pt->magic);
    sec[4] = pt->major;
    sec[5] = pt->minor;
    sec[6] = pt->patch;
    mlfs_put_be16(sec + 7, pt->count);
    for(uint16_t i = 0; i < MLPT_MAX_PARTS; i++) {
        uint8_t* src = sec + 9 + (i * sizeof(mlpt_entry_t));
        mlfs_put_be32(src + 0, pt->entries[i].start_lba);
        mlfs_put_be32(src + 4, pt->entries[i].block_count);
        src[8] = pt->entries[i].type;
        src[9] = pt->entries[i].log2_block_size;
        memcpy(src + 10, pt->entries[i].name, sizeof(pt->entries[i].name));
    }
}

static void mlfs_decode_superblock(const uint8_t sec[512], mlfs_superblock_t* sb)
{
    memset(sb, 0, sizeof(*sb));
    sb->magic           = mlfs_get_be32(sec + 0);
    sb->major           = sec[4];
    sb->minor           = sec[5];
    sb->patch           = sec[6];
    sb->log2_block_size = sec[7];
    sb->reserved0       = sec[8];
    sb->total_blocks    = mlfs_get_be32(sec + 9);
    sb->bitmap_start    = mlfs_get_be32(sec + 13);
    sb->bitmap_blocks   = mlfs_get_be32(sec + 17);
    sb->root_dir_block  = mlfs_get_be32(sec + 21);
    sb->root_dir_blocks = mlfs_get_be32(sec + 25);
    for(size_t i = 0; i < 4; i++)
        sb->uuid[i] = mlfs_get_be32(sec + 29 + (i * sizeof(uint32_t)));
    sb->checksum = mlfs_get_be32(sec + 45);
    memcpy(sb->reserved, sec + 49, sizeof(sb->reserved));
}

static void mlfs_encode_superblock(uint8_t sec[512], const mlfs_superblock_t* sb)
{
    memset(sec, 0, 512);
    mlfs_put_be32(sec + 0, sb->magic);
    sec[4] = sb->major;
    sec[5] = sb->minor;
    sec[6] = sb->patch;
    sec[7] = sb->log2_block_size;
    sec[8] = sb->reserved0;
    mlfs_put_be32(sec + 9, sb->total_blocks);
    mlfs_put_be32(sec + 13, sb->bitmap_start);
    mlfs_put_be32(sec + 17, sb->bitmap_blocks);
    mlfs_put_be32(sec + 21, sb->root_dir_block);
    mlfs_put_be32(sec + 25, sb->root_dir_blocks);
    for(size_t i = 0; i < 4; i++)
        mlfs_put_be32(sec + 29 + (i * sizeof(uint32_t)), sb->uuid[i]);
    mlfs_put_be32(sec + 45, sb->checksum);
    memcpy(sec + 49, sb->reserved, sizeof(sb->reserved));
}

// ---- low-level block IO ----
static int mlfs_read_block(const mlfs_t* fs, uint32_t rel_block, void* buf)
{
    uint32_t spb = fs->bytes_per_block / fs->io.sector_size;
    uint64_t lba = (uint64_t)fs->part.start_lba + (uint64_t)rel_block * spb;
    return fs->io.read(fs->io.ctx, lba, spb, buf);
}

static int mlfs_write_block(const mlfs_t* fs, uint32_t rel_block, const void* buf)
{
    uint32_t spb = fs->bytes_per_block / fs->io.sector_size;
    uint64_t lba = (uint64_t)fs->part.start_lba + (uint64_t)rel_block * spb;
    return fs->io.write(fs->io.ctx, lba, spb, buf);
}

// ---- bitmap helpers ----
static uint32_t mlfs_bitmap_bits_per_block(const mlfs_t* fs)
{
    return (fs->bytes_per_block * 8u);
}

__attribute__((unused)) static uint32_t mlfs_bitmap_blocks_needed(const mlfs_t* fs, uint32_t total_blocks)
{
    uint32_t per = mlfs_bitmap_bits_per_block(fs);
    return (total_blocks + per - 1) / per;
}

static int mlfs_bitmap_get(const mlfs_t* fs, uint32_t bit_index, int* out_set)
{
    uint32_t per       = mlfs_bitmap_bits_per_block(fs);
    uint32_t map_block = fs->sb.bitmap_start + (bit_index / per);
    uint32_t within    = bit_index % per;
    uint8_t* blk       = (uint8_t*)malloc(fs->bytes_per_block);
    if(!blk)
        return -1;
    if(mlfs_read_block(fs, map_block, blk) != 0) {
        free(blk);
        return -1;
    }
    uint8_t v   = blk[within >> 3];
    int     set = (v >> (within & 7)) & 1;
    free(blk);
    *out_set = set;
    return 0;
}

static int mlfs_bitmap_set(const mlfs_t* fs, uint32_t bit_index, int value)
{
    uint32_t per       = mlfs_bitmap_bits_per_block(fs);
    uint32_t map_block = fs->sb.bitmap_start + (bit_index / per);
    uint32_t within    = bit_index % per;
    uint8_t* blk       = (uint8_t*)malloc(fs->bytes_per_block);
    if(!blk)
        return -1;
    if(mlfs_read_block(fs, map_block, blk) != 0) {
        free(blk);
        return -1;
    }
    uint8_t* byte = &blk[within >> 3];
    uint8_t  mask = 1u << (within & 7);
    if(value)
        *byte |= mask;
    else
        *byte &= (uint8_t)~mask;
    int rc = mlfs_write_block(fs, map_block, blk);
    free(blk);
    return rc;
}

static int mlfs_bitmap_find_run(const mlfs_t* fs, uint32_t start_bit, uint32_t want, uint32_t* out_start)
{
    uint32_t free_run = 0, run_start = 0;
    for(uint32_t b = start_bit; b < fs->sb.total_blocks; ++b) {
        int set = 0;
        if(mlfs_bitmap_get(fs, b, &set) != 0)
            return -1;
        if(!set) {
            if(!free_run)
                run_start = b;
            if(++free_run >= want) {
                *out_start = run_start;
                return 0;
            }
        } else
            free_run = 0;
    }
    return 1;
}

static int mlfs_bitmap_mark_run(const mlfs_t* fs, uint32_t start, uint32_t len, int value)
{
    for(uint32_t i = 0; i < len; i++) {
        int rc = mlfs_bitmap_set(fs, start + i, value);
        if(rc)
            return rc;
    }
    return 0;
}

int mlfs_get_block_stats(mlfs_t* fs, uint32_t* used_blocks, uint32_t* free_blocks)
{
    if(!fs || !used_blocks || !free_blocks)
        return -1;
    if(fs->bytes_per_block == 0 || fs->sb.total_blocks == 0)
        return -2;

    uint32_t used = 0;
    uint32_t free_count = 0;
    for(uint32_t block = 0; block < fs->sb.total_blocks; ++block) {
        int is_used = 0;
        int rc = mlfs_bitmap_get(fs, block, &is_used);
        if(rc != 0)
            return rc;
        if(is_used)
            ++used;
        else
            ++free_count;
    }

    *used_blocks = used;
    *free_blocks = free_count;
    return 0;
}

// ---- dir helpers ----
static int mlfs_dir_write_empty(const mlfs_t* fs, uint32_t first_block, uint32_t blocks)
{
    uint8_t* zero = (uint8_t*)calloc(1, fs->bytes_per_block);
    if(!zero)
        return -1;
    for(uint32_t i = 0; i < blocks; i++) {
        if(mlfs_write_block(fs, first_block + i, zero) != 0) {
            free(zero);
            return -1;
        }
    }
    free(zero);
    return 0;
}

// ---- PT R/W ----
int mlfs_read_mlpt(const mlfs_io_t* io, mlpt_t* out)
{
    if(!io || !out)
        return -1;  // Invalid parameters
    uint8_t sec[512];
    if(io->read(io->ctx, 0, 1, sec) != 0)
        return -1;
    mlfs_decode_mlpt(sec, out);
    if(out->magic != MLPT_MAGIC || out->major != MLPT_VERSION_MAJOR || out->minor != MLPT_VERSION_MINOR || out->patch != MLPT_VERSION_PATCH)
        return -2;
    return 0;
}

int mlfs_write_mlpt(const mlfs_io_t* io, const mlpt_t* pt)
{
    if(!io || !pt)
        return -1;  // Invalid parameters
    uint8_t sec[512];
    mlfs_encode_mlpt(sec, pt);
    return io->write(io->ctx, 0, 1, sec);
}

int mlfs_make_single_partition(const mlfs_io_t* io, uint32_t start_lba, uint32_t sectors_total, uint8_t log2_block_bytes)
{
    if(!io)
        return -1;  // NULL I/O context
    if(log2_block_bytes < 9 || log2_block_bytes > 16)
        return -99;
    uint32_t block_bytes = 1u << log2_block_bytes;
    if(block_bytes % io->sector_size)
        return -98;
    uint32_t spb = block_bytes / io->sector_size;
    mlpt_t   pt;
    memset(&pt, 0, sizeof(pt));
    pt.magic           = MLPT_MAGIC;
    pt.major           = MLPT_VERSION_MAJOR;
    pt.minor           = MLPT_VERSION_MINOR;
    pt.patch           = MLPT_VERSION_PATCH;
    pt.count           = 1;
    mlpt_entry_t* e    = &pt.entries[0];
    e->start_lba       = start_lba;
    e->type            = 1;
    e->log2_block_size = log2_block_bytes;
    e->block_count     = sectors_total / spb;
    strncpy(e->name, "MLFS0", sizeof(e->name) - 1);
    return mlfs_write_mlpt(io, &pt);
}

int mlfs_make_empty_partition_table(const mlfs_io_t* io)
{
    if(!io)
        return -1;  // NULL I/O context
    mlpt_t pt;
    memset(&pt, 0, sizeof(pt));
    pt.magic = MLPT_MAGIC;
    pt.major = MLPT_VERSION_MAJOR;
    pt.minor = MLPT_VERSION_MINOR;
    pt.patch = MLPT_VERSION_PATCH;
    pt.count = 0;  // No partitions initially
    return mlfs_write_mlpt(io, &pt);
}

int mlfs_add_partition(const mlfs_io_t* io, uint32_t start_lba, uint32_t block_count, uint8_t log2_block_size, const char* name)
{
    // Validate parameters
    if(!io)
        return -1;  // NULL I/O context
    if(start_lba == 0)
        return -100;  // LBA 0 is reserved for partition table
    if(block_count == 0)
        return -101;  // Zero-sized partition not allowed
    if(log2_block_size < 9 || log2_block_size > 16)
        return -99;  // Invalid block size
    if(!name)
        return -98;  // Invalid name
    if(strlen(name) == 0)
        return -102;  // Empty name not allowed

    // Read existing partition table
    mlpt_t pt;
    int    rc = mlfs_read_mlpt(io, &pt);
    if(rc != 0)
        return rc;

    // Check if we have space for another partition
    if(pt.count >= MLPT_MAX_PARTS)
        return -97;  // Too many partitions

    // Check for overlapping partitions
    uint32_t block_bytes = 1u << log2_block_size;
    if(block_bytes % io->sector_size)
        return -96;  // Block size not aligned to sector size
    uint32_t sectors_per_block = block_bytes / io->sector_size;
    uint32_t end_lba           = start_lba + (block_count * sectors_per_block) - 1;

    for(uint16_t i = 0; i < pt.count; i++) {
        mlpt_entry_t* existing                   = &pt.entries[i];
        uint32_t      existing_block_bytes       = 1u << existing->log2_block_size;
        uint32_t      existing_sectors_per_block = existing_block_bytes / io->sector_size;
        uint32_t      existing_end_lba           = existing->start_lba + (existing->block_count * existing_sectors_per_block) - 1;

        // Check for overlap
        if(start_lba <= existing_end_lba && end_lba >= existing->start_lba)
            return -95;  // Partition overlap
    }

    // Add the new partition
    mlpt_entry_t* e    = &pt.entries[pt.count];
    e->start_lba       = start_lba;
    e->block_count     = block_count;
    e->type            = 1;  // MLFS type
    e->log2_block_size = log2_block_size;
    strncpy(e->name, name, sizeof(e->name) - 1);
    e->name[sizeof(e->name) - 1] = '\0';  // Ensure null termination

    pt.count++;

    return mlfs_write_mlpt(io, &pt);
}

// ---- mkfs/mount ----
int mlfs_mkfs(const mlfs_io_t* io, uint16_t part_index, mlfs_t* out_fs)
{
    if(!io || !out_fs)
        return -1;  // Invalid parameters
    mlpt_t pt;
    int    rc = mlfs_read_mlpt(io, &pt);
    if(rc)
        return rc;
    if(part_index >= pt.count)
        return -3;
    mlpt_entry_t part = pt.entries[part_index];
    if(part.type != 1)
        return -4;
    memset(out_fs, 0, sizeof(*out_fs));
    out_fs->io           = *io;
    out_fs->part         = part;
    uint32_t block_bytes = 1u << part.log2_block_size;
    if(block_bytes % io->sector_size)
        return -5;
    out_fs->bytes_per_block = block_bytes;
    mlfs_superblock_t sb;
    memset(&sb, 0, sizeof(sb));
    sb.magic           = MLFS_MAGIC;
    sb.major           = MLFS_VERSION_MAJOR;
    sb.minor           = MLFS_VERSION_MINOR;
    sb.patch           = MLFS_VERSION_PATCH;
    sb.log2_block_size = part.log2_block_size;
    sb.total_blocks    = part.block_count;
    sb.bitmap_start    = 1;
    out_fs->sb         = sb;
    sb.bitmap_blocks =
        (out_fs->bytes_per_block ? ((sb.total_blocks + (out_fs->bytes_per_block * 8u) - 1) / (out_fs->bytes_per_block * 8u)) : 0);
    sb.root_dir_block  = sb.bitmap_start + sb.bitmap_blocks;
    sb.root_dir_blocks = 2;
    uint32_t uuid_temp[4];
    mlfs_fill_uuid(uuid_temp);
    memcpy(sb.uuid, uuid_temp, sizeof(sb.uuid));
    sb.checksum = 0;
    uint8_t sb_sec[512];
    mlfs_encode_superblock(sb_sec, &sb);
    sb.checksum = mlfs_cksum32(sb_sec, sizeof(sb_sec));
    out_fs->sb   = sb;
    uint8_t* blk = (uint8_t*)calloc(1, out_fs->bytes_per_block);
    if(!blk)
        return -6;
    mlfs_encode_superblock(blk, &sb);
    rc = mlfs_write_block(out_fs, 0, blk);
    if(rc) {
        free(blk);
        return rc;
    }
    memset(blk, 0, out_fs->bytes_per_block);
    for(uint32_t i = 0; i < sb.bitmap_blocks; i++) {
        rc = mlfs_write_block(out_fs, sb.bitmap_start + i, blk);
        if(rc) {
            free(blk);
            return rc;
        }
    }
    rc = mlfs_bitmap_mark_run(out_fs, 0, 1 + sb.bitmap_blocks, 1);
    if(rc) {
        free(blk);
        return rc;
    }
    rc = mlfs_bitmap_mark_run(out_fs, sb.root_dir_block, sb.root_dir_blocks, 1);
    if(rc) {
        free(blk);
        return rc;
    }
    rc = mlfs_dir_write_empty(out_fs, sb.root_dir_block, sb.root_dir_blocks);
    free(blk);
    return rc;
}

int mlfs_mount(const mlfs_io_t* io, uint16_t part_index, mlfs_t* out_fs)
{
    if(!io || !out_fs)
        return -1;  // Invalid parameters
    mlpt_t pt;
    int    rc = mlfs_read_mlpt(io, &pt);
    if(rc)
        return rc;
    if(part_index >= pt.count)
        return -3;
    mlpt_entry_t part = pt.entries[part_index];
    if(part.type != 1)
        return -4;
    memset(out_fs, 0, sizeof(*out_fs));
    out_fs->io           = *io;
    out_fs->part         = part;
    uint32_t block_bytes = 1u << part.log2_block_size;
    if(block_bytes % io->sector_size)
        return -5;
    out_fs->bytes_per_block = block_bytes;
    uint8_t tmp[512];
    rc = io->read(io->ctx, (uint64_t)part.start_lba, 1, tmp);
    if(rc)
        return rc;
    mlfs_superblock_t sb;
    mlfs_decode_superblock(tmp, &sb);
    if(sb.magic != MLFS_MAGIC || sb.major != MLFS_VERSION_MAJOR || sb.minor != MLFS_VERSION_MINOR || sb.patch != MLFS_VERSION_PATCH)
        return -10;
    uint32_t old = sb.checksum;
    tmp[45] = tmp[46] = tmp[47] = tmp[48] = 0;
    if(mlfs_cksum32(tmp, sizeof(tmp)) != old)
        return -11;
    if(sb.log2_block_size != part.log2_block_size)
        return -12;
    out_fs->sb = sb;
    return 0;
}

// ---- root-only file ops ----

int mlfs_alloc_run(mlfs_t* fs, uint32_t blocks_wanted, mlfs_extent_t* out_ext)
{
    uint32_t start_search = fs->sb.root_dir_block + fs->sb.root_dir_blocks;
    uint32_t start        = 0;
    int      rc           = mlfs_bitmap_find_run(fs, start_search, blocks_wanted, &start);
    if(rc)
        return rc;
    rc = mlfs_bitmap_mark_run(fs, start, blocks_wanted, 1);
    if(rc)
        return rc;
    out_ext->start  = start;
    out_ext->length = blocks_wanted;
    return 0;
}

int mlfs_create_empty_file(mlfs_t* fs, const char* name, uint32_t initial_blocks)
{
    if(!fs || !name)
        return -1;

    // Resolve path to find target directory and filename
    uint32_t target_dir_block, target_dir_blocks;
    char     filename[MLFS_MAX_NAME];
    int      rc = mlfs_resolve_path(fs, name, &target_dir_block, &target_dir_blocks, filename);
    if(rc != 0)
        return rc;  // Path resolution failed

    // Don't allow creating files with empty names (root directory case)
    if(strlen(filename) == 0)
        return -5;  // Invalid filename

    if(initial_blocks == 0)
        initial_blocks = 1;
    mlfs_extent_t ext;
    rc = mlfs_alloc_run(fs, initial_blocks, &ext);
    if(rc)
        return rc;
    uint8_t* zero = (uint8_t*)calloc(1, fs->bytes_per_block);
    if(!zero)
        return -1;
    for(uint32_t i = 0; i < ext.length; i++) {
        rc = mlfs_write_block(fs, ext.start + i, zero);
        if(rc) {
            free(zero);
            return rc;
        }
    }
    free(zero);
    return mlfs_dir_add_entry_to_dir(fs, target_dir_block, target_dir_blocks, filename, 0, ext, 0);
}

ssize_t mlfs_pwrite_file(mlfs_t* fs, const char* name, const void* src, size_t count, size_t offset)
{
    if(!fs || !name)
        return -1;

    // Resolve path to find target directory and filename
    uint32_t target_dir_block, target_dir_blocks;
    char     filename[MLFS_MAX_NAME];
    int      rc = mlfs_resolve_path(fs, name, &target_dir_block, &target_dir_blocks, filename);
    if(rc != 0)
        return rc;  // Path resolution failed

    // Don't allow writing to directories (empty filename)
    if(strlen(filename) == 0)
        return -5;  // Invalid filename

    mlfs_dentry_t de;
    uint32_t      blk_addr = 0, idx = 0;
    rc = mlfs_dir_lookup_in_dir(fs, target_dir_block, target_dir_blocks, filename, &de, &blk_addr, &idx);
    if(rc)
        return -1;
    if(de.extents_used == 0)
        return -2;
    mlfs_extent_t ext       = de.extents[0];
    size_t        max_bytes = (size_t)ext.length * fs->bytes_per_block;
    if(offset + count > max_bytes)
        count = (max_bytes > offset) ? (max_bytes - offset) : 0;
    if(!count)
        return 0;
    uint8_t* blk = (uint8_t*)malloc(fs->bytes_per_block);
    if(!blk)
        return -1;
    size_t written = 0, off = offset;
    while(written < count) {
        uint32_t rel    = (uint32_t)(off / fs->bytes_per_block);
        uint32_t within = (uint32_t)(off % fs->bytes_per_block);
        uint32_t bno    = ext.start + rel;
        size_t   tocpy  = fs->bytes_per_block - within;
        if(tocpy > count - written)
            tocpy = count - written;
        if(mlfs_read_block(fs, bno, blk) != 0) {
            free(blk);
            return -1;
        }
        memcpy(blk + within, (const uint8_t*)src + written, tocpy);
        if(mlfs_write_block(fs, bno, blk) != 0) {
            free(blk);
            return -1;
        }
        written += tocpy;
        off += tocpy;
    }
    free(blk);
    if(offset + written > de.size_bytes)
        de.size_bytes = (uint32_t)(offset + written);
    de.mtime           = mlfs_now_unix();
    mlfs_dentry_t* buf = (mlfs_dentry_t*)malloc(fs->bytes_per_block);
    if(!buf)
        return -1;
    if(mlfs_read_block(fs, blk_addr, buf) != 0) {
        free(buf);
        return -1;
    }
    mlfs_decode_dentry_block(buf, fs->bytes_per_block);
    buf[idx] = de;
    mlfs_encode_dentry_block(buf, fs->bytes_per_block);
    if(mlfs_write_block(fs, blk_addr, buf) != 0) {
        free(buf);
        return -1;
    }
    free(buf);
    return (ssize_t)written;
}

ssize_t mlfs_pread_file(mlfs_t* fs, const char* name, void* dst, size_t count, size_t offset)
{
    if(!fs || !name)
        return -1;

    // Resolve path to find target directory and filename
    uint32_t target_dir_block, target_dir_blocks;
    char     filename[MLFS_MAX_NAME];
    int      rc = mlfs_resolve_path(fs, name, &target_dir_block, &target_dir_blocks, filename);
    if(rc != 0)
        return rc;  // Path resolution failed

    // Don't allow reading directories (empty filename)
    if(strlen(filename) == 0)
        return -5;  // Invalid filename

    mlfs_dentry_t de;
    rc = mlfs_dir_lookup_in_dir(fs, target_dir_block, target_dir_blocks, filename, &de, NULL, NULL);
    if(rc)
        return -1;
    if(offset >= de.size_bytes)
        return 0;
    if(offset + count > de.size_bytes)
        count = de.size_bytes - offset;
    mlfs_extent_t ext = de.extents[0];
    uint8_t*      blk = (uint8_t*)malloc(fs->bytes_per_block);
    if(!blk)
        return -1;
    size_t readn = 0, off = offset;
    while(readn < count) {
        uint32_t rel    = (uint32_t)(off / fs->bytes_per_block);
        uint32_t within = (uint32_t)(off % fs->bytes_per_block);
        uint32_t bno    = ext.start + rel;
        size_t   tocpy  = fs->bytes_per_block - within;
        if(tocpy > count - readn)
            tocpy = count - readn;
        if(mlfs_read_block(fs, bno, blk) != 0) {
            free(blk);
            return -1;
        }
        memcpy((uint8_t*)dst + readn, blk + within, tocpy);
        readn += tocpy;
        off += tocpy;
    }
    free(blk);
    return (ssize_t)readn;
}

// ---- Directory operations ----

// ---- Path parsing utilities ----

// Split a path into components (e.g., "/dir1/dir2/file" -> ["dir1", "dir2", "file"])
// Returns number of components, or -1 on error
static int mlfs_split_path(const char* path, char components[][MLFS_MAX_NAME], int max_components)
{
    if(!path || !components || max_components <= 0)
        return -1;

    // Handle empty or root-only path
    if(strcmp(path, "") == 0 || strcmp(path, "/") == 0)
        return 0;

    int         count = 0;
    const char* start = path;

    // Skip leading slash
    if(*start == '/')
        start++;

    while(*start && count < max_components) {
        // Find end of current component
        const char* end = strchr(start, '/');
        size_t      len;

        if(end) {
            len = end - start;
        } else {
            len = strlen(start);
        }

        // Check component length
        if(len == 0) {
            // Empty component (double slash), skip it
            start = end + 1;
            continue;
        }

        if(len >= MLFS_MAX_NAME) {
            return -1;  // Component name too long
        }

        // Copy component
        memcpy(components[count], start, len);
        components[count][len] = '\0';
        count++;

        // Move to next component
        if(end) {
            start = end + 1;
        } else {
            break;
        }
    }

    return count;
}

// Resolve a path to find the target directory and filename
// Returns 0 on success, negative on error
// On success: *target_dir_block and *target_dir_blocks contain the directory where the file/dir should be
// *filename contains the final component name
static int mlfs_resolve_path(mlfs_t* fs, const char* path, uint32_t* target_dir_block, uint32_t* target_dir_blocks, char* filename)
{
    if(!fs || !path || !target_dir_block || !target_dir_blocks || !filename)
        return -1;

    char components[16][MLFS_MAX_NAME];  // Support up to 16 path levels
    int  num_components = mlfs_split_path(path, components, 16);

    if(num_components < 0)
        return -1;  // Invalid path

    if(num_components == 0) {
        // Root directory itself
        *target_dir_block  = fs->sb.root_dir_block;
        *target_dir_blocks = fs->sb.root_dir_blocks;
        strcpy(filename, "");
        return 0;
    }

    // Start at root directory
    uint32_t current_dir_block      = fs->sb.root_dir_block;
    uint32_t current_dir_num_blocks = fs->sb.root_dir_blocks;

    // Traverse all components except the last one
    for(int i = 0; i < num_components - 1; i++) {
        mlfs_dentry_t dir_entry;
        int           rc = mlfs_dir_lookup_in_dir(fs, current_dir_block, current_dir_num_blocks, components[i], &dir_entry, NULL, NULL);
        if(rc != 0)
            return -2;  // Directory component not found

        // Check if it's actually a directory
        if(!(dir_entry.flags & 1))
            return -3;  // Component is not a directory

        if(dir_entry.extents_used == 0)
            return -4;  // Empty directory extent

        // Move to this directory
        mlfs_extent_t ext      = dir_entry.extents[0];
        current_dir_block      = ext.start;
        current_dir_num_blocks = ext.length;
    }

    // Set output values
    *target_dir_block  = current_dir_block;
    *target_dir_blocks = current_dir_num_blocks;
    strcpy(filename, components[num_components - 1]);

    return 0;
}

static int mlfs_path_is_descendant(const char* parent_path, const char* child_path)
{
    char parent_components[16][MLFS_MAX_NAME];
    char child_components[16][MLFS_MAX_NAME];
    int  parent_count = mlfs_split_path(parent_path, parent_components, 16);
    int  child_count  = mlfs_split_path(child_path, child_components, 16);

    if(parent_count <= 0 || child_count <= parent_count)
        return 0;

    for(int i = 0; i < parent_count; i++) {
        if(strcmp(parent_components[i], child_components[i]) != 0)
            return 0;
    }

    return 1;
}

// Helper: generalized directory lookup (works on any directory)
static int mlfs_dir_lookup_in_dir(const mlfs_t* fs, uint32_t dir_first_block, uint32_t dir_num_blocks, const char* name, mlfs_dentry_t* out,
                                  uint32_t* out_block, uint32_t* out_index)
{
    const uint32_t per = fs->bytes_per_block / sizeof(mlfs_dentry_t);
    mlfs_dentry_t* buf = (mlfs_dentry_t*)malloc(fs->bytes_per_block);
    if(!buf)
        return -1;

    for(uint32_t blk = 0; blk < dir_num_blocks; ++blk) {
        if(mlfs_read_block(fs, dir_first_block + blk, buf) != 0) {
            free(buf);
            return -1;
        }
        mlfs_decode_dentry_block(buf, fs->bytes_per_block);
        for(uint32_t i = 0; i < per; i++) {
            if(buf[i].in_use && strncmp(buf[i].name, name, MLFS_MAX_NAME) == 0) {
                if(out)
                    *out = buf[i];
                if(out_block)
                    *out_block = dir_first_block + blk;
                if(out_index)
                    *out_index = i;
                free(buf);
                return 0;
            }
        }
    }
    free(buf);
    return 1;  // not found
}

// Helper: generalized directory add entry
static int mlfs_dir_add_entry_to_dir(const mlfs_t* fs, uint32_t dir_first_block, uint32_t dir_num_blocks, const char* name, int is_dir,
                                     mlfs_extent_t first_ext, uint32_t size_bytes)
{
    const uint32_t per = fs->bytes_per_block / sizeof(mlfs_dentry_t);
    mlfs_dentry_t* buf = (mlfs_dentry_t*)malloc(fs->bytes_per_block);
    if(!buf)
        return -1;

    for(uint32_t blk = 0; blk < dir_num_blocks; ++blk) {
        if(mlfs_read_block(fs, dir_first_block + blk, buf) != 0) {
            free(buf);
            return -1;
        }
        mlfs_decode_dentry_block(buf, fs->bytes_per_block);
        for(uint32_t i = 0; i < per; i++) {
            if(!buf[i].in_use) {
                memset(&buf[i], 0, sizeof(buf[i]));
                buf[i].in_use     = 1;
                buf[i].flags      = (uint8_t)(is_dir ? 1 : 2);  // bit0=dir, bit1=file
                buf[i].size_bytes = size_bytes;
                buf[i].ctime = buf[i].mtime = mlfs_now_unix();
                buf[i].extents_used         = 1;
                strncpy(buf[i].name, name, MLFS_MAX_NAME - 1);
                buf[i].name[MLFS_MAX_NAME - 1] = '\0';
                buf[i].extents[0]              = first_ext;
                mlfs_encode_dentry_block(buf, fs->bytes_per_block);
                int rcw                        = mlfs_write_block(fs, dir_first_block + blk, buf);
                free(buf);
                return rcw;
            }
        }
    }
    free(buf);
    return 1;  // no free slots
}

static int mlfs_dir_add_existing_entry_to_dir(const mlfs_t* fs, uint32_t dir_first_block, uint32_t dir_num_blocks, const mlfs_dentry_t* entry)
{
    const uint32_t per = fs->bytes_per_block / sizeof(mlfs_dentry_t);
    mlfs_dentry_t* buf = (mlfs_dentry_t*)malloc(fs->bytes_per_block);
    if(!buf)
        return -1;

    for(uint32_t blk = 0; blk < dir_num_blocks; ++blk) {
        if(mlfs_read_block(fs, dir_first_block + blk, buf) != 0) {
            free(buf);
            return -1;
        }
        mlfs_decode_dentry_block(buf, fs->bytes_per_block);
        for(uint32_t i = 0; i < per; i++) {
            if(!buf[i].in_use) {
                buf[i] = *entry;
                mlfs_encode_dentry_block(buf, fs->bytes_per_block);
                int rcw = mlfs_write_block(fs, dir_first_block + blk, buf);
                free(buf);
                return rcw;
            }
        }
    }

    free(buf);
    return 1;
}

static int mlfs_dir_write_entry_at(const mlfs_t* fs, uint32_t block_addr, uint32_t index, const mlfs_dentry_t* entry)
{
    const uint32_t per = fs->bytes_per_block / sizeof(mlfs_dentry_t);
    if(index >= per)
        return -1;

    mlfs_dentry_t* buf = (mlfs_dentry_t*)malloc(fs->bytes_per_block);
    if(!buf)
        return -1;

    if(mlfs_read_block(fs, block_addr, buf) != 0) {
        free(buf);
        return -1;
    }

    mlfs_decode_dentry_block(buf, fs->bytes_per_block);
    buf[index] = *entry;
    mlfs_encode_dentry_block(buf, fs->bytes_per_block);

    int rcw = mlfs_write_block(fs, block_addr, buf);
    free(buf);
    return rcw;
}

// Helper: remove directory entry
static int mlfs_dir_remove_entry_from_dir(const mlfs_t* fs, uint32_t dir_first_block, uint32_t dir_num_blocks, const char* name)
{
    mlfs_dentry_t entry;
    uint32_t      blk_addr, idx;
    int           rc = mlfs_dir_lookup_in_dir(fs, dir_first_block, dir_num_blocks, name, &entry, &blk_addr, &idx);
    if(rc)
        return rc;  // not found or error

    mlfs_dentry_t* buf = (mlfs_dentry_t*)malloc(fs->bytes_per_block);
    if(!buf)
        return -1;

    if(mlfs_read_block(fs, blk_addr, buf) != 0) {
        free(buf);
        return -1;
    }
    mlfs_decode_dentry_block(buf, fs->bytes_per_block);

    // Mark entry as not in use
    buf[idx].in_use = 0;
    memset(&buf[idx], 0, sizeof(buf[idx]));  // Clear the entry

    mlfs_encode_dentry_block(buf, fs->bytes_per_block);
    int rcw = mlfs_write_block(fs, blk_addr, buf);
    free(buf);
    return rcw;
}

// Helper: count entries in directory
static int mlfs_dir_count_entries_in_dir(const mlfs_t* fs, uint32_t dir_first_block, uint32_t dir_num_blocks, uint32_t* count_out)
{
    const uint32_t per = fs->bytes_per_block / sizeof(mlfs_dentry_t);
    mlfs_dentry_t* buf = (mlfs_dentry_t*)malloc(fs->bytes_per_block);
    if(!buf)
        return -1;

    uint32_t count = 0;
    for(uint32_t blk = 0; blk < dir_num_blocks; ++blk) {
        if(mlfs_read_block(fs, dir_first_block + blk, buf) != 0) {
            free(buf);
            return -1;
        }
        mlfs_decode_dentry_block(buf, fs->bytes_per_block);
        for(uint32_t i = 0; i < per; i++) {
            if(buf[i].in_use) {
                count++;
            }
        }
    }
    free(buf);
    *count_out = count;
    return 0;
}

// Create a new directory
int mlfs_create_directory(mlfs_t* fs, const char* path, uint32_t initial_blocks)
{
    if(!fs || !path)
        return -1;

    // Resolve path to find target directory and dirname
    uint32_t target_dir_block, target_dir_blocks;
    char     dirname[MLFS_MAX_NAME];
    int      rc = mlfs_resolve_path(fs, path, &target_dir_block, &target_dir_blocks, dirname);
    if(rc != 0)
        return rc;  // Path resolution failed

    // Don't allow creating directories with empty names (root directory case)
    if(strlen(dirname) == 0)
        return -5;  // Invalid directory name

    if(initial_blocks == 0)
        initial_blocks = 1;

    // Allocate blocks for the new directory
    mlfs_extent_t ext;
    rc = mlfs_alloc_run(fs, initial_blocks, &ext);
    if(rc)
        return rc;

    // Initialize directory blocks to empty
    uint8_t* zero = (uint8_t*)calloc(1, fs->bytes_per_block);
    if(!zero)
        return -1;

    for(uint32_t i = 0; i < ext.length; i++) {
        rc = mlfs_write_block(fs, ext.start + i, zero);
        if(rc) {
            free(zero);
            return rc;
        }
    }
    free(zero);

    // Add directory entry to target directory
    return mlfs_dir_add_entry_to_dir(fs, target_dir_block, target_dir_blocks, dirname, 1, ext, 0);
}

// Delete a directory (must be empty)
int mlfs_delete_directory(mlfs_t* fs, const char* path)
{
    if(!fs || !path)
        return -1;

    // Resolve path to find target directory and dirname
    uint32_t target_dir_block, target_dir_blocks;
    char     dirname[MLFS_MAX_NAME];
    int      rc = mlfs_resolve_path(fs, path, &target_dir_block, &target_dir_blocks, dirname);
    if(rc != 0)
        return rc;  // Path resolution failed

    // Don't allow deleting root directory (empty dirname)
    if(strlen(dirname) == 0)
        return -5;  // Invalid directory name

    // Look up the directory
    mlfs_dentry_t dir_entry;
    rc = mlfs_dir_lookup_in_dir(fs, target_dir_block, target_dir_blocks, dirname, &dir_entry, NULL, NULL);
    if(rc)
        return rc;  // not found or error

    // Check if it's actually a directory
    if(!(dir_entry.flags & 1))
        return -2;  // not a directory

    // Check if directory is empty
    uint32_t count;
    if(dir_entry.extents_used > 0) {
        mlfs_extent_t ext = dir_entry.extents[0];
        rc                = mlfs_dir_count_entries_in_dir(fs, ext.start, ext.length, &count);
        if(rc)
            return rc;
        if(count > 0)
            return -3;  // directory not empty
    }

    // Free the directory blocks
    if(dir_entry.extents_used > 0) {
        mlfs_extent_t ext = dir_entry.extents[0];
        rc                = mlfs_bitmap_mark_run(fs, ext.start, ext.length, 0);
        if(rc)
            return rc;
    }

    // Remove directory entry from parent directory
    return mlfs_dir_remove_entry_from_dir(fs, target_dir_block, target_dir_blocks, dirname);
}

// Delete a file
int mlfs_delete_file(mlfs_t* fs, const char* path)
{
    if(!fs || !path)
        return -1;

    // Resolve path to find target directory and filename
    uint32_t target_dir_block, target_dir_blocks;
    char     filename[MLFS_MAX_NAME];
    int      rc = mlfs_resolve_path(fs, path, &target_dir_block, &target_dir_blocks, filename);
    if(rc != 0)
        return rc;  // Path resolution failed

    // Don't allow deleting directories (empty filename)
    if(strlen(filename) == 0)
        return -5;  // Invalid filename

    // Look up the file
    mlfs_dentry_t file_entry;
    rc = mlfs_dir_lookup_in_dir(fs, target_dir_block, target_dir_blocks, filename, &file_entry, NULL, NULL);
    if(rc)
        return rc;  // not found or error

    // Check if it's actually a file
    if(!(file_entry.flags & 2))
        return -2;  // not a file

    // Free the file blocks
    if(file_entry.extents_used > 0) {
        mlfs_extent_t ext = file_entry.extents[0];
        rc                = mlfs_bitmap_mark_run(fs, ext.start, ext.length, 0);
        if(rc)
            return rc;
    }

    // Remove file entry from parent directory
    return mlfs_dir_remove_entry_from_dir(fs, target_dir_block, target_dir_blocks, filename);
}

int mlfs_rename(mlfs_t* fs, const char* old_path, const char* new_path)
{
    if(!fs || !old_path || !new_path)
        return -1;

    uint32_t old_dir_block, old_dir_blocks;
    char     old_name[MLFS_MAX_NAME];
    int      rc = mlfs_resolve_path(fs, old_path, &old_dir_block, &old_dir_blocks, old_name);
    if(rc != 0)
        return rc;
    if(strlen(old_name) == 0)
        return -5;

    uint32_t old_entry_block = 0, old_entry_index = 0;
    mlfs_dentry_t old_entry;
    rc = mlfs_dir_lookup_in_dir(fs, old_dir_block, old_dir_blocks, old_name, &old_entry, &old_entry_block, &old_entry_index);
    if(rc)
        return rc;

    uint32_t new_dir_block, new_dir_blocks;
    char     new_name[MLFS_MAX_NAME];
    rc = mlfs_resolve_path(fs, new_path, &new_dir_block, &new_dir_blocks, new_name);
    if(rc != 0)
        return rc;
    if(strlen(new_name) == 0)
        return -5;

    if((old_entry.flags & 1) && mlfs_path_is_descendant(old_path, new_path))
        return -6;

    if(old_dir_block == new_dir_block && old_dir_blocks == new_dir_blocks && strcmp(old_name, new_name) == 0)
        return 0;

    mlfs_dentry_t existing;
    rc = mlfs_dir_lookup_in_dir(fs, new_dir_block, new_dir_blocks, new_name, &existing, NULL, NULL);
    if(rc == 0)
        return -7;
    if(rc < 0)
        return rc;

    mlfs_dentry_t renamed = old_entry;
    size_t new_name_len = strlen(new_name);
    memset(renamed.name, 0, sizeof(renamed.name));
    memcpy(renamed.name, new_name, new_name_len + 1);
    renamed.mtime = mlfs_now_unix();

    if(old_dir_block == new_dir_block && old_dir_blocks == new_dir_blocks)
        return mlfs_dir_write_entry_at(fs, old_entry_block, old_entry_index, &renamed);

    rc = mlfs_dir_add_existing_entry_to_dir(fs, new_dir_block, new_dir_blocks, &renamed);
    if(rc)
        return rc;

    rc = mlfs_dir_remove_entry_from_dir(fs, old_dir_block, old_dir_blocks, old_name);
    if(rc)
        mlfs_dir_remove_entry_from_dir(fs, new_dir_block, new_dir_blocks, new_name);

    return rc;
}

// Read directory contents
int mlfs_read_directory(mlfs_t* fs, const char* path, mlfs_dentry_t* entries, uint32_t max_entries, uint32_t* count_out)
{
    if(!fs || !path || !entries || !count_out)
        return -1;

    uint32_t dir_first_block, dir_num_blocks;

    // Handle root directory specially
    if(strcmp(path, "/") == 0 || strcmp(path, "") == 0) {
        dir_first_block = fs->sb.root_dir_block;
        dir_num_blocks  = fs->sb.root_dir_blocks;
    } else {
        // Resolve path to find target directory and dirname
        uint32_t target_dir_block, target_dir_blocks;
        char     dirname[MLFS_MAX_NAME];
        int      rc = mlfs_resolve_path(fs, path, &target_dir_block, &target_dir_blocks, dirname);
        if(rc != 0)
            return rc;  // Path resolution failed

        // If dirname is empty, we're reading the resolved directory itself
        if(strlen(dirname) == 0) {
            dir_first_block = target_dir_block;
            dir_num_blocks  = target_dir_blocks;
        } else {
            // Look up the directory
            mlfs_dentry_t dir_entry;
            rc = mlfs_dir_lookup_in_dir(fs, target_dir_block, target_dir_blocks, dirname, &dir_entry, NULL, NULL);
            if(rc)
                return rc;  // not found or error

            // Check if it's actually a directory
            if(!(dir_entry.flags & 1))
                return -2;  // not a directory

            if(dir_entry.extents_used == 0) {
                *count_out = 0;
                return 0;  // empty directory
            }

            mlfs_extent_t ext = dir_entry.extents[0];
            dir_first_block   = ext.start;
            dir_num_blocks    = ext.length;
        }
    }

    // Read directory contents
    const uint32_t per = fs->bytes_per_block / sizeof(mlfs_dentry_t);
    mlfs_dentry_t* buf = (mlfs_dentry_t*)malloc(fs->bytes_per_block);
    if(!buf)
        return -1;

    uint32_t found = 0;
    for(uint32_t blk = 0; blk < dir_num_blocks && found < max_entries; ++blk) {
        if(mlfs_read_block(fs, dir_first_block + blk, buf) != 0) {
            free(buf);
            return -1;
        }
        mlfs_decode_dentry_block(buf, fs->bytes_per_block);
        for(uint32_t i = 0; i < per && found < max_entries; i++) {
            if(buf[i].in_use) {
                entries[found] = buf[i];
                found++;
            }
        }
    }

    free(buf);
    *count_out = found;
    return 0;
}
