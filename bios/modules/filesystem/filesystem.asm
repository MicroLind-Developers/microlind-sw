; MLFS 1.1.0 runtime extension, using fixed sector buffers and inline extents.
    include "../../include/module.inc"
    include "../../include/filesystem.inc"
    include "../../include/memory.inc"
    include "../../../mlfs/lib/include/mlfs_types.inc"

    org MLP_FILESYSTEM_BASE
    jmp FS_START
    org FS_API_BASE
    fcc "FSR1"
    fdb FS_API_VERSION,FS_API_COUNT
    jmp FS_MOUNT
    jmp FS_STAT
    jmp FS_LIST
    jmp FS_READ
    jmp FS_STATS
    jmp FS_WRITE
    jmp FS_CREATE
    jmp FS_UNLINK
    jmp FS_MKDIR
    jmp FS_RMDIR
    jmp FS_RENAME

; Module-private state. BIOS buffers and application memory are never borrowed
; by the services. The console alone owns the BIOS serial buffer while active.
FS_STATE       equ $B600
F_READY        equ FS_STATE
F_MOUNTED      equ FS_STATE+1
F_SHIFT        equ FS_STATE+2
F_PART_INDEX   equ FS_STATE+3
F_CF_READ      equ FS_STATE+4
F_PUTS         equ FS_STATE+6
F_PUTC         equ FS_STATE+8
F_GETC         equ FS_STATE+10
F_PART         equ FS_STATE+12
F_BLOCKS       equ FS_STATE+16
F_BITMAP       equ FS_STATE+20       ; Relative bitmap block start/count
F_ROOT         equ FS_STATE+28       ; Relative root block start/count
F_DATA_MIN     equ FS_STATE+36
F_BITMAP_LBA   equ FS_STATE+40
F_BITMAP_END   equ FS_STATE+44
F_ROOT_LBA     equ FS_STATE+48
F_ROOT_END     equ FS_STATE+52
F_REQUEST      equ FS_STATE+56
F_PATH         equ FS_STATE+58
F_PATH_LIMIT   equ FS_STATE+60
F_DEPTH        equ FS_STATE+62
F_DIR_LBA      equ FS_STATE+64
F_DIR_END      equ FS_STATE+68
F_CURRENT      equ FS_STATE+72
F_END          equ FS_STATE+76
F_TEMP         equ FS_STATE+80
F_TEMP2        equ FS_STATE+84
F_CHECKSUM     equ FS_STATE+88
F_FILE_SIZE    equ FS_STATE+92
F_SECTOR_OFF   equ FS_STATE+96
F_DEST         equ FS_STATE+98
F_LEFT         equ FS_STATE+100
F_DONE         equ FS_STATE+102
F_CURSOR       equ FS_STATE+104
F_SLOT         equ FS_STATE+108
F_USED         equ FS_STATE+110
F_BITS         equ FS_STATE+114
F_BYTE         equ FS_STATE+118
F_STACK_BASE   equ FS_STATE+120
F_CF_WRITE     equ FS_STATE+122
F_BIOS_API     equ FS_STATE+124
FS_CON_REQUEST equ $B700
FS_BUFFER      equ $B800
FS_MAP_BUFFER  equ $BA00
FS_DENTRY      equ $BC00
FS_NAME        equ $BC80
FS_SAVED_ENTRY equ $BD00
FS_LINE        equ $BE00
FS_LINE_LIMIT  equ FS_LINE+128
FS_MEMORY_END  equ $C000

; X=BIOS descriptor; Y=0 opens console, nonzero initializes and returns.
; Preserve the BIOS context. Reloading clears the module's entire private state.
; -------------------------------------------------------
;  Bind BIOS services, mount partition 0, and optionally open the console.
; -------------------------------------------------------
; input:            X=BIOS MBR1 descriptor; Y=0 for console, nonzero to initialize only
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; module service
;                   pointers and mount state initialized
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_START:
    pshs x,y,u
    stx F_BIOS_API
    clr F_READY
    clr F_MOUNTED
    ldd ,x
    cmpd #$4D42
    lbne FS_BAD_ABI
    ldd 2,x
    cmpd #$5231
    lbne FS_BAD_ABI
    ldd 4,x
    cmpd #BIOS_MODULE_API_VERSION
    lbne FS_BAD_ABI
    ldd 6,x
    cmpd #6
    lblo FS_BAD_ABI
    leau BIOS_MODULE_CF_READ-BIOS_MODULE_API_BASE,x
    stu F_CF_READ
    leau BIOS_MODULE_CF_WRITE-BIOS_MODULE_API_BASE,x
    stu F_CF_WRITE
    leau BIOS_MODULE_SERIAL_PRINT-BIOS_MODULE_API_BASE,x
    stu F_PUTS
    leau BIOS_MODULE_SERIAL_PUTC-BIOS_MODULE_API_BASE,x
    stu F_PUTC
    leau BIOS_MODULE_SERIAL_GETC-BIOS_MODULE_API_BASE,x
    stu F_GETC
    inc F_READY
    clrb
    jsr FS_MOUNT
    ldy 2,s                         ; Saved entry mode.
    bne FS_START_RETURN
    jsr FS_CONSOLE
FS_START_RETURN:
    puls x,y,u,pc
FS_BAD_ABI:
    ldd #FS_EABI
    orcc #1
    puls x,y,u,pc

