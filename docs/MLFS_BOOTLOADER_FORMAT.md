# MLFS Bootloader Format Notes

This document describes the MLFS on-disk structures and the minimum read-only
algorithm needed for a BIOS bootloader to find and load MLOS from an MLFS
partition.

The source of truth for the current format is:

- `mlfs/lib/include/mlfs.h`
- `mlfs/lib/include/mlfs_types.h`
- `mlfs/lib/include/mlfs_types.inc`
- `mlfs/lib/src/mlfs.c`

## Bootloader Goal

The BIOS bootloader should do the smallest useful MLFS operation:

1. Read sector 0.
2. Parse the MLFS partition table.
3. Select an MLFS partition.
4. Read the partition superblock.
5. Locate a boot file in the root directory.
6. Read its extent data into RAM.
7. Jump to the loaded MLOS entry point.

It does not need to support allocation, deletion, timestamps, indirect extents,
or general directory traversal in the first version.

Recommended first boot file convention:

```text
/mlos.bin
```

Alternative later conventions:

```text
/boot/mlos.bin
/boot/mlos.ihex
/boot/kernel.bin
```

For the first BIOS bootloader, prefer a raw binary file with a known load
address. Intel HEX or S-record loading can be added later, but raw binary keeps
the boot path much smaller.

## Endianness

MLFS uses explicit big-endian encoding for all multi-byte on-disk fields.

This matches the HD6309/6809 native byte order and keeps the BIOS/MLOS
bootloader path simple. Linux and host tools must convert at the disk boundary
with big-endian helpers.

For example, `MLFS_MAGIC` is defined as:

```c
#define MLFS_MAGIC 0x4D4C4653u /* 'MLFS' */
```

On disk, the byte sequence is:

```text
4D 4C 46 53
 M  L  F  S
```

Likewise, `MLPT_MAGIC` is:

```c
#define MLPT_MAGIC 0x4D4C5054u /* 'MLPT' */
```

On disk:

```text
4D 4C 50 54
 M  L  P  T
```

Bootloader code can compare these byte sequences directly or load them as
native big-endian values.

## Disk Layout

MLFS uses disk sectors for physical I/O and MLFS blocks for filesystem
allocation.

The current I/O layer assumes 512-byte disk sectors:

```c
mlfs_io_t.sector_size = 512
```

Sector 0 contains the MLFS partition table:

```text
disk LBA 0: MLPT partition table
```

Each MLFS partition starts at an absolute disk LBA from the partition table:

```text
partition_start_lba + 0: superblock
partition_start_lba + N: filesystem blocks
```

MLFS block size is configurable:

```text
block_bytes = 1 << log2_block_size
```

Valid values:

```text
log2_block_size 9..16 = 512..65536 bytes
```

The number of disk sectors per MLFS block is:

```text
sectors_per_block = block_bytes / 512
```

To read relative MLFS block `B`:

```text
absolute_lba = partition_start_lba + (B * sectors_per_block)
sector_count = sectors_per_block
```

## Partition Table: `mlpt_t`

The partition table is exactly 512 bytes at disk LBA 0.

Header layout:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | magic, big-endian `MLPT_MAGIC` |
| 4 | 1 | major |
| 5 | 1 | minor |
| 6 | 1 | patch |
| 7 | 2 | count, big-endian |
| 9 | 384 | partition entries, 16 * 24 bytes |
| 393 | 119 | reserved |

Expected version:

```text
major = 0
minor = 1
patch = 0
```

### Partition Entry: `mlpt_entry_t`

Each entry is 24 bytes.

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | start_lba, big-endian absolute disk LBA |
| 4 | 4 | block_count, big-endian MLFS block count |
| 8 | 1 | type, `1 = MLFS` |
| 9 | 1 | log2_block_size |
| 10 | 14 | name, NUL-terminated if shorter |

For boot, select the first entry where:

```text
type == 1
log2_block_size >= 9
log2_block_size <= 16
block_count != 0
```

Later, the BIOS can select by name, for example `boot` or `system`.

## Superblock: `mlfs_superblock_t`

The superblock is stored at relative MLFS block 0 of the selected partition.
Since it fits in 512 bytes, the bootloader only needs to read the first disk
sector at `partition_start_lba` to validate it.

Layout:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | magic, big-endian `MLFS_MAGIC` |
| 4 | 1 | major |
| 5 | 1 | minor |
| 6 | 1 | patch |
| 7 | 1 | log2_block_size |
| 8 | 1 | reserved0 |
| 9 | 4 | total_blocks, big-endian |
| 13 | 4 | bitmap_start, big-endian |
| 17 | 4 | bitmap_blocks, big-endian |
| 21 | 4 | root_dir_block, big-endian |
| 25 | 4 | root_dir_blocks, big-endian |
| 29 | 16 | uuid |
| 45 | 4 | checksum, big-endian |
| 49 | 463 | reserved |

Expected version:

```text
major = 0
minor = 1
patch = 0
```

Format defaults from `mlfs_mkfs()`:

```text
bitmap_start    = 1
root_dir_block  = bitmap_start + bitmap_blocks
root_dir_blocks = 2
```

### Checksum

The superblock checksum is a 32-bit additive checksum over all 512 superblock
bytes with the checksum field treated as zero.

Current C implementation:

