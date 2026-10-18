; Mutation state shares no buffers with callers. Bitmap sectors use BA00,
; data/directory sectors B800. Only one mutation may run at a time.
M_ENTRY_LBA    equ $B680
M_ENTRY_OFF    equ $B684
M_WANTED       equ $B686
M_ALLOC_START  equ $B68A
M_ALLOC_COUNT  equ $B68E
M_SCAN_BLOCK   equ $B692
M_RUN          equ $B696
M_MAP_LBA      equ $B69A
M_MAP_OFF      equ $B69E
M_MASK         equ $B6A0
M_MODE         equ $B6A1       ; 0 free, 1 allocate, 2 verify used, 3 verify free
M_LEFT         equ $B6A2
M_MAP_VALID    equ $B6A6
M_OLD_START    equ $B6A7
M_OLD_COUNT    equ $B6AB
M_NEW_SIZE     equ $B6AF
M_POSITION     equ $B6B3
M_STOP         equ $B6B7
M_DATA_LBA     equ $B6BB
M_COPY_LBA     equ $B6BF
M_COPY_END     equ $B6C3
M_SOURCE_LBA   equ $B6C7
M_SOURCE_OFF   equ $B6CB
M_PARENT_LBA   equ $B6CD
M_DEST_LBA     equ $B6D1
M_DEST_OFF     equ $B6D5
M_TYPE         equ $B6D7
M_FORBIDDEN    equ $B6D8
M_FORBID_START equ $B6D9
M_RELOCATED    equ $B6DD
M_CACHED_LBA   equ $B6DE
M_ERROR        equ $B6E2
M_MAP_DIRTY    equ $B6E4
M_CHUNK        equ $B6E5
M_ZERO         equ $B6E7
M_PUBLISH      equ $B6E8

; Record the location before F_VALIDATE_ENTRY replaces F_CURRENT with data LBA.
; -------------------------------------------------------
;  Record a buffered directory entry location before extent validation changes the cursor.
; -------------------------------------------------------
; input:            X=entry within FS_BUFFER; F_CURRENT=containing sector LBA
; output:           M_ENTRY_LBA=sector; M_ENTRY_OFF=byte offset; X preserved
; clobbers:         D, W, CC
; -------------------------------------------------------
M_RECORD_SLOT:
    tfr x,d
    subd #FS_BUFFER
    std M_ENTRY_OFF
    ldq F_CURRENT
    stq M_ENTRY_LBA
    rts

; -------------------------------------------------------
;  Write the private data buffer to one CF sector.
; -------------------------------------------------------
; input:            Q=LBA28; FS_BUFFER=512 source bytes; F_CF_WRITE=BIOS write entry
; output:           D=0/C clear on success; D=FS_EIO/C set on failure
; clobbers:         D, X, CC; W is preserved
; -------------------------------------------------------
F_WRITE_SECTOR:
    ldx #FS_BUFFER
    jsr [F_CF_WRITE]
    lbcs M_IO_ERROR
    lbra F_SECTOR_OK

; Sector read/modify/write preserves the other three directory entries.
; -------------------------------------------------------
;  Commit the private entry with sector read/modify/write, preserving neighboring entries.
; -------------------------------------------------------
; input:            FS_DENTRY=128-byte entry; M_ENTRY_LBA/M_ENTRY_OFF=target slot
; output:           D=0/C clear or D=FS_EIO/C set; FS_BUFFER=directory-sector scratch
; clobbers:         D, W, X, Y, CC
; -------------------------------------------------------
M_STORE_ENTRY:
    ldq M_ENTRY_LBA
    jsr F_READ_SECTOR
    bcs M_STORE_RETURN
    ldd M_ENTRY_OFF
    ldy #FS_BUFFER
    leay d,y
    ldx #FS_DENTRY
    ldw #MLFS_DENTRY_SIZE
    tfm x+,y+
    ldq M_ENTRY_LBA
    jsr F_WRITE_SECTOR
M_STORE_RETURN:
    rts

; -------------------------------------------------------
;  Zero the private directory entry without writing to disk.
; -------------------------------------------------------
; input:            None
; output:           FS_DENTRY=128 zero bytes; X=FS_DENTRY+128; W=0
; clobbers:         W, X, CC
; -------------------------------------------------------
M_CLEAR_ENTRY:
    ldx #FS_DENTRY
    ldw #MLFS_DENTRY_SIZE
M_CLEAR_BYTE:
    clr ,x+
    decw
    bne M_CLEAR_BYTE
    rts

; -------------------------------------------------------
;  Clear an on-disk directory slot using sector read/modify/write.
; -------------------------------------------------------
; input:            M_ENTRY_LBA/M_ENTRY_OFF=target slot
; output:           FS_DENTRY cleared; D=0/C clear or D=FS_EIO/C set
; clobbers:         D, W, X, Y, CC
; -------------------------------------------------------
M_ERASE_ENTRY:
    jsr M_CLEAR_ENTRY
    bra M_STORE_ENTRY

; Missing final component is usable for create/rename. A missing ancestor is
; an error. The existing lookup leaves the parent extent and final name intact.
; -------------------------------------------------------
;  Accept a missing final component for creation, rejecting missing ancestors and invalid tails.
; -------------------------------------------------------
; input:            D=lookup error; F_PATH/F_PATH_LIMIT=unmatched tail; M_TYPE=file or directory
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; FS_NAME and parent
;                   directory state retained
; clobbers:         D, X, CC
; -------------------------------------------------------
M_MISSING_LEAF:
    cmpd #FS_ENOENT
    beq M_CHECK_LEAF
    orcc #1
    rts