; -------------------------------------------------------
;  Validate and mount one MLPT/MLFS partition; failed remounts clear the mount.
; -------------------------------------------------------
; input:            B=partition index 0..15; initialized BIOS service pointers
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; F_MOUNTED=1 only
;                   on success
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_MOUNT:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    clr F_MOUNTED                   ; A failed remount invalidates old state.
    tst F_READY
    lbeq FS_API_ABI
    cmpb #MLPT_MAX_PARTS
    lbhs FS_API_INVALID
    stb F_PART_INDEX
    ldq #0
    jsr F_READ_SECTOR
    lbcs FS_API_RETURN
    ldx #FS_BUFFER
    ldy #F_PT_ID
    jsr F_IDENTIFY
    lbcs FS_API_RETURN
    ldd FS_BUFFER+MLPT_COUNT
    beq F_MOUNT_BAD
    cmpd #MLPT_MAX_PARTS
    bhi F_MOUNT_BAD
    clra
    ldb F_PART_INDEX
    cmpd FS_BUFFER+MLPT_COUNT
    bhs F_MOUNT_BAD
    lda #MLPT_ENTRY_SIZE
    mul
    ldx #FS_BUFFER+MLPT_ENTRIES
    leax d,x
    lda MLPT_ENTRY_TYPE,x
    cmpa #1
    bne F_MOUNT_BAD
    lda MLPT_ENTRY_LOG2_BLOCK_SIZE,x
    suba #9
    cmpa #7
    bhi F_MOUNT_BAD
    sta F_SHIFT
    ldq MLPT_ENTRY_START_LBA,x
    bita #$F0
    bne F_MOUNT_BAD
    stq F_PART
    jsr F_Q_ZERO
    beq F_MOUNT_BAD
    ldq MLPT_ENTRY_BLOCK_COUNT,x
    stq F_BLOCKS
    jsr F_Q_ZERO
    beq F_MOUNT_BAD
    jsr F_BLOCK_LBA
    bcs F_MOUNT_BAD
    cmpd #$1000
    bhi F_MOUNT_BAD
    blo F_MOUNT_PART_OK
    cmpw #0
    bne F_MOUNT_BAD
F_MOUNT_PART_OK:
    ldq F_PART
    jsr F_READ_SECTOR
    lbcs FS_API_RETURN
    bra F_MOUNT_SB
F_MOUNT_BAD:
    lbra FS_API_CORRUPT
F_MOUNT_SB:
    ldx #FS_BUFFER
    ldy #F_FS_ID
    jsr F_IDENTIFY
    lbcs FS_API_RETURN
    lda FS_BUFFER+MLFS_SB_LOG2_BLOCK_SIZE
    suba #9
    cmpa F_SHIFT
    bne F_MOUNT_BAD
    ldq FS_BUFFER+MLFS_SB_TOTAL_BLOCKS
    cmpd F_BLOCKS
    bne F_MOUNT_BAD
    cmpw F_BLOCKS+2
    bne F_MOUNT_BAD
    ldq FS_BUFFER+MLFS_SB_CHECKSUM
    stq F_CHECKSUM
    ldq #0
    stq FS_BUFFER+MLFS_SB_CHECKSUM
    jsr F_SUM_SECTOR
    cmpd F_CHECKSUM
    bne F_MOUNT_BAD
    cmpw F_CHECKSUM+2
    bne F_MOUNT_BAD
    ldx #FS_BUFFER+MLFS_SB_BITMAP_START
    ldy #F_BITMAP
    ldw #16
    tfm x+,y+                       ; Bitmap and root extent descriptors.
    ldq #1
    stq F_TEMP2
    ldx #F_BITMAP
    jsr F_RANGE
    lbcs FS_API_CORRUPT
    ldq F_CURRENT
    stq F_BITMAP_LBA
    ldq F_END
    stq F_BITMAP_END
    ldx #F_ROOT
    jsr F_RANGE
    lbcs FS_API_CORRUPT
    ldq F_TEMP2
    stq F_DATA_MIN
    ldq F_CURRENT
    stq F_ROOT_LBA
    ldq F_END
    stq F_ROOT_END
    ; Bitmap capacity must cover all partition blocks. Compare sector counts:
    ; ceil(blocks/4096) <= bitmap sectors. All arithmetic is checked/bounded.
    ldq F_BLOCKS
    addw #4095
    adcb #0
    adca #0
    stq F_TEMP
    ldb #12
    jsr F_SHIFT_RIGHT
    ldq F_BITMAP_END
    subw F_BITMAP_LBA+2
    sbcb F_BITMAP_LBA+1
    sbca F_BITMAP_LBA
    cmpd F_TEMP
    lblo FS_API_CORRUPT
    bhi F_MOUNT_OK
    cmpw F_TEMP+2
    lblo FS_API_CORRUPT
F_MOUNT_OK:
    inc F_MOUNTED
    lbra FS_API_OK

; -------------------------------------------------------
;  Resolve a path and copy its raw 128-byte directory entry.
; -------------------------------------------------------
; input:            X=FsRequest; path=NUL-terminated name; buffer/count span at least 128 bytes
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; request.done=128
;                   on success
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_STAT:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    jsr F_REQUEST_CHECK
    lbcs FS_API_RETURN
    jsr F_ENTRY_BUFFER_CHECK
    lbcs FS_API_RETURN
    jsr F_LOOKUP
    lbcs FS_API_RETURN
    jsr F_COPY_ENTRY
    ldx F_REQUEST
    ldd #MLFS_DENTRY_SIZE
    std FS_REQ_DONE,x
    lbra FS_API_OK

; -------------------------------------------------------
;  Return the next occupied directory slot, skipping empty slots.
; -------------------------------------------------------
; input:            X=FsRequest; path=directory; buffer/count span at least 128 bytes;
;                   offset=slot cursor
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; request.done=1 for
;                   an entry, 0 at EOF; offset=next slot
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_LIST:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    jsr F_REQUEST_CHECK
    lbcs FS_API_RETURN
    jsr F_ENTRY_BUFFER_CHECK
    lbcs FS_API_RETURN
    jsr F_LOOKUP
    lbcs FS_API_RETURN
    jsr F_DIRECTORY
    lbcs FS_API_RETURN
    ldx F_REQUEST
    ldq FS_REQ_OFFSET,x
    stq F_CURSOR
    tfr f,a
    anda #3
    sta F_SLOT
    ldq F_CURSOR
    stq F_TEMP
    ldb #2
    jsr F_SHIFT_RIGHT
    ldq F_TEMP
    addw F_DIR_LBA+2
    adcb F_DIR_LBA+1
    adca F_DIR_LBA
    lbcs FS_API_RANGE
    stq F_CURRENT
