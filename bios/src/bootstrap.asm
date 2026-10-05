; Read-only MLFS 1.1.0 partition-0 bootstrap. Fixed 512-byte sector buffer.
; Accept the host formatter's ordered superblock/bitmap/root/data layout.
    include "../include/module.inc"
    include "../../mlfs/lib/include/mlfs_types.inc"

BL_NAME       equ 0               ; Root filename pointer
BL_KIND       equ 2               ; Requested MLP kind (word)
BL_SHIFT      equ 4               ; log2(sectors per block), 0..7
BL_PART       equ 5               ; Partition start LBA
BL_BLOCKS     equ 9               ; Partition block count
BL_MIN        equ 13              ; First permitted block of next extent
BL_LBA        equ 17              ; Next sector to read
BL_END        equ 21              ; Exclusive end of current extent
BL_FILE_SIZE  equ 25              ; File bytes (word, bounded by RAM capacity)
BL_HEADER     equ 27              ; Private MLP header, survives buffer refill
BL_LEFT       equ 47              ; Payload bytes remaining
BL_SUM        equ 49              ; Saved checksum
BL_STATUS     equ 53              ; Failure category
BL_STATE      equ $D940
BL_STATE_SIZE equ 54
    ifgt BL_STATE+BL_STATE_SIZE-$DC00
        error "Bootstrap state overlaps the BIOS stack"
    endc

; X = root filename (optional leading slash), B = MLP kind (0 or 1).
; C clear/A=0/X=absolute entry on success; C set/A=MLP_ERR_* on failure.
; Clobbers D,W,X,Y,U,CC. No writes to disk. Not reentrant.
BIOS_LOAD_MODULE:
    ldu #BL_STATE
    clra
    std BL_KIND,u
    lda #MLP_ERR_HEADER
    sta BL_STATUS,u
    cmpb #1
    lbhi BL_FAIL
    lda ,x
    cmpa #'/'
    bne BL_SAVE_NAME
    leax 1,x
BL_SAVE_NAME:
    stx BL_NAME,u
    lda #MLP_ERR_METADATA
    sta BL_STATUS,u
    ldq #0
    jsr BL_READ
    lbcs BL_FAIL
    ldx #STORAGE_BUFFER_START
    ldy #BL_PT_MAGIC
    jsr BL_IDENTIFY
    lbcs BL_FAIL
    ldd STORAGE_BUFFER_START+MLPT_COUNT
    beq BL_BAD_TABLE
    cmpd #MLPT_MAX_PARTS
    bhi BL_BAD_TABLE
    ldx #STORAGE_BUFFER_START+MLPT_ENTRIES
    lda MLPT_ENTRY_TYPE,x
    cmpa #1
    bne BL_BAD_TABLE
    lda MLPT_ENTRY_LOG2_BLOCK_SIZE,x
    suba #9
    cmpa #7
    bhi BL_BAD_TABLE
    sta BL_SHIFT,u
    ldq MLPT_ENTRY_START_LBA,x
    bita #$F0
    bne BL_BAD_TABLE
    stq BL_PART,u
    tstd
    bne BL_PART_NONZERO
    cmpw #0
    beq BL_BAD_TABLE
BL_PART_NONZERO:
    ldq MLPT_ENTRY_BLOCK_COUNT,x
    stq BL_BLOCKS,u
    tstd
    bne BL_BLOCKS_NONZERO
    cmpw #0
    beq BL_BAD_TABLE
BL_BLOCKS_NONZERO:
    jsr BL_TO_LBA
    bcs BL_BAD_TABLE
    cmpd #$1000                 ; Exclusive end may equal the LBA28 limit.
    bhi BL_BAD_TABLE
    blo BL_PART_OK
    cmpw #0
    bne BL_BAD_TABLE
BL_PART_OK:
    ldq BL_PART,u
    jsr BL_READ
    lbcs BL_FAIL
    bra BL_SUPERBLOCK
BL_BAD_TABLE:
    lbra BL_FAIL