M_CHECK_LEAF:
    ldx F_PATH
    clrb
M_LEAF_TAIL:
    cmpx F_PATH_LIMIT
    lbhs F_PATH_TOO_LONG
    lda ,x+
    beq M_LEAF_END
    cmpa #'/'
    bne M_NO_ENTRY
    ldb #1
    bra M_LEAF_TAIL
M_LEAF_END:
    tstb
    beq M_LEAF_OK
    lda M_TYPE
    cmpa #MLFS_DENTRY_FLAG_DIR
    lbne F_NOT_DIRECTORY
M_LEAF_OK:
    clrd
    andcc #$FE
M_HELPER_RETURN:
    rts

; -------------------------------------------------------
;  Return a missing-ancestor error to the calling helper.
; -------------------------------------------------------
; input:            None
; output:           D=FS_ENOENT; C set
; clobbers:         D, CC
; -------------------------------------------------------
M_NO_ENTRY:
    ldd #FS_ENOENT
    lbra F_HELPER_ERROR

; -------------------------------------------------------
;  Find an unused directory slot without changing its contents.
; -------------------------------------------------------
; input:            F_DIR_LBA/F_DIR_END=validated directory sector extent
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure;
;                   M_ENTRY_LBA/M_ENTRY_OFF=free slot; FS_BUFFER=containing sector
; clobbers:         D, W, X, CC
; -------------------------------------------------------
M_FIND_SLOT:
    ldq F_DIR_LBA
    stq F_CURRENT
M_SLOT_SECTOR:
    ldq F_CURRENT
    cmpd F_DIR_END
    lbhi M_NO_SPACE
    blo M_SLOT_READ
    cmpw F_DIR_END+2
    lbhs M_NO_SPACE
M_SLOT_READ:
    jsr F_READ_SECTOR
    bcs M_HELPER_RETURN
    ldx #FS_BUFFER
M_SLOT_NEXT:
    lda ,x
    beq M_SLOT_FOUND
    cmpa #1
    lbne F_PATH_CORRUPT
    leax MLFS_DENTRY_SIZE,x
    cmpx #FS_BUFFER+512
    bne M_SLOT_NEXT
    jsr F_ADVANCE
    bra M_SLOT_SECTOR
M_SLOT_FOUND:
    jsr M_RECORD_SLOT
    clrd
    andcc #$FE
    rts

; Bitmap cache: flush a changed sector before reading the next. Failed writes
; leave the cache dirty; rollback invalidates it and rereads actual media.
; -------------------------------------------------------
;  Flush a dirty bitmap sector, retaining the dirty flag if writing fails.
; -------------------------------------------------------
; input:            M_MAP_DIRTY; M_CACHED_LBA; FS_MAP_BUFFER=bitmap sector
; output:           D=0/C clear or D=FS_EIO/C set; M_MAP_DIRTY=0 after success
; clobbers:         D, W, X, CC
; -------------------------------------------------------
M_MAP_FLUSH:
    tst M_MAP_DIRTY
    lbeq M_MAP_OK
    ldq M_CACHED_LBA
    ldx #FS_MAP_BUFFER
    jsr [F_CF_WRITE]
    lbcs M_IO_ERROR
    clr M_MAP_DIRTY
M_MAP_OK:
    clrd
    andcc #$FE
    rts

; -------------------------------------------------------
;  Locate an allocation bit, flushing/loading the bitmap cache as needed.
; -------------------------------------------------------
; input:            M_SCAN_BLOCK=valid relative block; mounted bitmap bounds and cache state
; output:           D=0/C clear, X=bitmap byte, M_MASK=bit mask; D=FS_EIO/C set on failure
; clobbers:         D, W, X, CC
; -------------------------------------------------------
M_BITMAP_LOCATE:
    ldq M_SCAN_BLOCK
    stq F_TEMP
    ldb #12
    jsr F_SHIFT_RIGHT
    ldq F_TEMP
    addw F_BITMAP_LBA+2
    adcb F_BITMAP_LBA+1
    adca F_BITMAP_LBA
    stq M_MAP_LBA
    tst M_MAP_VALID
    beq M_MAP_LOAD
    cmpd M_CACHED_LBA
    bne M_MAP_LOAD
    cmpw M_CACHED_LBA+2
    beq M_MAP_POSITION
M_MAP_LOAD:
    jsr M_MAP_FLUSH
    bcs M_MAP_RETURN
    clr M_MAP_VALID
    ldq M_MAP_LBA
    stq M_CACHED_LBA
    ldx #FS_MAP_BUFFER
    jsr [F_CF_READ]
    lbcs M_IO_ERROR
    inc M_MAP_VALID
M_MAP_POSITION:
    ldd M_SCAN_BLOCK+2
    lsrd
    lsrd
    lsrd
    andd #511
    std M_MAP_OFF
    ldx #FS_MAP_BUFFER
    leax d,x
    ldb M_SCAN_BLOCK+3
    andb #7
    lda #1
    tstb
    beq M_MASK_READY
M_MASK_SHIFT:
    lsla
    decb
    bne M_MASK_SHIFT
M_MASK_READY:
    sta M_MASK
    clrd
    andcc #$FE
M_MAP_RETURN:
    rts

; -------------------------------------------------------
;  Advance the relative-block bitmap cursor by one.
; -------------------------------------------------------
; input:            M_SCAN_BLOCK=32-bit relative block
; output:           Q and M_SCAN_BLOCK=previous block+1
; clobbers:         D, W, CC
; -------------------------------------------------------
M_SCAN_ADVANCE:
    ldq M_SCAN_BLOCK
    addw #1
    adcb #0
    adca #0
    stq M_SCAN_BLOCK
    rts