F_LIST_SECTOR:
    ldq F_CURRENT
    cmpd F_DIR_END
    bhi F_LIST_END
    blo F_LIST_READ
    cmpw F_DIR_END+2
    bhs F_LIST_END
F_LIST_READ:
    jsr F_READ_SECTOR
    lbcs FS_API_RETURN
F_LIST_SLOT:
    clra
    ldb F_SLOT
    lsld
    lsld
    lsld
    lsld
    lsld
    lsld
    lsld
    ldx #FS_BUFFER
    leax d,x
    ldq F_CURSOR
    addw #1
    adcb #0
    adca #0
    stq F_CURSOR
    lda MLFS_DENTRY_IN_USE,x
    beq F_LIST_SKIP
    cmpa #1
    lbne FS_API_CORRUPT
    jsr F_SAVE_ENTRY
    jsr F_VALIDATE_ENTRY
    lbcs FS_API_RETURN
    jsr F_COPY_ENTRY
    ldx F_REQUEST
    ldq F_CURSOR
    stq FS_REQ_OFFSET,x
    ldd #1
    std FS_REQ_DONE,x
    lbra FS_API_OK
F_LIST_SKIP:
    inc F_SLOT
    lda F_SLOT
    cmpa #4
    blo F_LIST_SLOT
    clr F_SLOT
    jsr F_ADVANCE
    bra F_LIST_SECTOR
F_LIST_END:
    ldx F_REQUEST
    ldq F_CURSOR
    stq FS_REQ_OFFSET,x
    lbra FS_API_OK

; -------------------------------------------------------
;  Read bytes from a file, capping the transfer at EOF.
; -------------------------------------------------------
; input:            X=FsRequest; path=file; buffer=destination; count=bytes; offset=32-bit byte
;                   position
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; request.done=bytes
;                   read, including partial reads; offset unchanged
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_READ:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    jsr F_REQUEST_CHECK
    lbcs FS_API_RETURN
    jsr F_BUFFER_CHECK
    lbcs FS_API_RETURN
    jsr F_LOOKUP
    lbcs FS_API_RETURN
    lda FS_DENTRY+MLFS_DENTRY_FLAGS
    bita #MLFS_DENTRY_FLAG_DIR
    lbne FS_API_ISDIR
    ldx F_REQUEST
    ldq FS_REQ_OFFSET,x
    cmpd FS_DENTRY+MLFS_DENTRY_SIZE_BYTES
    lbhi FS_API_OK
    blo F_READ_POSITION
    cmpw FS_DENTRY+MLFS_DENTRY_SIZE_BYTES+2
    lbhs FS_API_OK
F_READ_POSITION:
    stq F_TEMP
    ldd FS_REQ_OFFSET+2,x
    andd #511
    std F_SECTOR_OFF
    ldd FS_REQ_BUFFER,x
    std F_DEST
    ldd FS_REQ_COUNT,x
    std F_LEFT
    clr F_DONE
    clr F_DONE+1
    ; Cap the transfer at EOF, retaining the full 32-bit file offset.
    ldq FS_DENTRY+MLFS_DENTRY_SIZE_BYTES
    subw FS_REQ_OFFSET+2,x
    sbcb FS_REQ_OFFSET+1,x
    sbca FS_REQ_OFFSET,x
    tstd
    bne F_READ_COUNT_SET
    cmpw F_LEFT
    bhs F_READ_COUNT_SET
    stw F_LEFT
F_READ_COUNT_SET:
    ldd F_LEFT
    lbeq FS_API_OK
    ldb #9
    jsr F_SHIFT_RIGHT
    ldq F_TEMP
    addw F_CURRENT+2
    adcb F_CURRENT+1
    adca F_CURRENT
    stq F_CURRENT
F_READ_NEXT:
    ldq F_CURRENT
    jsr F_READ_SECTOR
    bcs F_READ_ERROR
    ldd #512
    subd F_SECTOR_OFF
    cmpd F_LEFT
    bls F_READ_CHUNK
    ldd F_LEFT
F_READ_CHUNK:
    tfr d,w
    pshs d
    ldd F_SECTOR_OFF
    ldx #FS_BUFFER
    leax d,x
    ldy F_DEST
    tfm x+,y+
    sty F_DEST
    puls d
    addd F_DONE
    std F_DONE
    ldx F_REQUEST
    std FS_REQ_DONE,x
    ldd #512
    subd F_SECTOR_OFF
    cmpd F_LEFT
    bls F_READ_SUBTRACT
    ldd F_LEFT
F_READ_SUBTRACT:
    tfr d,w
    ldd F_LEFT
    subr w,d
    std F_LEFT
    lbeq FS_API_OK
    clr F_SECTOR_OFF
    clr F_SECTOR_OFF+1
    jsr F_ADVANCE
    bra F_READ_NEXT
F_READ_ERROR:
    lbra FS_API_RETURN

; -------------------------------------------------------
;  Count used and free partition blocks, excluding bitmap padding.
; -------------------------------------------------------
; input:            X=writable eight-byte result buffer; mounted partition
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; [X]=32-bit used
;                   blocks, [X+4]=32-bit free blocks, big-endian
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_STATS:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    stx F_REQUEST
    cmpx #FS_CON_REQUEST
    beq F_STATS_BUFFER_OK
    ldd #8
    jsr F_RAM_SPAN
    lbcs FS_API_RETURN
F_STATS_BUFFER_OK:
    jsr F_REQUIRE_MOUNT
    lbcs FS_API_RETURN
    ldq #0
    stq F_USED
    ldq F_BLOCKS
    stq F_BITS
    ldq F_BITMAP_LBA
    stq F_CURRENT
F_STATS_SECTOR:
    ldq F_CURRENT
    jsr F_READ_SECTOR
    lbcs FS_API_RETURN
    ldy #FS_BUFFER
