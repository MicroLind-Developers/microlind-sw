#ifndef MLFS_TYPES_H
#define MLFS_TYPES_H

typedef struct {
    void *ctx; // user context (driver or simulator)
    mlfs_read_fn read;
    mlfs_write_fn write;
    uint32_t sector_size; // disk sector bytes (e.g., 512)
} mlfs_io_t;

typedef struct __attribute__((packed)) {
    uint32_t start_lba;      // absolute disk LBA where partition starts (in disk sectors)
    uint32_t block_count;    // number of MLFS blocks in this partition
    uint8_t type;            // 1=MLFS
    uint8_t log2_block_size; // 9..16 encodes 512..65536 bytes
    char name[14];           // zero-terminated if shorter
} mlpt_entry_t;

typedef struct __attribute__((packed)) {
    uint32_t magic; // MLPT_MAGIC
    uint8_t major;  // MLPT_VERSION_MAJOR
    uint8_t minor;  // MLPT_VERSION_MINOR
    uint8_t patch;  // MLPT_VERSION_PATCH
    uint16_t count; // how many valid entries
    mlpt_entry_t entries[MLPT_MAX_PARTS];
    uint8_t reserved[512 - 4 - 1 - 1 - 1 - 2 - (sizeof(mlpt_entry_t) * MLPT_MAX_PARTS)];
} mlpt_t;

typedef struct __attribute__((packed)) {
    uint32_t start;  // block index relative to partition start (block 0 = superblock)
    uint32_t length; // number of blocks in run
} mlfs_extent_t;

typedef struct __attribute__((packed)) {
    uint8_t in_use;        // 0=free slot, 1=occupied
    uint8_t flags;         // bit0=dir, bit1=file, bit2=hidden
    uint32_t size_bytes;   // logical file size
    uint32_t mtime;        // unix epoch seconds
    uint32_t ctime;        // creation time
    uint8_t extents_used;  // number of extents in the inline table
    uint8_t extents_total; // total extents incl. indirect; 0 if unknown
    char name[MLFS_MAX_NAME];
    mlfs_extent_t extents[4]; // inline; more via extent-index blocks if needed
    uint32_t first_indirect;  // 0 if none; else block index of extent-index array
    uint8_t reserved[4];
} mlfs_dentry_t; // 128 bytes exactly

typedef struct __attribute__((packed)) {
    uint32_t magic;          // MLFS_MAGIC
    uint8_t major;           // MLFS_VERSION_MAJOR
    uint8_t minor;           // MLFS_VERSION_MINOR
    uint8_t patch;           // MLFS_VERSION_PATCH
    uint8_t log2_block_size; // must match MLPT entry
    uint8_t reserved0;

    uint32_t total_blocks;  // blocks in partition
    uint32_t bitmap_start;  // first block of bitmap (usually 1)
    uint32_t bitmap_blocks; // how many blocks for bitmap

    uint32_t root_dir_block;  // first block of root dir
    uint32_t root_dir_blocks; // blocks allocated to root dir

    uint32_t uuid[4];  // simple GUID-ish
    uint32_t checksum; // additive checksum of header with this field as 0

    uint8_t reserved[512 - 4 - 1 - 1 - 1 - 1 - 1 - 4 - 4 - 4 - 4 - 4 - 16 - 4];
} mlfs_superblock_t; // fits in 512 bytes

// In-memory mount state
typedef struct {
    mlfs_io_t io;
    mlpt_entry_t part;
    mlfs_superblock_t sb;
    uint32_t bytes_per_block;
} mlfs_t;

// ---------------------------------------------------------------------------------------------
// Old stuff down here
// ---------------------------------------------------------------------------------------------

// // 16 bytes for partition header
// struct mlfs_partition_header_t
// {
//     char name[8];               // 8 bytes for name
//     uint32_t start_sector;      // 4 bytes for start sector
//     uint8_t block_size;        // 1 byte for block size (max 256)
//     uint16_t size;              // 2 bytes for size (max 65535 blocks) (this
//     will affect the block table size) uint8_t flags;              // 1 byte
//     for flags
// };

// // 392 bytes for disc header
// struct mlfs_disc_header_t
// {
//     char magic[4];                              // "M", "L", "F", "S"
//     uint8_t major_version;                      // 1 byte for major version
//     uint8_t minor_version;                      // 1 byte for minor version
//     uint8_t no_of_partitions;                   // 1 byte for no of
//     partitions uint8_t spare_byte;                         // 1 byte for
//     spare byte mlfs_partition_header_t partitions[24];     // 16 bytes * 24 =
//     384 bytes for partitions uint8_t spare_bytes[100]; // 1 byte for spare
//     byte
// };

// // 9 bytes for boot record
// struct mlfs_boot_record_t
// {
//     uint8_t type;                // 1 byte for type
//     uint32_t boot_start;        // 4 bytes for boot start
//     uint32_t boot_size;         // 4 bytes for boot size
// };

// 8192 bytes for block table = 65536 bits
// each bit represents a block
// 1 means the block is used, 0 means the block is free
// 65536 bits for block size of 1 sector / block => max 65536 * 512 bytes =
// 33554432 bytes = 32MB partition 65536 bits for block size of 2 sectors /
// block => max 2 * 65536 * 512 bytes = 67108864 bytes = 64MB partition 65536
// bits for block size of 16 sectors / block => max 16 * 65536 * 512 bytes =
// 536870912 bytes = 512MB partition 65536 bits for block size of 256 sectors /
// block => max 256 * 65536 * 512 bytes = 8589934592 bytes = 8GB partition

#endif // MLFS_TYPES_H