; Operate on a checked relative-block range. Ranges passed here never include
; filesystem metadata or bitmap padding. Mode 2/3 checks change no bytes.
; -------------------------------------------------------
;  Free, claim, or verify a checked run of allocation bits and flush pending changes.
; -------------------------------------------------------
; input:            M_ALLOC_START/M_ALLOC_COUNT=checked data-block run; M_MODE=0 free, 1 claim, 2
;                   verify used, 3 verify free
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; modes 0/1 update
;                   media; M_SCAN_BLOCK/M_LEFT and cache are scratch
; clobbers:         D, W, X, CC
; -------------------------------------------------------
M_BITMAP_RANGE:
    ldq M_ALLOC_START
    stq M_SCAN_BLOCK
    ldq M_ALLOC_COUNT
    stq M_LEFT
    jsr F_Q_ZERO
    lbeq M_MAP_OK
M_RANGE_NEXT:
    jsr M_BITMAP_LOCATE
    bcs M_MAP_RETURN
    lda ,x
    ldb M_MODE
    cmpb #2
    beq M_RANGE_USED
    cmpb #3
    beq M_RANGE_FREE
    tstb
    beq M_RANGE_CLEAR
    ora M_MASK
    bra M_RANGE_STORE
M_RANGE_CLEAR:
    ldb M_MASK
    comb
    andr b,a
M_RANGE_STORE:
    sta ,x
    lda #1
    sta M_MAP_DIRTY
    bra M_RANGE_ADVANCE
M_RANGE_USED:
    bita M_MASK
    lbeq F_PATH_CORRUPT
    bra M_RANGE_ADVANCE
M_RANGE_FREE:
    bita M_MASK
    lbne M_NO_SPACE
M_RANGE_ADVANCE:
    jsr M_SCAN_ADVANCE
    ldq M_LEFT
    subw #1
    sbcb #0
    sbca #0
    stq M_LEFT
    jsr F_Q_ZERO
    bne M_RANGE_NEXT
    jmp M_MAP_FLUSH

; -------------------------------------------------------
;  Find a contiguous free run without claiming it.
; -------------------------------------------------------
; input:            M_WANTED=nonzero block count; mounted data/bitmap bounds
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure;
;                   M_ALLOC_START/M_ALLOC_COUNT=free run on success
; clobbers:         D, W, X, CC
; -------------------------------------------------------
M_FIND_RUN:
    ldq F_DATA_MIN
    stq M_SCAN_BLOCK
    ldq #0
    stq M_RUN
M_RUN_NEXT:
    ldq M_SCAN_BLOCK
    cmpd F_BLOCKS
    lbhi M_NO_SPACE
    blo M_RUN_TEST
    cmpw F_BLOCKS+2
    lbhs M_NO_SPACE
M_RUN_TEST:
    jsr M_BITMAP_LOCATE
    lbcs M_HELPER_RETURN
    lda ,x
    bita M_MASK
    bne M_RUN_USED
    ldq M_RUN
    jsr F_Q_ZERO
    bne M_RUN_INCREMENT
    ldq M_SCAN_BLOCK
    stq M_ALLOC_START
    ldq #0
M_RUN_INCREMENT:
    addw #1
    adcb #0
    adca #0
    stq M_RUN
    cmpd M_WANTED
    bne M_RUN_ADVANCE
    cmpw M_WANTED+2
    beq M_RUN_FOUND
    bra M_RUN_ADVANCE
M_RUN_USED:
    ldq #0
    stq M_RUN
M_RUN_ADVANCE:
    jsr M_SCAN_ADVANCE
    bra M_RUN_NEXT
M_RUN_FOUND:
    ldq M_WANTED
    stq M_ALLOC_COUNT
    clrd
    andcc #$FE
    rts

; -------------------------------------------------------
;  Find and claim a free contiguous run, rolling back failed claims.
; -------------------------------------------------------
; input:            M_WANTED=nonzero block count; mounted allocation state
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure;
;                   M_ALLOC_START/M_ALLOC_COUNT=claimed run; M_PUBLISH=0
; clobbers:         D, W, X, CC
; -------------------------------------------------------
M_ALLOCATE:
    clr M_PUBLISH
    jsr M_FIND_RUN
    bcs M_ALLOC_RETURN
    lda #1
    sta M_MODE
    jsr M_BITMAP_RANGE
    bcs M_ROLLBACK
M_ALLOC_RETURN:
    rts

; Only free a newly claimed, previously verified free run. Failure of rollback
; invalidates the mount; the original I/O error remains the returned status.
; -------------------------------------------------------
;  Release an unpublished new allocation after readback; invalidate an uncertain mount.
; -------------------------------------------------------
; input:            D=original error; M_ALLOC_*=new run; M_PUBLISH; M_ENTRY_*; FS_DENTRY=new
;                   entry; FS_SAVED_ENTRY=old entry
; output:           D=original error/C set; published blocks retained; F_MOUNTED cleared if
;                   rollback is uncertain
; clobbers:         D, W, X, Y, CC
; -------------------------------------------------------
M_ROLLBACK:
    std M_ERROR
    tst M_PUBLISH
    beq M_ROLLBACK_FREE
    ; A completion error can follow a write that reached media. Never release
    ; an extent until readback establishes that the old entry is still present.
    ldq M_ENTRY_LBA
    jsr F_READ_SECTOR
    bcs M_ROLLBACK_UNCERTAIN
    ldd M_ENTRY_OFF
    ldx #FS_BUFFER
    leax d,x
    pshs x
    ldy #FS_DENTRY
    jsr M_COMPARE_ENTRY
    puls x
    beq M_ROLLBACK_DONE           ; New entry reached media: keep its blocks.
    ldy #FS_SAVED_ENTRY
    jsr M_COMPARE_ENTRY
    bne M_ROLLBACK_UNCERTAIN