F_STATS_BYTE:
    lda ,y+
    sta F_BYTE
    ldu #8
F_STATS_BIT:
    lsr F_BYTE
    bcc F_STATS_FREE
    ldq F_USED
    addw #1
    adcb #0
    adca #0
    stq F_USED
F_STATS_FREE:
    ldq F_BITS
    subw #1
    sbcb #0
    sbca #0
    stq F_BITS
    jsr F_Q_ZERO
    beq F_STATS_DONE
    leau -1,u
    bne F_STATS_BIT
    cmpy #FS_BUFFER+512
    bne F_STATS_BYTE
    jsr F_ADVANCE
    bra F_STATS_SECTOR
F_STATS_DONE:
    ldx F_REQUEST
    ldq F_USED
    stq ,x
    ldq F_BLOCKS
    subw F_USED+2
    sbcb F_USED+1
    sbca F_USED
    stq 4,x
    lbra FS_API_OK

; Request and buffer bounds protect module state, BIOS state, stack and ROM.
; -------------------------------------------------------
;  Validate a request, reset its transfer count and mutation cache, and require a mount.
; -------------------------------------------------------
; input:            X=FsRequest; F_STACK_BASE=lowest allowed caller stack address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; F_REQUEST=X; valid
;                   request.done=0
; clobbers:         D, Y, CC
; -------------------------------------------------------
F_REQUEST_CHECK:
    clr M_FORBIDDEN
    clr M_MAP_VALID
    clr M_MAP_DIRTY
    stx F_REQUEST
    cmpx #FS_CON_REQUEST
    beq F_REQUEST_VALID
    ldd #FS_REQ_SIZE
    jsr F_RAM_SPAN
    bcs F_REQUEST_RETURN
F_REQUEST_VALID:
    clr FS_REQ_DONE,x
    clr FS_REQ_DONE+1,x
    jsr F_REQUIRE_MOUNT
F_REQUEST_RETURN:
    rts

; -------------------------------------------------------
;  Require an initialized module and a valid mounted partition.
; -------------------------------------------------------
; input:            F_READY, F_MOUNTED
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure
; clobbers:         D, CC
; -------------------------------------------------------
F_REQUIRE_MOUNT:
    tst F_READY
    beq F_REQUIRE_ABI
    tst F_MOUNTED
    beq F_REQUIRE_NO_MOUNT
    clrd
    andcc #$FE
    rts
F_REQUIRE_ABI:
    ldd #FS_EABI
    bra F_HELPER_ERROR
F_REQUIRE_NO_MOUNT:
    ldd #FS_ENOMOUNT
    bra F_HELPER_ERROR

; -------------------------------------------------------
;  Require capacity for a raw directory entry and validate the complete buffer span.
; -------------------------------------------------------
; input:            F_REQUEST=FsRequest pointer; F_STACK_BASE=caller stack bound
; output:           C clear for a valid buffer of at least 128 bytes; D=FS_EINVAL/C set otherwise
; clobbers:         D, X, Y, CC
; -------------------------------------------------------
F_ENTRY_BUFFER_CHECK:
    ldx F_REQUEST
    ldd FS_REQ_COUNT,x
    cmpd #MLFS_DENTRY_SIZE
    blo F_REQUEST_INVALID

; -------------------------------------------------------
;  Validate a request buffer, allowing the console to use its serial buffer.
; -------------------------------------------------------
; input:            F_REQUEST=FsRequest pointer; F_STACK_BASE=caller stack bound
; output:           C clear on success; D=FS_EINVAL/C set on failure; X=buffer pointer
; clobbers:         D, X, Y, CC
; -------------------------------------------------------
F_BUFFER_CHECK:
    ldx F_REQUEST
    ldd FS_REQ_COUNT,x
    ldx FS_REQ_BUFFER,x
    ; Only this exact internal request may use the console's serial buffer.
    ldy F_REQUEST
    cmpy #FS_CON_REQUEST
    bne F_RAM_SPAN
    cmpx #SERIAL_BUFFER_START
    bne F_RAM_SPAN
    cmpd #SERIAL_BUFFER_SIZE
    bhi F_REQUEST_INVALID
    andcc #$FE
    rts

; -------------------------------------------------------
;  Check that a byte span fits application RAM or live caller stack storage.
; -------------------------------------------------------
; input:            X=start address; D=byte count; F_STACK_BASE=caller stack bound
; output:           C clear and D preserved on success; D=FS_EINVAL/C set on failure
; clobbers:         D, Y, CC
; -------------------------------------------------------
F_RAM_SPAN:
    pshs d
    cmpx #MLP_APPLICATION_BASE
    blo F_RAM_BAD
    ldy #MLP_APPLICATION_LIMIT
    cmpx #MLP_APPLICATION_LIMIT
    blo F_RAM_ADD
    cmpx #$DC00
    blo F_RAM_BAD
    cmpx F_STACK_BASE
    blo F_RAM_BAD
    ldy #$E000
F_RAM_ADD:
    tfr x,d
    addd ,s
    bcs F_RAM_BAD
    cmpr y,d
    bhi F_RAM_BAD
    puls d
    andcc #$FE
    rts
F_RAM_BAD:
    leas 2,s

; -------------------------------------------------------
;  Return an invalid-argument error to the calling helper.
; -------------------------------------------------------
; input:            None
; output:           D=FS_EINVAL; C set
; clobbers:         D, CC
; -------------------------------------------------------
F_REQUEST_INVALID:
    ldd #FS_EINVAL

; -------------------------------------------------------
;  Return the supplied helper error with carry set.
; -------------------------------------------------------
; input:            D=negative FS_E* error
; output:           D unchanged; C set
; clobbers:         CC
; -------------------------------------------------------
F_HELPER_ERROR:
    orcc #1
    rts

