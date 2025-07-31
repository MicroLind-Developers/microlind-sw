#ifndef MLFS_TYPES_H
#define MLFS_TYPES_H

// 16 bytes for partition header
struct mlfs_partition_header_t
{
    char name[8];               // 8 bytes for name
    uint32_t start_sector;      // 4 bytes for start sector
    uint8_t block_size;        // 1 byte for block size (max 256)
    uint16_t size;              // 2 bytes for size (max 65535 blocks) (this will affect the block table size)
    uint8_t flags;              // 1 byte for flags
};

// 392 bytes for disc header
struct mlfs_disc_header_t
{
    char magic[4];                              // "M", "L", "F", "S"
    uint8_t major_version;                      // 1 byte for major version    
    uint8_t minor_version;                      // 1 byte for minor version
    uint8_t no_of_partitions;                   // 1 byte for no of partitions
    uint8_t spare_byte;                         // 1 byte for spare byte
    mlfs_partition_header_t partitions[24];     // 16 bytes * 24 = 384 bytes for partitions
    uint8_t spare_bytes[100];                         // 1 byte for spare byte
};

// 9 bytes for boot record
struct mlfs_boot_record_t
{
    uint8_t type;                // 1 byte for type
    uint32_t boot_start;        // 4 bytes for boot start
    uint32_t boot_size;         // 4 bytes for boot size
};

// 8192 bytes for block table = 65536 bits
// each bit represents a block  
// 1 means the block is used, 0 means the block is free
// 65536 bits for block size of 1 sector / block => max 65536 * 512 bytes = 33554432 bytes = 32MB partition
// 65536 bits for block size of 2 sectors / block => max 2 * 65536 * 512 bytes = 67108864 bytes = 64MB partition
// 65536 bits for block size of 16 sectors / block => max 16 * 65536 * 512 bytes = 536870912 bytes = 512MB partition
// 65536 bits for block size of 256 sectors / block => max 256 * 65536 * 512 bytes = 8589934592 bytes = 8GB partition



#endif // MLFS_TYPES_H