M_ROLLBACK_FREE:
    clr M_MAP_VALID
    clr M_MAP_DIRTY
    clr M_MODE
    jsr M_BITMAP_RANGE
    bcc M_ROLLBACK_DONE
M_ROLLBACK_UNCERTAIN:
    clr F_MOUNTED
M_ROLLBACK_DONE:
    ldd M_ERROR
    lbra F_HELPER_ERROR

; -------------------------------------------------------
;  Compare two complete raw directory entries.
; -------------------------------------------------------
; input:            X=first 128-byte entry; Y=second 128-byte entry
; output:           Z set when equal, clear on mismatch; X/Y advanced; W=remaining comparison
;                   count
; clobbers:         A, W, X, Y, CC
; -------------------------------------------------------
M_COMPARE_ENTRY:
    ldw #MLFS_DENTRY_SIZE
M_COMPARE_BYTE:
    lda ,x+
    cmpa ,y+
    bne M_COMPARE_RETURN
    decw
    bne M_COMPARE_BYTE
M_COMPARE_RETURN:
    rts

; -------------------------------------------------------
;  Require every bit of a validated existing extent to be allocated.
; -------------------------------------------------------
; input:            FS_DENTRY=validated entry; mounted bitmap state
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; M_OLD_* and
;                   M_ALLOC_*=existing extent; M_MODE=2
; clobbers:         D, W, X, CC
; -------------------------------------------------------
M_VERIFY_OLD:
    ldq FS_DENTRY+MLFS_DENTRY_EXTENTS
    stq M_OLD_START
    stq M_ALLOC_START
    ldq FS_DENTRY+MLFS_DENTRY_EXTENTS+4
    stq M_OLD_COUNT
    stq M_ALLOC_COUNT
    lda #2
    sta M_MODE
    jmp M_BITMAP_RANGE

; Zero a newly allocated run, including sectors beyond eventual EOF.
; -------------------------------------------------------
;  Zero every sector of a newly allocated run, including capacity beyond EOF.
; -------------------------------------------------------
; input:            M_ALLOC_START/M_ALLOC_COUNT=nonempty checked run; mounted partition state
; output:           D=0/C clear or D=FS_EIO/C set; FS_BUFFER cleared; F_CURRENT/F_END=sector
;                   cursors
; clobbers:         D, W, X, CC
; -------------------------------------------------------
M_ZERO_RUN:
    ldq M_ALLOC_START
    jsr F_BLOCK_LBA
    stq F_CURRENT
    ldq M_ALLOC_START
    addw M_ALLOC_COUNT+2
    adcb M_ALLOC_COUNT+1
    adca M_ALLOC_COUNT
    jsr F_BLOCK_LBA
    stq F_END
    ldx #FS_BUFFER
    ldw #512
M_ZERO_BUFFER:
    clr ,x+
    decw
    bne M_ZERO_BUFFER
M_ZERO_SECTOR:
    ldq F_CURRENT
    jsr F_WRITE_SECTOR
    bcs M_ZERO_RETURN
    jsr F_ADVANCE
    cmpd F_END
    bne M_ZERO_SECTOR
    cmpw F_END+2
    bne M_ZERO_SECTOR
    clrd
    andcc #$FE
M_ZERO_RETURN:
    rts

; -------------------------------------------------------
;  Create an empty file with a zero-filled contiguous allocation.
; -------------------------------------------------------
; input:            X=FsRequest; path=new name; offset=initial blocks (0 means 1); buffer/count
;                   ignored
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; valid
;                   request.done=0
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_CREATE:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    lda #MLFS_DENTRY_FLAG_FILE
    bra M_CREATE_START

; -------------------------------------------------------
;  Create an empty directory with a zero-filled contiguous allocation.
; -------------------------------------------------------
; input:            X=FsRequest; path=new name; offset=initial blocks (0 means 1); buffer/count
;                   ignored
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; valid
;                   request.done=0
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_MKDIR:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    lda #MLFS_DENTRY_FLAG_DIR
M_CREATE_START:
    sta M_TYPE
    jsr F_REQUEST_CHECK
    lbcs FS_API_RETURN
    jsr F_LOOKUP
    lbcc M_API_EXISTS
    jsr M_MISSING_LEAF
    lbcs FS_API_RETURN
    jsr M_FIND_SLOT
    lbcs FS_API_RETURN
    ldd M_ENTRY_OFF
    ldx #FS_BUFFER
    leax d,x
    ldy #FS_SAVED_ENTRY
    ldw #MLFS_DENTRY_SIZE
    tfm x+,y+
    ldx F_REQUEST
    ldq FS_REQ_OFFSET,x
    jsr F_Q_ZERO
    bne M_CREATE_SIZE
    ldq #1
M_CREATE_SIZE:
    stq M_WANTED
    jsr M_ALLOCATE
    lbcs FS_API_RETURN
    jsr M_ZERO_RUN
    bcs M_CREATE_ROLLBACK
    jsr M_CLEAR_ENTRY
    lda #1
    sta FS_DENTRY+MLFS_DENTRY_IN_USE
    sta FS_DENTRY+MLFS_DENTRY_EXTENTS_USED
    sta FS_DENTRY+MLFS_DENTRY_EXTENTS_TOTAL
    lda M_TYPE
    sta FS_DENTRY+MLFS_DENTRY_FLAGS
    ldq M_ALLOC_START
    stq FS_DENTRY+MLFS_DENTRY_EXTENTS
    ldq M_ALLOC_COUNT
    stq FS_DENTRY+MLFS_DENTRY_EXTENTS+4
    jsr M_SET_NAME
    inc M_PUBLISH
    jsr M_STORE_ENTRY
    bcs M_CREATE_ROLLBACK
    lbra FS_API_OK