; Resolve a path from root without allocating blocks or copying whole paths.
; -------------------------------------------------------
;  Resolve a bounded path from root using one sector buffer.
; -------------------------------------------------------
; input:            F_REQUEST=FsRequest pointer containing the path; mounted state
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; FS_DENTRY and
;                   M_ENTRY_* identify the result; F_DIR_* identifies its parent; F_PATH/FS_NAME
;                   identify the unmatched component on FS_ENOENT
; clobbers:         D, W, X, Y, CC
; -------------------------------------------------------
F_LOOKUP:
    ldx F_REQUEST
    ldx FS_REQ_PATH,x

; -------------------------------------------------------
;  Resolve a bounded path from root using one sector buffer.
; -------------------------------------------------------
; input:            X=NUL-terminated path; F_REQUEST selects caller/console bounds; mounted state
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; FS_DENTRY and
;                   M_ENTRY_* identify the result; F_DIR_* identifies its parent; F_PATH/FS_NAME
;                   identify the unmatched component on FS_ENOENT
; clobbers:         D, W, X, Y, CC
; -------------------------------------------------------
F_LOOKUP_AT_X:
    ldy #MLP_APPLICATION_LIMIT
    ldd F_REQUEST
    cmpd #FS_CON_REQUEST
    bne F_LOOKUP_EXTERNAL
    ldy #FS_LINE_LIMIT
    cmpx #FS_LINE
    bhs F_LOOKUP_PATH_SET
    cmpx #F_ROOT_PATH
    bne F_REQUEST_INVALID
    ldy #F_ROOT_PATH+2
    bra F_LOOKUP_PATH_SET
F_LOOKUP_EXTERNAL:
    cmpx #MLP_APPLICATION_BASE
    blo F_REQUEST_INVALID
    cmpx #MLP_APPLICATION_LIMIT
    blo F_LOOKUP_PATH_SET
    cmpx #$DC00
    blo F_REQUEST_INVALID
    cmpx F_STACK_BASE
    blo F_REQUEST_INVALID
    ldy #$E000
F_LOOKUP_PATH_SET:
    cmpr y,x
    lbhs F_REQUEST_INVALID
    stx F_PATH
    sty F_PATH_LIMIT
    clr F_DEPTH
    ldq #0
    stq M_ENTRY_LBA
    ; A synthetic root dentry shares all subsequent directory traversal code.
    ldx #FS_DENTRY
    ldy #MLFS_DENTRY_SIZE
F_ROOT_CLEAR:
    clr ,x+
    leay -1,y
    bne F_ROOT_CLEAR
    lda #1
    sta FS_DENTRY+MLFS_DENTRY_IN_USE
    sta FS_DENTRY+MLFS_DENTRY_FLAGS
    sta FS_DENTRY+MLFS_DENTRY_EXTENTS_USED
    sta FS_DENTRY+MLFS_DENTRY_EXTENTS_TOTAL
    ldx #F_ROOT
    ldy #FS_DENTRY+MLFS_DENTRY_EXTENTS
    ldw #8
    tfm x+,y+
    ldq F_ROOT_LBA
    stq F_DIR_LBA
    ldq F_ROOT_END
    stq F_DIR_END
F_PATH_NEXT:
    ldx F_PATH
F_PATH_SLASH:
    cmpx F_PATH_LIMIT
    lbhs F_PATH_TOO_LONG
    lda ,x+
    lbeq F_LOOKUP_SUCCESS
    cmpa #'/'
    bne F_PATH_NAME_START
    lda FS_DENTRY+MLFS_DENTRY_FLAGS
    bita #MLFS_DENTRY_FLAG_DIR
    lbeq F_NOT_DIRECTORY
    bra F_PATH_SLASH
F_PATH_NAME_START:
    inc F_DEPTH
    ldb F_DEPTH
    cmpb #16
    lbhi F_PATH_TOO_LONG
    ldy #FS_NAME
F_PATH_NAME:
    sta ,y+
    cmpy #FS_NAME+MLFS_MAX_NAME
    lbhs F_PATH_TOO_LONG
    cmpx F_PATH_LIMIT
    lbhs F_PATH_TOO_LONG
    lda ,x+
    beq F_PATH_COMPONENT
    cmpa #'/'
    bne F_PATH_NAME
F_PATH_COMPONENT:
    clr ,y
    leax -1,x                       ; Leave slash/NUL for the next iteration.
    stx F_PATH
    ; Dot traversal is deliberately rejected; names remain literal components.
    lda FS_NAME
    cmpa #'.'
    bne F_PATH_FIND
    tst FS_NAME+1
    lbeq F_REQUEST_INVALID
    lda FS_NAME+1
    cmpa #'.'
    bne F_PATH_FIND
    tst FS_NAME+2
    lbeq F_REQUEST_INVALID
F_PATH_FIND:
    jsr F_DIRECTORY
    lbcs F_LOOKUP_DONE
    ldq F_DIR_LBA
    stq F_CURRENT
F_LOOKUP_SECTOR:
    ldq F_CURRENT
    cmpd F_DIR_END
    lbhi F_PATH_MISSING
    blo F_LOOKUP_READ
    cmpw F_DIR_END+2
    lbhs F_PATH_MISSING
F_LOOKUP_READ:
    jsr F_READ_SECTOR
    lbcs F_LOOKUP_DONE
    ldx #FS_BUFFER
F_LOOKUP_SLOT:
    lda MLFS_DENTRY_IN_USE,x
    beq F_LOOKUP_SKIP
    cmpa #1
    lbne F_PATH_CORRUPT
    pshs x
    leax MLFS_DENTRY_NAME,x
    ldy #FS_NAME
    ldb #MLFS_MAX_NAME
F_NAME_COMPARE:
    lda ,y+
    cmpa ,x+
    bne F_NAME_DIFFERENT
    tsta
    beq F_NAME_FOUND
    decb
    bne F_NAME_COMPARE
F_NAME_DIFFERENT:
    puls x
F_LOOKUP_SKIP:
    leax MLFS_DENTRY_SIZE,x
    cmpx #FS_BUFFER+512
    bne F_LOOKUP_SLOT
    jsr F_ADVANCE
    bra F_LOOKUP_SECTOR