BL_SUPERBLOCK:
    ldx #STORAGE_BUFFER_START
    ldy #BL_FS_MAGIC
    jsr BL_IDENTIFY
    lbcs BL_FAIL
    lda STORAGE_BUFFER_START+MLFS_SB_LOG2_BLOCK_SIZE
    suba #9
    cmpa BL_SHIFT,u
    lbne BL_FAIL
    ldq STORAGE_BUFFER_START+MLFS_SB_TOTAL_BLOCKS
    cmpd BL_BLOCKS,u
    lbne BL_FAIL
    cmpw BL_BLOCKS+2,u
    lbne BL_FAIL
    ldq STORAGE_BUFFER_START+MLFS_SB_CHECKSUM
    stq BL_SUM,u
    ldq #0
    stq STORAGE_BUFFER_START+MLFS_SB_CHECKSUM
    ldx #STORAGE_BUFFER_START
    ldy #512
    jsr MLFS_CKSUM32
    cmpd BL_SUM,u
    lbne BL_FAIL
    cmpw BL_SUM+2,u
    lbne BL_FAIL
    ldq #1
    stq BL_MIN,u
    ldx #STORAGE_BUFFER_START+MLFS_SB_BITMAP_START
    jsr BL_RANGE
    lbcs BL_FAIL
    ldx #STORAGE_BUFFER_START+MLFS_SB_ROOT_DIR_BLOCK
    jsr BL_RANGE
    lbcs BL_FAIL
BL_DIRECTORY:
    ldq BL_LBA,u
    cmpd BL_END,u
    bne BL_DIR_READ
    cmpw BL_END+2,u
    bne BL_DIR_READ
    lda #MLP_ERR_NOT_FOUND
    lbra BL_RETURN_ERROR
BL_DIR_READ:
    jsr BL_NEXT
    lbcs BL_FAIL
    ldx #STORAGE_BUFFER_START
BL_DENTRY:
    lda MLFS_DENTRY_IN_USE,x
    cmpa #1
    bne BL_SKIP_ENTRY
    pshs x
    leax MLFS_DENTRY_NAME,x
    ldy BL_NAME,u
    ldb #MLFS_MAX_NAME
BL_MATCH:
    lda ,y+
    cmpa ,x+
    bne BL_NO_MATCH
    tsta
    beq BL_FOUND
    decb
    bne BL_MATCH
BL_NO_MATCH:
    puls x
BL_SKIP_ENTRY:
    leax MLFS_DENTRY_SIZE,x
    cmpx #STORAGE_BUFFER_START+512
    bne BL_DENTRY
    bra BL_DIRECTORY
BL_FOUND:
    puls x
    lda #MLP_ERR_LAYOUT
    sta BL_STATUS,u
    lda MLFS_DENTRY_FLAGS,x
    anda #3
    cmpa #MLFS_DENTRY_FLAG_FILE
    lbne BL_FAIL
    lda MLFS_DENTRY_EXTENTS_USED,x
    cmpa #1
    lbne BL_FAIL
    lda MLFS_DENTRY_EXTENTS_TOTAL,x
    cmpa #1                     ; 0 means unknown, accepted by the host API.
    lbhi BL_FAIL
    ldq MLFS_DENTRY_FIRST_INDIRECT,x
    tstd
    lbne BL_FAIL
    cmpw #0
    lbne BL_FAIL
    ldd MLFS_DENTRY_SIZE_BYTES,x
    lbne BL_FAIL
    ldd MLFS_DENTRY_SIZE_BYTES+2,x
    cmpd #MLP_HEADER_SIZE+1
    lblo BL_FAIL
    cmpd #$8000+MLP_HEADER_SIZE
    lbhi BL_FAIL
    std BL_FILE_SIZE,u
    leax MLFS_DENTRY_EXTENTS,x
    jsr BL_RANGE
    lbcs BL_FAIL
    ; File bytes must fit its extent. Limit reads to logical file sectors.
    ldd BL_FILE_SIZE,u
    addd #511
    lsrd
    lsrd
    lsrd
    lsrd
    lsrd
    lsrd
    lsrd
    lsrd
    lsrd
    tfr d,w
    clrd
    addw BL_LBA+2,u
    adcb BL_LBA+1,u
    adca BL_LBA,u
    cmpd BL_END,u
    lbhi BL_FAIL
    blo BL_FILE_FITS
    cmpw BL_END+2,u
    lbhi BL_FAIL