M_CREATE_ROLLBACK:
    jsr M_ROLLBACK
    lbra FS_API_RETURN

; -------------------------------------------------------
;  Clear the private entry name and copy the current parsed component into it.
; -------------------------------------------------------
; input:            FS_NAME=validated NUL-terminated component
; output:           FS_DENTRY.name=zero-padded component
; clobbers:         D, X, Y, CC
; -------------------------------------------------------
M_SET_NAME:
    ldx #FS_DENTRY+MLFS_DENTRY_NAME
    ldb #MLFS_MAX_NAME
M_NAME_CLEAR:
    clr ,x+
    decb
    bne M_NAME_CLEAR
    ldx #FS_NAME
    ldy #FS_DENTRY+MLFS_DENTRY_NAME
M_NAME_COPY:
    lda ,x+
    sta ,y+
    bne M_NAME_COPY
    rts

; -------------------------------------------------------
;  Remove a file entry before releasing its contiguous allocation.
; -------------------------------------------------------
; input:            X=FsRequest; path=file; buffer/count/offset ignored
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; valid
;                   request.done=0
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_UNLINK:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    lda #MLFS_DENTRY_FLAG_FILE
    bra M_REMOVE_START

; -------------------------------------------------------
;  Remove an empty directory and release its allocation; reject root and nonempty directories.
; -------------------------------------------------------
; input:            X=FsRequest; path=directory; buffer/count/offset ignored
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; valid
;                   request.done=0
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_RMDIR:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    lda #MLFS_DENTRY_FLAG_DIR
M_REMOVE_START:
    sta M_TYPE
    jsr F_REQUEST_CHECK
    lbcs FS_API_RETURN
    jsr F_LOOKUP
    lbcs FS_API_RETURN
    tst FS_DENTRY+MLFS_DENTRY_NAME
    lbeq FS_API_INVALID            ; The synthetic root cannot be removed.
    lda FS_DENTRY+MLFS_DENTRY_FLAGS
    anda #3
    cmpa M_TYPE
    beq M_REMOVE_TYPE_OK
    cmpa #MLFS_DENTRY_FLAG_DIR
    lbeq FS_API_ISDIR
    lbra M_API_NOTDIR
M_REMOVE_TYPE_OK:
    jsr M_VERIFY_OLD
    lbcs FS_API_RETURN
    lda M_TYPE
    cmpa #MLFS_DENTRY_FLAG_DIR
    bne M_REMOVE_ENTRY
    jsr F_DIRECTORY
    lbcs FS_API_RETURN
    ldq F_DIR_LBA
    stq F_CURRENT
M_EMPTY_SECTOR:
    ldq F_CURRENT
    jsr F_READ_SECTOR
    lbcs FS_API_RETURN
    ldx #FS_BUFFER
M_EMPTY_SLOT:
    lda ,x
    cmpa #1
    lbeq M_API_NOTEMPTY
    tsta
    lbne FS_API_CORRUPT
    leax MLFS_DENTRY_SIZE,x
    cmpx #FS_BUFFER+512
    bne M_EMPTY_SLOT
    jsr F_ADVANCE
    cmpd F_DIR_END
    bne M_EMPTY_SECTOR
    cmpw F_DIR_END+2
    bne M_EMPTY_SECTOR
M_REMOVE_ENTRY:
    ; Remove the reference before releasing blocks. A failed release may leak
    ; space, but cannot leave an entry pointing to reused blocks.
    jsr M_ERASE_ENTRY
    lbcs FS_API_RETURN
    ldq M_OLD_START
    stq M_ALLOC_START
    ldq M_OLD_COUNT
    stq M_ALLOC_COUNT
    clr M_MODE
    jsr M_BITMAP_RANGE
    lbcs FS_API_RETURN
    lbra FS_API_OK

; Writes first reserve/prepare enough contiguous capacity, then zero any gap,
; then publish each successfully written chunk's size and transferred count.
; -------------------------------------------------------
;  Write file bytes, preparing contiguous growth and zeroing any gap beyond EOF.
; -------------------------------------------------------
; input:            X=FsRequest; path=file; buffer=source; count=bytes; offset=32-bit byte
;                   position
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure;
;                   request.done=confirmed bytes, including partial writes; offset unchanged
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_WRITE:
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
    ldd FS_REQ_COUNT,x
    lbeq FS_API_OK
    ldq FS_REQ_OFFSET,x
    addw FS_REQ_COUNT,x
    adcb #0
    adca #0
    lbcs FS_API_RANGE
    stq M_NEW_SIZE
    subw #1
    sbcb #0
    sbca #0
    stq F_TEMP
    ldb F_SHIFT
    addb #9
    jsr F_SHIFT_RIGHT
    ldq F_TEMP
    addw #1
    adcb #0
    adca #0
    stq M_WANTED
    jsr M_VERIFY_OLD
    lbcs FS_API_RETURN
    ldq M_OLD_COUNT
    cmpd M_WANTED
    bhi M_WRITE_CAPACITY
    blo M_WRITE_GROW
    cmpw M_WANTED+2
    bhs M_WRITE_CAPACITY
M_WRITE_GROW:
    jsr M_GROW_FILE
    lbcs FS_API_RETURN
