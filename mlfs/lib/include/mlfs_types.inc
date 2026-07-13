; -----------------------------------------------------------------
; MLFS Types and Constants for 6309 Assembler
; This file defines structure offsets and constants from mlfs_types.h
; -----------------------------------------------------------------

; -----------------------------------------------------------------
; Constants
; -----------------------------------------------------------------
MLPT_MAGIC             equ $4D4C5054  ; 'MLPT'
MLPT_VERSION_MAJOR      equ 1
MLPT_VERSION_MINOR      equ 1
MLPT_VERSION_PATCH      equ 0

MLFS_MAGIC              equ $4D4C4653  ; 'MLFS'
MLFS_VERSION_MAJOR       equ 1
MLFS_VERSION_MINOR       equ 1
MLFS_VERSION_PATCH      equ 0

MLFS_MAX_NAME           equ 48
MLPT_MAX_PARTS          equ 16

; -----------------------------------------------------------------
; mlfs_io_t structure (8 bytes)
; -----------------------------------------------------------------
MLFS_IO_CTX             equ 0         ; void* ctx (2 bytes)
MLFS_IO_READ            equ 2         ; mlfs_read_fn read (2 bytes)
MLFS_IO_WRITE           equ 4         ; mlfs_write_fn write (2 bytes)
MLFS_IO_SECTOR_SIZE     equ 6         ; uint32_t sector_size (2 bytes, low word)
MLFS_IO_SIZE            equ 8

; -----------------------------------------------------------------
; mlpt_entry_t structure (packed, 24 bytes)
; -----------------------------------------------------------------
MLPT_ENTRY_START_LBA    equ 0         ; uint32_t start_lba (4 bytes)
MLPT_ENTRY_BLOCK_COUNT  equ 4         ; uint32_t block_count (4 bytes)
MLPT_ENTRY_TYPE         equ 8         ; uint8_t type (1 byte)
MLPT_ENTRY_LOG2_BLOCK_SIZE equ 9      ; uint8_t log2_block_size (1 byte)
MLPT_ENTRY_NAME         equ 10        ; char name[14] (14 bytes)
MLPT_ENTRY_SIZE         equ 24

; -----------------------------------------------------------------
; mlpt_t structure (512 bytes)
; -----------------------------------------------------------------
MLPT_MAGIC_FIELD        equ 0         ; uint32_t magic (4 bytes)
MLPT_MAJOR              equ 4         ; uint8_t major (1 byte)
MLPT_MINOR              equ 5         ; uint8_t minor (1 byte)
MLPT_PATCH              equ 6         ; uint8_t patch (1 byte)
MLPT_COUNT              equ 7         ; uint16_t count (2 bytes)
MLPT_ENTRIES            equ 9         ; mlpt_entry_t entries[16] (16 * 24 = 384 bytes)
MLPT_RESERVED           equ 393        ; uint8_t reserved[...] (rest of 512 bytes)
MLPT_SIZE               equ 512

; -----------------------------------------------------------------
; mlfs_extent_t structure (packed, 8 bytes)
; -----------------------------------------------------------------
MLFS_EXTENT_START       equ 0         ; uint32_t start (4 bytes)
MLFS_EXTENT_LENGTH      equ 4         ; uint32_t length (4 bytes)
MLFS_EXTENT_SIZE        equ 8

; -----------------------------------------------------------------
; mlfs_dentry_t structure (packed, 128 bytes)
; -----------------------------------------------------------------
MLFS_DENTRY_IN_USE      equ 0         ; uint8_t in_use (1 byte)
MLFS_DENTRY_FLAGS       equ 1         ; uint8_t flags (1 byte)
MLFS_DENTRY_SIZE_BYTES  equ 2         ; uint32_t size_bytes (4 bytes)
MLFS_DENTRY_MTIME       equ 6         ; uint32_t mtime (4 bytes)
MLFS_DENTRY_CTIME       equ 10        ; uint32_t ctime (4 bytes)
MLFS_DENTRY_EXTENTS_USED equ 14      ; uint8_t extents_used (1 byte)
MLFS_DENTRY_EXTENTS_TOTAL equ 15     ; uint8_t extents_total (1 byte)
MLFS_DENTRY_NAME        equ 16       ; char name[48] (48 bytes)
MLFS_DENTRY_EXTENTS     equ 64       ; mlfs_extent_t extents[4] (4 * 8 = 32 bytes)
MLFS_DENTRY_FIRST_INDIRECT equ 96    ; uint32_t first_indirect (4 bytes)
MLFS_DENTRY_RESERVED    equ 100       ; uint8_t reserved[28] (28 bytes)
MLFS_DENTRY_SIZE        equ 128

; Dentry flags
MLFS_DENTRY_FLAG_DIR    equ $01       ; bit0 = directory
MLFS_DENTRY_FLAG_FILE   equ $02       ; bit1 = file
MLFS_DENTRY_FLAG_HIDDEN equ $04       ; bit2 = hidden

; -----------------------------------------------------------------
; mlfs_superblock_t structure (packed, 512 bytes)
; -----------------------------------------------------------------
MLFS_SB_MAGIC           equ 0         ; uint32_t magic (4 bytes)
MLFS_SB_MAJOR           equ 4         ; uint8_t major (1 byte)
MLFS_SB_MINOR           equ 5         ; uint8_t minor (1 byte)
MLFS_SB_PATCH           equ 6         ; uint8_t patch (1 byte)
MLFS_SB_LOG2_BLOCK_SIZE equ 7        ; uint8_t log2_block_size (1 byte)
MLFS_SB_RESERVED0        equ 8        ; uint8_t reserved0 (1 byte)
MLFS_SB_TOTAL_BLOCKS     equ 9        ; uint32_t total_blocks (4 bytes)
MLFS_SB_BITMAP_START     equ 13      ; uint32_t bitmap_start (4 bytes)
MLFS_SB_BITMAP_BLOCKS    equ 17      ; uint32_t bitmap_blocks (4 bytes)
MLFS_SB_ROOT_DIR_BLOCK   equ 21      ; uint32_t root_dir_block (4 bytes)
MLFS_SB_ROOT_DIR_BLOCKS  equ 25      ; uint32_t root_dir_blocks (4 bytes)
MLFS_SB_UUID             equ 29      ; uint32_t uuid[4] (16 bytes)
MLFS_SB_CHECKSUM         equ 45      ; uint32_t checksum (4 bytes)
MLFS_SB_RESERVED         equ 49       ; uint8_t reserved[...] (rest of 512 bytes)
MLFS_SB_SIZE             equ 512

; -----------------------------------------------------------------
; mlfs_t structure (in-memory mount state)
; -----------------------------------------------------------------
MLFS_T_IO               equ 0         ; mlfs_io_t io (8 bytes)
MLFS_T_PART             equ 8         ; mlpt_entry_t part (24 bytes)
MLFS_T_SB                equ 32       ; mlfs_superblock_t sb (512 bytes)
MLFS_T_BYTES_PER_BLOCK   equ 544      ; uint32_t bytes_per_block (4 bytes)
MLFS_T_SIZE              equ 548

; -----------------------------------------------------------------
; Helper macros for structure access
; -----------------------------------------------------------------

; Example usage:
;   ldx fs_ptr
;   ldd MLFS_T_BYTES_PER_BLOCK,x  ; Load bytes_per_block field

; For nested structures:
;   ldx fs_ptr
;   ldy MLFS_T_IO + MLFS_IO_SECTOR_SIZE,x  ; Load io.sector_size