F_NAME_FOUND:
    puls x
    jsr F_SAVE_ENTRY
    jsr F_VALIDATE_ENTRY
    bcs F_LOOKUP_DONE
    lbra F_PATH_NEXT
F_LOOKUP_DONE:
    rts
F_LOOKUP_SUCCESS:
    clrd
    andcc #$FE
    rts

; -------------------------------------------------------
;  Return a missing-path-component error.
; -------------------------------------------------------
; input:            None
; output:           D=FS_ENOENT; C set
; clobbers:         D, CC
; -------------------------------------------------------
F_PATH_MISSING:
    ldd #FS_ENOENT
    lbra F_HELPER_ERROR

; -------------------------------------------------------
;  Return a corrupt-filesystem-metadata error.
; -------------------------------------------------------
; input:            None
; output:           D=FS_ECORRUPT; C set
; clobbers:         D, CC
; -------------------------------------------------------
F_PATH_CORRUPT:
    ldd #FS_ECORRUPT
    lbra F_HELPER_ERROR

; -------------------------------------------------------
;  Return an overlong or excessively deep path error.
; -------------------------------------------------------
; input:            None
; output:           D=FS_ENAMETOOLONG; C set
; clobbers:         D, CC
; -------------------------------------------------------
F_PATH_TOO_LONG:
    ldd #FS_ENAMETOOLONG
    lbra F_HELPER_ERROR

; -------------------------------------------------------
;  Record a directory slot location and copy its entry into private storage.
; -------------------------------------------------------
; input:            X=128-byte entry within FS_BUFFER; F_CURRENT=its sector LBA
; output:           FS_DENTRY=entry copy; M_ENTRY_LBA/M_ENTRY_OFF=on-disk location; W=0
; clobbers:         D, W, X, Y, CC
; -------------------------------------------------------
F_SAVE_ENTRY:
    jsr M_RECORD_SLOT
    ldy #FS_DENTRY
    ldw #MLFS_DENTRY_SIZE
    tfm x+,y+
    rts

; -------------------------------------------------------
;  Copy the private directory entry to the request destination.
; -------------------------------------------------------
; input:            FS_DENTRY=128-byte entry; F_REQUEST points to a validated destination request
; output:           128 bytes copied; X=FS_DENTRY+128; Y=destination+128; W=0
; clobbers:         W, X, Y, CC
; -------------------------------------------------------
F_COPY_ENTRY:
    ldx F_REQUEST
    ldy FS_REQ_BUFFER,x
    ldx #FS_DENTRY
    ldw #MLFS_DENTRY_SIZE
    tfm x+,y+
    rts

; -------------------------------------------------------
;  Validate an entry name, type, contiguous extent, and logical size.
; -------------------------------------------------------
; input:            FS_DENTRY=entry; mounted partition bounds and F_DATA_MIN
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure;
;                   F_CURRENT/F_END=data sector extent on success
; clobbers:         D, W, X, CC
; -------------------------------------------------------
F_VALIDATE_ENTRY:
    ldx #FS_DENTRY+MLFS_DENTRY_NAME
    tst ,x
    lbeq F_PATH_CORRUPT
    ldb #MLFS_MAX_NAME
F_VALIDATE_NAME:
    tst ,x+
    beq F_VALIDATE_FLAGS
    decb
    bne F_VALIDATE_NAME
    bra F_PATH_CORRUPT
F_VALIDATE_FLAGS:
    lda FS_DENTRY+MLFS_DENTRY_FLAGS
    anda #3
    cmpa #1
    beq F_VALIDATE_LAYOUT
    cmpa #2
    bne F_PATH_CORRUPT
F_VALIDATE_LAYOUT:
    lda FS_DENTRY+MLFS_DENTRY_EXTENTS_USED
    cmpa #1
    bne F_LAYOUT_BAD
    lda FS_DENTRY+MLFS_DENTRY_EXTENTS_TOTAL
    cmpa #1
    bhi F_LAYOUT_BAD
    ldq FS_DENTRY+MLFS_DENTRY_FIRST_INDIRECT
    jsr F_Q_ZERO
    bne F_LAYOUT_BAD
    ldq F_DATA_MIN
    stq F_TEMP2
    ldx #FS_DENTRY+MLFS_DENTRY_EXTENTS
    jsr F_RANGE
    bcs F_PATH_CORRUPT
    ; File byte count must fit the extent: ceil(size/512) <= extent sectors.
    ldq FS_DENTRY+MLFS_DENTRY_SIZE_BYTES
    addw #511
    adcb #0
    adca #0
    bcs F_FILE_SIZE_OVERFLOW
    stq F_TEMP
    ldb #9
    jsr F_SHIFT_RIGHT
    bra F_FILE_CAPACITY
F_FILE_SIZE_OVERFLOW:
    ; A 32-bit size near UINT32_MAX still needs at most $00800000 sectors.
    ldq #$00800000
    stq F_TEMP
F_FILE_CAPACITY:
    ldq F_END
    subw F_CURRENT+2
    sbcb F_CURRENT+1
    sbca F_CURRENT
    cmpd F_TEMP
    lblo F_PATH_CORRUPT
    bhi F_ENTRY_VALID
    cmpw F_TEMP+2
    lblo F_PATH_CORRUPT
F_ENTRY_VALID:
    clrd
    andcc #$FE
    rts

; -------------------------------------------------------
;  Return an unsupported extent-layout error.
; -------------------------------------------------------
; input:            None
; output:           D=FS_EUNSUPPORTED; C set
; clobbers:         D, CC
; -------------------------------------------------------
F_LAYOUT_BAD:
    ldd #FS_EUNSUPPORTED
    lbra F_HELPER_ERROR