M_WRITE_CAPACITY:
    ldx F_REQUEST
    ldq FS_REQ_OFFSET,x
    stq M_STOP
    ldq FS_DENTRY+MLFS_DENTRY_SIZE_BYTES
    cmpd M_STOP
    bhi M_WRITE_DATA
    blo M_WRITE_GAP
    cmpw M_STOP+2
    bhs M_WRITE_DATA
M_WRITE_GAP:
    stq M_POSITION
    lda #1
    sta M_ZERO
    jsr M_STREAM_WRITE
    lbcs FS_API_RETURN
M_WRITE_DATA:
    ldx F_REQUEST
    ldq FS_REQ_OFFSET,x
    stq M_POSITION
    ldq M_NEW_SIZE
    stq M_STOP
    ldd FS_REQ_BUFFER,x
    std F_DEST
    clr M_ZERO
    jsr M_STREAM_WRITE
    lbcs FS_API_RETURN
    lbra FS_API_OK

; -------------------------------------------------------
;  Grow file capacity by adjacent expansion or copy/publish/release relocation.
; -------------------------------------------------------
; input:            FS_DENTRY/M_ENTRY_*=resolved file; M_OLD_*=verified extent; M_WANTED>old
;                   block count
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; FS_DENTRY capacity
;                   updated on publication; logical size retained
; clobbers:         D, W, X, Y, CC
; -------------------------------------------------------
M_GROW_FILE:
    ldx #FS_DENTRY
    ldy #FS_SAVED_ENTRY
    ldw #MLFS_DENTRY_SIZE
    tfm x+,y+
    clr M_PUBLISH
    clr M_RELOCATED
    ldq M_OLD_START
    addw M_OLD_COUNT+2
    adcb M_OLD_COUNT+1
    adca M_OLD_COUNT
    stq M_ALLOC_START
    ldq M_WANTED
    subw M_OLD_COUNT+2
    sbcb M_OLD_COUNT+1
    sbca M_OLD_COUNT
    stq M_ALLOC_COUNT
    addw M_ALLOC_START+2
    adcb M_ALLOC_START+1
    adca M_ALLOC_START
    bcs M_GROW_RELOCATE
    cmpd F_BLOCKS
    bhi M_GROW_RELOCATE
    blo M_GROW_ADJACENT
    cmpw F_BLOCKS+2
    bhi M_GROW_RELOCATE
M_GROW_ADJACENT:
    lda #3
    sta M_MODE
    jsr M_BITMAP_RANGE
    bcc M_GROW_CLAIM
    cmpd #FS_ENOSPC
    bne M_GROW_RETURN
M_GROW_RELOCATE:
    inc M_RELOCATED
    jsr M_ALLOCATE
    bcs M_GROW_RETURN
    bra M_GROW_ZERO
M_GROW_CLAIM:
    lda #1
    sta M_MODE
    jsr M_BITMAP_RANGE
    bcs M_GROW_ROLLBACK
M_GROW_ZERO:
    jsr M_ZERO_RUN
    bcs M_GROW_ROLLBACK
    tst M_RELOCATED
    beq M_GROW_PUBLISH
    jsr M_COPY_FILE
    bcs M_GROW_ROLLBACK
    ldq M_ALLOC_START
    stq FS_DENTRY+MLFS_DENTRY_EXTENTS
M_GROW_PUBLISH:
    ldq M_WANTED
    stq FS_DENTRY+MLFS_DENTRY_EXTENTS+4
    inc M_PUBLISH
    jsr M_STORE_ENTRY
    bcs M_GROW_ROLLBACK
    tst M_RELOCATED
    beq M_GROW_OK
    ldq M_OLD_START
    stq M_ALLOC_START
    ldq M_OLD_COUNT
    stq M_ALLOC_COUNT
    clr M_MODE
    jsr M_BITMAP_RANGE
    bcs M_GROW_RETURN
M_GROW_OK:
    clrd
    andcc #$FE
M_GROW_RETURN:
    rts

; -------------------------------------------------------
;  Tail-call allocation rollback after a growth preparation or publication error.
; -------------------------------------------------------
; input:            D=original error; growth allocation and entry state required by M_ROLLBACK
; output:           D=original error/C set; allocation retained or released according to metadata
;                   readback
; clobbers:         D, W, X, Y, CC
; -------------------------------------------------------
M_GROW_ROLLBACK:
    jmp M_ROLLBACK

; -------------------------------------------------------
;  Copy existing file sectors to the prepared relocation extent, including the final sector
;  tail.
; -------------------------------------------------------
; input:            M_OLD_START=source; M_ALLOC_START=destination; FS_DENTRY.size=logical length
; output:           D=0/C clear or D=FS_EIO/C set; M_COPY_* and M_DATA_LBA=sector cursors
; clobbers:         D, W, X, CC
; -------------------------------------------------------
M_COPY_FILE:
    ldq M_OLD_START
    jsr F_BLOCK_LBA
    stq M_COPY_LBA
    ldq M_ALLOC_START
    jsr F_BLOCK_LBA
    stq M_DATA_LBA
    ldq FS_DENTRY+MLFS_DENTRY_SIZE_BYTES
    stq F_TEMP
    ldb #9
    jsr F_SHIFT_RIGHT
    ldd FS_DENTRY+MLFS_DENTRY_SIZE_BYTES+2
    andd #511
    beq M_COPY_COUNT
    ldq F_TEMP
    addw #1
    adcb #0
    adca #0
    stq F_TEMP
M_COPY_COUNT:
    ldq F_TEMP
    addw M_COPY_LBA+2
    adcb M_COPY_LBA+1
    adca M_COPY_LBA
    stq M_COPY_END