BL_FILE_FITS:
    stq BL_END,u
    jsr BL_NEXT
    lbcs BL_FAIL
    ldx #STORAGE_BUFFER_START
    leay BL_HEADER,u
    ldw #MLP_HEADER_SIZE
    tfm x+,y+
    lda #MLP_ERR_HEADER
    sta BL_STATUS,u
    ldd BL_HEADER,u
    cmpd #$4D4C
    lbne BL_FAIL
    ldd BL_HEADER+2,u
    cmpd #$5031
    lbne BL_FAIL
    ldd BL_HEADER+MLP_ABI,u
    cmpd #BIOS_MODULE_API_VERSION
    lbne BL_FAIL
    ldd BL_HEADER+MLP_KIND,u
    cmpd BL_KIND,u
    lbne BL_FAIL
    ldx #MLP_FILESYSTEM_BASE
    ldy #MLP_FILESYSTEM_LIMIT-MLP_FILESYSTEM_BASE
    tstd
    beq BL_CHECK_RAM
    ldx #MLP_APPLICATION_BASE
    ldy #MLP_APPLICATION_LIMIT-MLP_APPLICATION_BASE
BL_CHECK_RAM:
    cmpx BL_HEADER+MLP_LOAD,u
    lbne BL_FAIL
    cmpy BL_HEADER+MLP_MEMORY_SIZE,u
    lblo BL_FAIL
    ldd BL_HEADER+MLP_PAYLOAD_SIZE,u
    lbeq BL_FAIL
    cmpd BL_HEADER+MLP_MEMORY_SIZE,u
    lbhi BL_FAIL
    std BL_LEFT,u
    addd #MLP_HEADER_SIZE
    cmpd BL_FILE_SIZE,u
    lbne BL_FAIL
    ldd BL_HEADER+MLP_ENTRY,u
    cmpd BL_LEFT,u
    lbhs BL_FAIL
    addd BL_HEADER+MLP_LOAD,u
    std BL_HEADER+MLP_ENTRY,u
    ; Copy initialized bytes, preserving the destination across CF calls.
    ldy #STORAGE_BUFFER_START+MLP_HEADER_SIZE
    ldw #512-MLP_HEADER_SIZE
BL_COPY:
    lda ,y+
    sta ,x+
    ldd BL_LEFT,u
    subd #1
    std BL_LEFT,u
    beq BL_CHECK_PAYLOAD
    decw
    bne BL_COPY
    pshs x
    jsr BL_NEXT
    puls x
    lbcs BL_FAIL
    ldy #STORAGE_BUFFER_START
    ldw #512
    bra BL_COPY
BL_CHECK_PAYLOAD:
    lda #MLP_ERR_CHECKSUM
    sta BL_STATUS,u
    ldx BL_HEADER+MLP_LOAD,u
    ldy BL_HEADER+MLP_PAYLOAD_SIZE,u
    jsr MLFS_CKSUM32
    cmpd BL_HEADER+MLP_CHECKSUM,u
    bne BL_FAIL
    cmpw BL_HEADER+MLP_CHECKSUM+2,u
    bne BL_FAIL
    ldd BL_HEADER+MLP_MEMORY_SIZE,u
    subd BL_HEADER+MLP_PAYLOAD_SIZE,u
    beq BL_LOADED
    tfr d,y
BL_ZERO:
    clr ,x+
    leay -1,y
    bne BL_ZERO
BL_LOADED:
    ldx BL_HEADER+MLP_ENTRY,u
    clra
    andcc #$FE
    rts