; -------------------------------------------------------
;  Resolve a directory extent and reject a forbidden ancestor during moves.
; -------------------------------------------------------
; input:            FS_DENTRY=directory or synthetic root; mounted state;
;                   M_FORBIDDEN/M_FORBID_START
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure;
;                   F_DIR_LBA/F_DIR_END=directory sector extent
; clobbers:         D, W, X, CC
; -------------------------------------------------------
F_DIRECTORY:
    lda FS_DENTRY+MLFS_DENTRY_FLAGS
    bita #MLFS_DENTRY_FLAG_DIR
    beq F_NOT_DIRECTORY
    ; Synthetic root has no name. A real dentry cannot use an empty name.
    tst FS_DENTRY+MLFS_DENTRY_NAME
    beq F_DIRECTORY_ROOT
    tst M_FORBIDDEN
    beq F_DIRECTORY_RANGE
    ldq FS_DENTRY+MLFS_DENTRY_EXTENTS
    cmpd M_FORBID_START
    bne F_DIRECTORY_RANGE
    cmpw M_FORBID_START+2
    lbeq F_REQUEST_INVALID
F_DIRECTORY_RANGE:
    ldq F_DATA_MIN
    stq F_TEMP2
    ldx #FS_DENTRY+MLFS_DENTRY_EXTENTS
    jsr F_RANGE
    lbcs F_PATH_CORRUPT
    ldq F_CURRENT
    stq F_DIR_LBA
    ldq F_END
    stq F_DIR_END
    bra F_DIRECTORY_OK
F_DIRECTORY_ROOT:
    ldq F_ROOT_LBA
    stq F_DIR_LBA
    ldq F_ROOT_END
    stq F_DIR_END
F_DIRECTORY_OK:
    clrd
    andcc #$FE
    rts

; -------------------------------------------------------
;  Return a path-component-is-not-a-directory error.
; -------------------------------------------------------
; input:            None
; output:           D=FS_ENOTDIR; C set
; clobbers:         D, CC
; -------------------------------------------------------
F_NOT_DIRECTORY:
    ldd #FS_ENOTDIR
    lbra F_HELPER_ERROR

; Q helpers and streaming sector access. Internal helpers may clobber registers.
; -------------------------------------------------------
;  Test whether all 32 bits of Q are zero without changing its value.
; -------------------------------------------------------
; input:            Q=32-bit value (D:W)
; output:           Z set if Q=0, clear otherwise; Q unchanged
; clobbers:         CC
; -------------------------------------------------------
F_Q_ZERO:
    tstd
    bne F_Q_NONZERO
    cmpw #0
F_Q_NONZERO:
    rts

; -------------------------------------------------------
;  Convert a partition-relative block number to an absolute sector LBA.
; -------------------------------------------------------
; input:            Q=relative block; F_SHIFT=log2(sectors/block); F_PART=partition start LBA
; output:           Q=absolute LBA/C clear on success; C set on shift or addition overflow;
;                   F_TEMP=scratch
; clobbers:         D, W, CC
; -------------------------------------------------------
F_BLOCK_LBA:
    stq F_TEMP
    ldb F_SHIFT
    beq F_BLOCK_SHIFTED
F_BLOCK_SHIFT:
    asl F_TEMP+3
    rol F_TEMP+2
    rol F_TEMP+1
    rol F_TEMP
    bcs F_RANGE_BAD
    decb
    bne F_BLOCK_SHIFT
F_BLOCK_SHIFTED:
    ldq F_TEMP
    addw F_PART+2
    adcb F_PART+1
    adca F_PART
    rts

; -------------------------------------------------------
;  Shift the private 32-bit scratch value right by a specified bit count.
; -------------------------------------------------------
; input:            F_TEMP=32-bit value; B=shift count 1..32
; output:           F_TEMP shifted right; B=0
; clobbers:         B, CC
; -------------------------------------------------------
F_SHIFT_RIGHT:
    lsr F_TEMP
    ror F_TEMP+1
    ror F_TEMP+2
    ror F_TEMP+3
    decb
    bne F_SHIFT_RIGHT
    rts

; -------------------------------------------------------
;  Validate an ordered contiguous block extent and convert its endpoints to LBAs.
; -------------------------------------------------------
; input:            X=big-endian block start/count pair; F_TEMP2=minimum start; mounted bounds
; output:           C clear for valid extent; F_CURRENT/F_END=sector endpoints; F_TEMP2=end
;                   block; C set on failure
; clobbers:         D, W, CC
; -------------------------------------------------------
F_RANGE:
    ldq ,x
    cmpd F_TEMP2
    blo F_RANGE_BAD
    bhi F_RANGE_START_OK
    cmpw F_TEMP2+2
    blo F_RANGE_BAD
F_RANGE_START_OK:
    ldq 4,x
    jsr F_Q_ZERO
    beq F_RANGE_BAD
    ldq ,x
    addw 6,x
    adcb 5,x
    adca 4,x
    bcs F_RANGE_BAD
    cmpd F_BLOCKS
    bhi F_RANGE_BAD
    blo F_RANGE_END_OK
    cmpw F_BLOCKS+2
    bhi F_RANGE_BAD
F_RANGE_END_OK:
    stq F_TEMP2
    jsr F_BLOCK_LBA
    bcs F_RANGE_BAD
    stq F_END
    ldq ,x
    jsr F_BLOCK_LBA
    bcs F_RANGE_BAD
    stq F_CURRENT
    andcc #$FE
    rts
F_RANGE_BAD:
    orcc #1
    rts

; -------------------------------------------------------
;  Advance the current sector cursor by one.
; -------------------------------------------------------
; input:            F_CURRENT=32-bit sector LBA
; output:           Q and F_CURRENT=previous LBA+1; caller enforces bounds
; clobbers:         D, W, CC
; -------------------------------------------------------
F_ADVANCE:
    ldq F_CURRENT
    addw #1
    adcb #0
    adca #0
    stq F_CURRENT
    rts