M_COPY_NEXT:
    ldq M_COPY_LBA
    cmpd M_COPY_END
    bne M_COPY_READ
    cmpw M_COPY_END+2
    beq M_GROW_OK
M_COPY_READ:
    jsr F_READ_SECTOR
    bcs M_GROW_RETURN
    ldq M_DATA_LBA
    jsr F_WRITE_SECTOR
    bcs M_GROW_RETURN
    ldq M_COPY_LBA
    addw #1
    adcb #0
    adca #0
    stq M_COPY_LBA
    ldq M_DATA_LBA
    addw #1
    adcb #0
    adca #0
    stq M_DATA_LBA
    bra M_COPY_NEXT

; -------------------------------------------------------
;  Stream gap zeroes or payload bytes, committing extended sizes before counting payload chunks.
; -------------------------------------------------------
; input:            FS_DENTRY=file; M_POSITION/M_STOP=byte range; M_ZERO!=0 for zeroes; otherwise
;                   F_DEST=source and F_REQUEST=request
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; M_POSITION
;                   advanced; payload mode updates file size and request.done
; clobbers:         D, W, X, Y, CC
; -------------------------------------------------------
M_STREAM_WRITE:
    ldq FS_DENTRY+MLFS_DENTRY_EXTENTS
    jsr F_BLOCK_LBA
    stq M_DATA_LBA
M_STREAM_NEXT:
    ldq M_POSITION
    cmpd M_STOP
    bne M_STREAM_POSITION
    cmpw M_STOP+2
    lbeq M_GROW_OK
M_STREAM_POSITION:
    stq F_TEMP
    ldd M_POSITION+2
    andd #511
    std F_SECTOR_OFF
    ldb #9
    jsr F_SHIFT_RIGHT
    ldq F_TEMP
    addw M_DATA_LBA+2
    adcb M_DATA_LBA+1
    adca M_DATA_LBA
    stq F_CURRENT
    jsr F_READ_SECTOR
    lbcs M_GROW_RETURN
    ldd #512
    subd F_SECTOR_OFF
    std M_CHUNK
    ldq M_STOP
    subw M_POSITION+2
    sbcb M_POSITION+1
    sbca M_POSITION
    tstd
    bne M_STREAM_CHUNK
    cmpw M_CHUNK
    bhs M_STREAM_CHUNK
    stw M_CHUNK
M_STREAM_CHUNK:
    ldd F_SECTOR_OFF
    ldy #FS_BUFFER
    leay d,y
    ldw M_CHUNK
    tst M_ZERO
    beq M_STREAM_COPY
M_STREAM_ZERO:
    clr ,y+
    decw
    bne M_STREAM_ZERO
    bra M_STREAM_STORE
M_STREAM_COPY:
    ldx F_DEST
    tfm x+,y+
    stx F_DEST
M_STREAM_STORE:
    ldq F_CURRENT
    jsr F_WRITE_SECTOR
    lbcs M_GROW_RETURN
    ldq M_POSITION
    addw M_CHUNK
    adcb #0
    adca #0
    stq M_POSITION
    tst M_ZERO
    lbne M_STREAM_NEXT
    cmpd FS_DENTRY+MLFS_DENTRY_SIZE_BYTES
    blo M_STREAM_DONE
    bhi M_STREAM_SIZE
    cmpw FS_DENTRY+MLFS_DENTRY_SIZE_BYTES+2
    bls M_STREAM_DONE
M_STREAM_SIZE:
    stq FS_DENTRY+MLFS_DENTRY_SIZE_BYTES
    jsr M_STORE_ENTRY
    lbcs M_GROW_RETURN
M_STREAM_DONE:
    ldx F_REQUEST
    ldd FS_REQ_DONE,x
    addd M_CHUNK
    std FS_REQ_DONE,x
    lbra M_STREAM_NEXT

; -------------------------------------------------------
;  Rename or move an entry without replacement; reject moves into its own descendants.
; -------------------------------------------------------
; input:            X=FsRequest; path=source; buffer=NUL-terminated destination; count/offset
;                   ignored
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; same resolved
;                   entry is a no-op; valid request.done=0
; clobbers:         D, W, CC; X, Y, U, DP are preserved
; -------------------------------------------------------
FS_RENAME:
    pshs x,y,u
    leau 8,s
    stu F_STACK_BASE
    jsr F_REQUEST_CHECK
    lbcs FS_API_RETURN
    jsr F_LOOKUP
    lbcs FS_API_RETURN
    tst FS_DENTRY+MLFS_DENTRY_NAME
    lbeq FS_API_INVALID
    lda FS_DENTRY+MLFS_DENTRY_FLAGS
    anda #3
    sta M_TYPE
    cmpa #MLFS_DENTRY_FLAG_DIR
    bne M_RENAME_SAVE
    inc M_FORBIDDEN
    ldq FS_DENTRY+MLFS_DENTRY_EXTENTS
    stq M_FORBID_START
M_RENAME_SAVE:
    ldx #FS_DENTRY
    ldy #FS_SAVED_ENTRY
    ldw #MLFS_DENTRY_SIZE
    tfm x+,y+
    ldq M_ENTRY_LBA
    stq M_SOURCE_LBA
    ldd M_ENTRY_OFF
    std M_SOURCE_OFF
    ldq F_DIR_LBA
    stq M_PARENT_LBA
    ldx F_REQUEST
    ldx FS_REQ_BUFFER,x
    jsr F_LOOKUP_AT_X
    bcs M_RENAME_MISSING
    ldq M_ENTRY_LBA
    cmpd M_SOURCE_LBA
    lbne M_API_EXISTS
    cmpw M_SOURCE_LBA+2
    lbne M_API_EXISTS
    ldd M_ENTRY_OFF
    cmpd M_SOURCE_OFF
    lbne M_API_EXISTS
    lbra FS_API_OK                ; Same resolved entry: a successful no-op.