BL_FAIL:
    lda BL_STATUS,u
BL_RETURN_ERROR:
    orcc #1
    rts

; Launch a validated module; Y is the optional runtime filesystem API pointer.
; Restore DP, Y, U and caller IRQ masks on return. Modules must balance S and
; restore peripheral/IRQ-hook state. Returns the same loader status in A/C.
BIOS_RUN_MODULE:
    pshs cc,dp,y,u
    jsr BIOS_LOAD_MODULE
    bcs BL_RUN_FAILED
    ldy 2,s
    ldx #BIOS_MODULE_API_BASE
    jsr [BL_STATE+BL_HEADER+MLP_ENTRY]
    puls cc,dp,y,u
    clra
    andcc #$FE
    rts
BL_RUN_FAILED:
    puls cc,dp,y,u
    orcc #1
    rts

; Seven-byte magic/version check shared by MLPT and MLFS.
BL_IDENTIFY:
    ldb #7
BL_IDENTIFY_BYTE:
    lda ,x+
    cmpa ,y+
    bne BL_HELPER_BAD
    decb
    bne BL_IDENTIFY_BYTE
    andcc #$FE
    rts
BL_PT_MAGIC:
    fcc "MLPT"
    fcb 1,1,0
BL_FS_MAGIC:
    fcc "MLFS"
    fcb 1,1,0

; Q = relative block. Return Q = absolute LBA; detect all 32-bit overflow.
BL_TO_LBA:
    leas -4,s
    stq ,s
    ldb BL_SHIFT,u
    beq BL_SHIFT_DONE
BL_SHIFT_LOOP:
    asl 3,s
    rol 2,s
    rol 1,s
    rol 0,s
    bcs BL_SHIFT_BAD
    decb
    bne BL_SHIFT_LOOP
BL_SHIFT_DONE:
    ldq ,s
    leas 4,s
    addw BL_PART+2,u
    adcb BL_PART+1,u
    adca BL_PART,u
    rts
BL_SHIFT_BAD:
    leas 4,s
BL_HELPER_BAD:
    orcc #1
    rts

; X = contiguous big-endian block start/count, BL_MIN = minimum start block.
; Check nonzero length, checked end <= partition blocks; update BL_MIN to end.
; Return absolute start/end in BL_LBA/BL_END. Preserve X and buffer contents.
BL_RANGE:
    ldq ,x
    cmpd BL_MIN,u
    blo BL_HELPER_BAD
    bhi BL_RANGE_START_OK
    cmpw BL_MIN+2,u
    blo BL_HELPER_BAD
BL_RANGE_START_OK:
    ldd 4,x
    bne BL_RANGE_LENGTH_OK
    ldd 6,x
    beq BL_HELPER_BAD
BL_RANGE_LENGTH_OK:
    ldq ,x
    addw 6,x
    adcb 5,x
    adca 4,x
    bcs BL_HELPER_BAD
    cmpd BL_BLOCKS,u
    bhi BL_HELPER_BAD
    blo BL_RANGE_END_OK
    cmpw BL_BLOCKS+2,u
    bhi BL_HELPER_BAD
BL_RANGE_END_OK:
    stq BL_MIN,u
    jsr BL_TO_LBA
    bcs BL_HELPER_BAD
    stq BL_END,u
    ldq ,x
    jsr BL_TO_LBA
    bcs BL_HELPER_BAD
    stq BL_LBA,u
    andcc #$FE
    rts

; BL_LBA is always inside the validated current extent at callers.
BL_NEXT:
    ldq BL_LBA,u
    jsr BL_READ
    bcs BL_NEXT_DONE
    ldq BL_LBA,u
    addw #1
    adcb #0
    adca #0
    stq BL_LBA,u
    andcc #$FE
BL_NEXT_DONE:
    rts
BL_READ:
    jsr CF_READ_SECTOR_BUFFER
    bcc BL_READ_DONE
    lda #MLP_ERR_IO
    sta BL_STATUS,u
BL_READ_DONE:
    rts