; -------------------------------------------------------
;  Read one CF sector into the private data buffer.
; -------------------------------------------------------
; input:            Q=LBA28; F_CF_READ=BIOS read entry
; output:           FS_BUFFER=512 bytes read; D=0/C clear or D=FS_EIO/C set
; clobbers:         D, X, CC; W is preserved
; -------------------------------------------------------
F_READ_SECTOR:
    ldx #FS_BUFFER
    jsr [F_CF_READ]
    bcc F_SECTOR_OK
    ldd #FS_EIO
    lbra F_HELPER_ERROR

; -------------------------------------------------------
;  Return successful sector-I/O status.
; -------------------------------------------------------
; input:            None
; output:           D=0; C clear
; clobbers:         D, CC
; -------------------------------------------------------
F_SECTOR_OK:
    clrd
    andcc #$FE
    rts

; -------------------------------------------------------
;  Compare seven magic/version bytes against the expected identifier.
; -------------------------------------------------------
; input:            X=candidate bytes; Y=expected seven-byte identifier
; output:           C clear on a match; D=FS_ECORRUPT/C set on mismatch; X/Y advanced
; clobbers:         D, X, Y, CC
; -------------------------------------------------------
F_IDENTIFY:
    ldb #7
F_IDENTIFY_BYTE:
    lda ,x+
    cmpa ,y+
    bne F_IDENTIFY_BAD
    decb
    bne F_IDENTIFY_BYTE
    andcc #$FE
    rts
F_IDENTIFY_BAD:
    ldd #FS_ECORRUPT
    lbra F_HELPER_ERROR
F_PT_ID:
    fcc "MLPT"
    fcb 1,1,0
F_FS_ID:
    fcc "MLFS"
    fcb 1,1,0

; -------------------------------------------------------
;  Compute the 32-bit additive checksum of one buffered sector.
; -------------------------------------------------------
; input:            FS_BUFFER=512 input bytes
; output:           Q and F_TEMP=32-bit byte sum
; clobbers:         D, W, X, Y, CC
; -------------------------------------------------------
F_SUM_SECTOR:
    ldq #0
    stq F_TEMP
    ldx #FS_BUFFER
    ldy #512
F_SUM_BYTE:
    lda ,x+
    adda F_TEMP+3
    sta F_TEMP+3
    bcc F_SUM_NEXT
    inc F_TEMP+2
    bne F_SUM_NEXT
    inc F_TEMP+1
    bne F_SUM_NEXT
    inc F_TEMP
F_SUM_NEXT:
    leay -1,y
    bne F_SUM_BYTE
    ldq F_TEMP
    rts

; -------------------------------------------------------
;  Finish a public service successfully and restore its saved registers.
; -------------------------------------------------------
; input:            S points to saved X,Y,U followed by the service return address
; output:           D=0/C clear; X,Y,U restored; returns to service caller
; clobbers:         D, CC
; -------------------------------------------------------
FS_API_OK:
    clrd
    andcc #$FE

; -------------------------------------------------------
;  Restore a public service frame and return its existing result.
; -------------------------------------------------------
; input:            D/CC=service result; S points to saved X,Y,U followed by the service return
;                   address
; output:           D/CC unchanged; X,Y,U restored; returns to service caller
; clobbers:         None beyond restoring X,Y,U
; -------------------------------------------------------
FS_API_RETURN:
    puls x,y,u,pc

; -------------------------------------------------------
;  Finish a public service with an ABI or initialization error.
; -------------------------------------------------------
; input:            S points to saved X,Y,U followed by the service return address
; output:           D=FS_EABI/C set; X,Y,U restored; returns to service caller
; clobbers:         D, CC
; -------------------------------------------------------
FS_API_ABI:
    ldd #FS_EABI
    bra FS_API_ERROR

; -------------------------------------------------------
;  Finish a public service with an invalid-argument error.
; -------------------------------------------------------
; input:            S points to saved X,Y,U followed by the service return address
; output:           D=FS_EINVAL/C set; X,Y,U restored; returns to service caller
; clobbers:         D, CC
; -------------------------------------------------------
FS_API_INVALID:
    ldd #FS_EINVAL
    bra FS_API_ERROR

; -------------------------------------------------------
;  Finish a public service with an corrupt-metadata error.
; -------------------------------------------------------
; input:            S points to saved X,Y,U followed by the service return address
; output:           D=FS_ECORRUPT/C set; X,Y,U restored; returns to service caller
; clobbers:         D, CC
; -------------------------------------------------------
FS_API_CORRUPT:
    ldd #FS_ECORRUPT
    bra FS_API_ERROR

; -------------------------------------------------------
;  Finish a public service with an offset-overflow error.
; -------------------------------------------------------
; input:            S points to saved X,Y,U followed by the service return address
; output:           D=FS_ERANGE/C set; X,Y,U restored; returns to service caller
; clobbers:         D, CC
; -------------------------------------------------------
FS_API_RANGE:
    ldd #FS_ERANGE
    bra FS_API_ERROR

; -------------------------------------------------------
;  Finish a public service with an file-operation-on-directory error.
; -------------------------------------------------------
; input:            S points to saved X,Y,U followed by the service return address
; output:           D=FS_EISDIR/C set; X,Y,U restored; returns to service caller
; clobbers:         D, CC
; -------------------------------------------------------
FS_API_ISDIR:
    ldd #FS_EISDIR

; -------------------------------------------------------
;  Finish a public service with the supplied error and restore its saved registers.
; -------------------------------------------------------
; input:            D=negative FS_E* error; S points to saved X,Y,U followed by the service
;                   return address
; output:           D unchanged/C set; X,Y,U restored; returns to service caller
; clobbers:         CC
; -------------------------------------------------------
FS_API_ERROR:
    orcc #1
    bra FS_API_RETURN

    include "mutation.asm"
    include "console.asm"
FS_CODE_END:
    ifgt FS_CODE_END-FS_STATE
        error "Filesystem code overlaps module-private state"
    endc
    ifgt FS_MEMORY_END-MLP_FILESYSTEM_LIMIT
        error "Filesystem exceeds its reserved RAM region"
    endc