```c
static uint32_t mlfs_cksum32(const void* p, size_t n)
{
    const uint8_t* b = (const uint8_t*)p;
    uint32_t s = 0;
    for(size_t i = 0; i < n; i++)
        s += b[i];
    return s;
}
```

For an initial bootloader, checksum validation is recommended but can be made a
separate step after magic/version/block-size validation works.

## Directory Entry: `mlfs_dentry_t`

Directories are stored as arrays of fixed 128-byte directory entries. A
512-byte MLFS block holds four directory entries. Larger block sizes hold:

```text
dentries_per_block = block_bytes / 128
```

Directory entry layout:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | in_use, `0 = free`, `1 = occupied` |
| 1 | 1 | flags |
| 2 | 4 | size_bytes, big-endian |
| 6 | 4 | mtime, big-endian Unix seconds |
| 10 | 4 | ctime, big-endian Unix seconds |
| 14 | 1 | extents_used |
| 15 | 1 | extents_total |
| 16 | 48 | name |
| 64 | 32 | inline extents, 4 * 8 bytes |
| 96 | 4 | first_indirect, big-endian |
| 100 | 28 | reserved |

Flags:

```text
bit 0 = directory
bit 1 = file
bit 2 = hidden
```

For bootloader use, accept only entries where:

```text
in_use == 1
(flags & 0x02) != 0
name == "mlos.bin"
extents_used >= 1
```

The bootloader can ignore:

- `mtime`
- `ctime`
- `extents_total`
- `first_indirect`
- hidden flag

## Extent: `mlfs_extent_t`

An extent is 8 bytes:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | start, big-endian relative MLFS block |
| 4 | 4 | length, big-endian block count |

The current simple C file path primarily uses the first extent:

```c
mlfs_extent_t ext = de.extents[0];
```

For the first bootloader, require the MLOS file to be single-extent:

```text
extents_used == 1
first_indirect == 0
```

This avoids needing indirect extent support in BIOS.

## Minimal Boot Read Algorithm

The following is the recommended first implementation.

### 1. Read MLPT

Read disk LBA 0 into a 512-byte buffer.

Validate:

```text
bytes[0..3] == 4D 4C 50 54
major == 0
minor == 1
patch == 0
count <= 16
```

### 2. Select Partition

Loop through `count` partition entries at offset `9 + index * 24`.

Choose the first MLFS entry:

```text
type == 1
log2_block_size in 9..16
block_count > 0
```

Save:

```text
partition_start_lba
partition_block_count
log2_block_size
block_bytes
sectors_per_block
```

### 3. Read Superblock

Read one sector from `partition_start_lba`.

Validate:

```text
bytes[0..3] == 4D 4C 46 53
version == 0.1.0
superblock.log2_block_size == partition.log2_block_size
total_blocks <= partition_block_count
root_dir_blocks > 0
```

Optional:

```text
validate checksum
```

Save:

```text
root_dir_block
root_dir_blocks
```

### 4. Search Root Directory

For each block in the root directory:

```text
for i = 0; i < root_dir_blocks; i++:
    read_mlfs_block(root_dir_block + i)
    scan block in 128-byte dentry steps
```

For each dentry:

```text
if in_use != 1: continue
if (flags & 0x02) == 0: continue
if name != "mlos.bin": continue
if extents_used != 1: fail unsupported
if first_indirect != 0: fail unsupported
found
```

Save:

```text
file_size_bytes
extent_start
extent_length
```

### 5. Load File Data

For each block in the file extent:

```text
for b = 0; b < extent_length; b++:
    read_mlfs_block(extent_start + b)
    copy to load_address
```

Stop copying after `file_size_bytes`; the last block may be partially used.

Recommended first load target:

```text
MLOS_ORIGIN = $8000
```

This matches the current MLOS skeleton in `mlos/include/mlos.inc`.

### 6. Jump to MLOS

After loading:

```asm
jmp MLOS_ORIGIN
```

Before jumping, decide whether BIOS owns the stack or whether MLOS will reset it.
The current MLOS skeleton sets its own stack:

```asm
lds #MLOS_STACK_TOP
```

## Required BIOS Primitives

The bootloader needs only a small storage API:

```text
cf_read_sector(lba32, count16, dst)
```

Recommended internal helper:

```text
mlfs_read_block(rel_block32, dst)
```

Where:

```text
absolute_lba = partition_start_lba + rel_block * sectors_per_block
```

For the first version, restrict block size to 512 bytes or 1024 bytes if that
simplifies buffering. Full MLFS supports up to 64 KB blocks, but a BIOS
bootloader does not need to support every possible filesystem immediately.

## Suggested Boot Partition Format

For simplest BIOS code:

```text
sector size      = 512 bytes
MLFS block size  = 512 bytes, log2 = 9
partition name   = boot
boot filename    = mlos.bin
file extents     = 1
load address     = $8000
entry address    = $8000
```

Using 512-byte MLFS blocks means:

```text
sectors_per_block = 1
```

That removes block-to-sector aggregation from the first bootloader.

## Future Extensions

After the first boot path works:

- select partition by name instead of first MLFS partition
- support `/boot/mlos.bin`
- support multiple inline extents
- support indirect extents
- support Intel HEX or S-record boot files
- add a boot metadata file with load address, entry point, and checksum
- add fallback boot filenames
- add a BIOS error code displayed on serial

## Format Rule

The on-disk format is independent of host CPU byte order. All multi-byte fields
are big-endian. C tools and Linux code must not write raw host structs directly
without encoding them first.