M_RENAME_MISSING:
    jsr M_MISSING_LEAF
    lbcs FS_API_RETURN
    ldq F_DIR_LBA
    cmpd M_PARENT_LBA
    bne M_RENAME_MOVE
    cmpw M_PARENT_LBA+2
    bne M_RENAME_MOVE
    ldq M_SOURCE_LBA
    stq M_ENTRY_LBA
    ldd M_SOURCE_OFF
    std M_ENTRY_OFF
    jsr M_RESTORE_SOURCE
    jsr M_SET_NAME
    jsr M_STORE_ENTRY
    lbcs FS_API_RETURN
    lbra FS_API_OK
M_RENAME_MOVE:
    jsr M_FIND_SLOT
    lbcs FS_API_RETURN
    ldq M_ENTRY_LBA
    stq M_DEST_LBA
    ldd M_ENTRY_OFF
    std M_DEST_OFF
    jsr M_RESTORE_SOURCE
    jsr M_SET_NAME
    jsr M_STORE_ENTRY
    bcs M_RENAME_ROLLBACK
    ldq M_SOURCE_LBA
    stq M_ENTRY_LBA
    ldd M_SOURCE_OFF
    std M_ENTRY_OFF
    jsr M_ERASE_ENTRY
    bcs M_RENAME_CHECK_SOURCE
    lbra FS_API_OK
M_RENAME_CHECK_SOURCE:
    std M_ERROR
    ldq M_SOURCE_LBA
    jsr F_READ_SECTOR
    bcs M_RENAME_UNCERTAIN
    ldd M_SOURCE_OFF
    ldx #FS_BUFFER
    leax d,x
    tst ,x
    beq M_RENAME_REPORT           ; Source erased: retain destination reference.
    ldy #FS_SAVED_ENTRY
    jsr M_COMPARE_ENTRY
    bne M_RENAME_UNCERTAIN
    ldd M_ERROR
    bra M_RENAME_ROLLBACK
M_RENAME_UNCERTAIN:
    clr F_MOUNTED
M_RENAME_REPORT:
    ldd M_ERROR
    lbra FS_API_ERROR

; -------------------------------------------------------
;  Erase a new move destination after failure, invalidating the mount if rollback fails.
; -------------------------------------------------------
; input:            D=original move error; M_DEST_LBA/M_DEST_OFF=destination slot;
;                   S points to the saved public service frame
; output:           D=original error/C set; destination erased if possible; returns through the
;                   public service frame
; clobbers:         D, W, CC; X,Y,U restored
; -------------------------------------------------------
M_RENAME_ROLLBACK:
    std M_ERROR
    ldq M_DEST_LBA
    stq M_ENTRY_LBA
    ldd M_DEST_OFF
    std M_ENTRY_OFF
    jsr M_ERASE_ENTRY
    bcc M_RENAME_ROLLBACK_DONE
    clr F_MOUNTED
M_RENAME_ROLLBACK_DONE:
    ldd M_ERROR
    lbra FS_API_ERROR

; -------------------------------------------------------
;  Restore the saved source entry after resolving a move destination.
; -------------------------------------------------------
; input:            FS_SAVED_ENTRY=128-byte source entry
; output:           FS_DENTRY=source copy; W=0
; clobbers:         W, X, Y, CC
; -------------------------------------------------------
M_RESTORE_SOURCE:
    ldx #FS_SAVED_ENTRY
    ldy #FS_DENTRY
    ldw #MLFS_DENTRY_SIZE
    tfm x+,y+
    rts

; -------------------------------------------------------
;  Finish the public mutation service with FS_EEXIST.
; -------------------------------------------------------
; input:            S points to saved X,Y,U followed by the service return address
; output:           D=FS_EEXIST/C set; X,Y,U restored; returns to service caller
; clobbers:         D, CC
; -------------------------------------------------------
M_API_EXISTS:
    ldd #FS_EEXIST
    lbra FS_API_ERROR

; -------------------------------------------------------
;  Finish the public mutation service with FS_ENOTEMPTY.
; -------------------------------------------------------
; input:            S points to saved X,Y,U followed by the service return address
; output:           D=FS_ENOTEMPTY/C set; X,Y,U restored; returns to service caller
; clobbers:         D, CC
; -------------------------------------------------------
M_API_NOTEMPTY:
    ldd #FS_ENOTEMPTY
    lbra FS_API_ERROR

; -------------------------------------------------------
;  Finish the public mutation service with FS_ENOTDIR.
; -------------------------------------------------------
; input:            S points to saved X,Y,U followed by the service return address
; output:           D=FS_ENOTDIR/C set; X,Y,U restored; returns to service caller
; clobbers:         D, CC
; -------------------------------------------------------
M_API_NOTDIR:
    ldd #FS_ENOTDIR
    lbra FS_API_ERROR

; -------------------------------------------------------
;  Return FS_ENOSPC to the calling helper.
; -------------------------------------------------------
; input:            None
; output:           D=FS_ENOSPC; C set
; clobbers:         D, CC
; -------------------------------------------------------
M_NO_SPACE:
    ldd #FS_ENOSPC
    lbra F_HELPER_ERROR

; -------------------------------------------------------
;  Return FS_EIO to the calling helper.
; -------------------------------------------------------
; input:            None
; output:           D=FS_EIO; C set
; clobbers:         D, CC
; -------------------------------------------------------
M_IO_ERROR:
    ldd #FS_EIO
    lbra F_HELPER_ERROR
