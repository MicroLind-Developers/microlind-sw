; Worker-private structural validation for the admitted single-extent MLFS
; profile. At most65535 blocks,8 directory levels,8192-byte reached bitmap.
V_BITS equ $1000
V_STACK equ $3000
V_DEPTH equ $0330
V_TOTAL equ $0332
V_CURSOR equ $0334
V_LIMIT equ $0336
V_MASK equ $0338
V_ZERO equ $0339
V_OFFSET equ $033A
V_BITMAP_INDEX equ $033C
V_DIRTY equ $033E
V_READONLY equ $033F
V_SAVED_STATUS equ $0340
V_BYTES equ $0342
V_TAIL_MASK equ $0344
V_CACHE_VALID equ $0345
V_CACHE_LBA equ $0348
V_DUP_LBA equ $034C
V_DUP_SLOT equ $0350

; Function: volume_validate. Inputs mounted F_* state. Outputs0/C0 if all
; reachable extents are disjoint, valid and allocated exactly as on disk; else
; FS_ECORRUPT/C1. Dirty but consistent volumes remain readable only. Clobbers
; all; stack<=32 plus asynchronous wrapper. No disk writes, bounded DFS state.
volume_validate:
    clr V_ZERO
    clr V_DEPTH
    clr V_CACHE_VALID
    clr V_READONLY
    ldx #V_ZERO
    ldy #V_BITS
    ldw #8192
    tfm x,y+
    tst F_SHIFT
    lbne vv_bad
    ldd F_BLOCKS
    lbne vv_bad
    ldd F_BLOCKS+2
    lbeq vv_bad
    std V_TOTAL
    ldd #0
    std V_CURSOR
    ldd F_DATA_MIN
    lbne vv_bad
    ldd F_DATA_MIN+2
    std V_LIMIT
    jsr vv_mark
    lbcs vv_return
    ldq F_ROOT_LBA
    stq V_STACK
    stq V_STACK+12
    ldq F_ROOT_END
    stq V_STACK+4
    clr V_STACK+8
vv_directory:
    ldb V_DEPTH
    lda #16
    mul
    ldu #V_STACK
    leau d,u
    lda 8,u
    cmpa #4
    blo vv_slot
    clr 8,u
    ldq ,u
    addw #1
    adcb #0
    adca #0
    stq ,u
vv_slot:
    ldq ,u
    cmpd 4,u
    bne vv_sector
    cmpw 6,u
    bne vv_sector
    tst V_DEPTH
    beq vv_bitmap_start
    dec V_DEPTH
    bra vv_directory
vv_sector:
    tst V_CACHE_VALID
    beq vv_read_dir
    cmpd V_CACHE_LBA
    bne vv_read_dir
    cmpw V_CACHE_LBA+2
    beq vv_cached_dir
vv_read_dir:
    stq V_CACHE_LBA
    jsr F_READ_SECTOR
    lbcs vv_return
    lda #1
    sta V_CACHE_VALID
vv_cached_dir:
    ldb 8,u
    lda #128
    mul
    ldx #FS_BUFFER
    leax d,x
    inc 8,u
    tst ,x
    beq vv_directory
    lda ,x
    cmpa #1
    lbne vv_bad
    ldy #FS_DENTRY
    ldw #128
    tfm x+,y+
    jsr F_VALIDATE_ENTRY
    lbcs vv_bad
    jsr vv_names
    lbcs vv_return
    ldd FS_DENTRY+64
    lbne vv_bad
    ldd FS_DENTRY+66
    std V_CURSOR
    ldd FS_DENTRY+68
    lbne vv_bad
    ldd V_CURSOR
    addd FS_DENTRY+70
    lbcs vv_bad
    cmpd V_TOTAL
    lbhi vv_bad
    std V_LIMIT
    jsr vv_mark
    lbcs vv_return
    lda FS_DENTRY+1
    bita #1
    beq vv_directory
    inc V_DEPTH
    lda V_DEPTH
    cmpa #8
    lbhs vv_bad
    ldb #16
    mul
    ldu #V_STACK
    leau d,u
    ldq F_CURRENT
    stq ,u
    stq 12,u
    ldq F_END
    stq 4,u
    clr 8,u
    bra vv_directory
vv_bitmap_start:
    ldd V_TOTAL
    andb #7
    lda #$FF
    tstb
    beq vv_tail_ready
    lda #1
vv_tail_shift:
    lsla
    decb
    bne vv_tail_shift
    deca
vv_tail_ready:
    sta V_TAIL_MASK
    ldd V_TOTAL
    lsrd
    lsrd
    lsrd
    std V_BYTES
    ldb V_TOTAL+1
    andb #7
    beq vv_bytes_ready
    ldd V_BYTES
    addd #1
    std V_BYTES
vv_bytes_ready:
    ldd #0
    std V_BITMAP_INDEX
vv_bitmap_sector:
    clrd
    ldw V_BITMAP_INDEX
    addw F_BITMAP_LBA+2
    adcb F_BITMAP_LBA+1
    adca F_BITMAP_LBA
    jsr F_READ_SECTOR
    bcs vv_return
    ldd V_BITMAP_INDEX
    lsld
    lsld
    lsld
    lsld
    lsld
    lsld
    lsld
    lsld
    lsld
    addd #V_BITS
    tfr d,y
    ldx #FS_BUFFER
    ldw #512
vv_compare:
    ldd V_BYTES
    cmpd #1
    beq vv_compare_last
    lda ,x+
    cmpa ,y+
    bne vv_bad
    ldd V_BYTES
    subd #1
    std V_BYTES
    decw
    bne vv_compare
    inc V_BITMAP_INDEX+1
    lbra vv_bitmap_sector
vv_compare_last:
    lda ,x
    eora ,y
    anda V_TAIL_MASK
    bne vv_bad
vv_bitmap_done:
    ldq F_PART
    jsr F_READ_SECTOR
    bcs vv_return
    lda FS_BUFFER+8
    sta V_READONLY
    anda #$FE
    bne vv_bad
    ldd #0
    andcc #$FE
vv_return:
    rts
vv_bad:
    ldd #FS_ECORRUPT
    orcc #1
    rts

; Function: vv_mark. Inputs relative [V_CURSOR,V_LIMIT), expected map. Outputs
; C0 or corrupt duplicate/C1; clobbers D,X. No I/O; <=65535 iterations per run.
vv_mark:
    ldd V_CURSOR
    cmpd V_LIMIT
    bhs vv_mark_done
    andb #7
    lda #1
vv_shift:
    tstb
    beq vv_mark_bit
    lsla
    decb
    bra vv_shift
vv_mark_bit:
    sta V_MASK
    ldd V_CURSOR
    lsrd
    lsrd
    lsrd
    ldx #V_BITS
    leax d,x
    lda ,x
    bita V_MASK
    bne vv_bad
    ora V_MASK
    sta ,x
    ldd V_CURSOR
    addd #1
    std V_CURSOR
    bra vv_mark
vv_mark_done:
    andcc #$FE
    rts

; Function: volume_state. Inputs A=0 clean/1 dirty. Outputs persisted state with
; repaired checksum/C0, or I/O/C1. Clobbers all. PIO completion is the selected
; write boundary; no claim of an ATA cache flush or atomic multi-sector update.
volume_state:
    sta V_DIRTY
    ldq F_PART
    jsr F_READ_SECTOR
    bcs vs_return
    lda V_DIRTY
    sta FS_BUFFER+8
    ldq #0
    stq FS_BUFFER+45
    ldx #FS_BUFFER
    ldy #512
    jsr vs_sum
    stq FS_BUFFER+45
    ldq F_PART
    jsr F_WRITE_SECTOR
vs_return:
    rts
; Function: vs_sum. Inputs X=sector,Y=512. Outputs sum32 Q; clobbers X,Y,D,W.
; Stack<=6; same byte checksum as host formatter and ROM.
vs_sum:
    ldq #0
vs_sum_next:
    pshs d
    clra
    ldb ,x+
    addr d,w
    puls d
    adcb #0
    adca #0
    leay -1,y
    bne vs_sum_next
    rts

; Function: vv_names. Inputs validated FS_DENTRY,U=directory walk record.
; Outputs C0 or malformed/duplicate name/C1; clobbers D,W,X,Y. Stack<=24 with
; PIO wait. Compares previous entries in this directory without retaining
; unbounded names; current entry remains in its separate private buffer.
vv_names:
    ldx #FS_DENTRY+MLFS_DENTRY_NAME
    lda ,x
    cmpa #'.'
    bne vn_scan_name
    tst 1,x
    lbeq vv_bad
    lda 1,x
    cmpa #'.'
    bne vn_scan_name
    tst 2,x
    lbeq vv_bad
vn_scan_name:
    lda ,x+
    beq vn_start
    cmpa #'/'
    lbeq vv_bad
    bra vn_scan_name
vn_start:
    ldq 12,u
    stq V_DUP_LBA
vn_sector:
    clr V_DUP_SLOT
    ldq V_DUP_LBA
    cmpd ,u
    bne vn_read
    cmpw 2,u
    bne vn_read
    lda 8,u
    cmpa #1
    beq vn_ok
vn_read:
    clr V_CACHE_VALID
    ldq V_DUP_LBA
    jsr F_READ_SECTOR
    lbcs vv_return
vn_slot:
    ldq V_DUP_LBA
    cmpd ,u
    bne vn_compare
    cmpw 2,u
    bne vn_compare
    lda V_DUP_SLOT
    inca
    cmpa 8,u
    bhs vn_ok
vn_compare:
    lda #128
    ldb V_DUP_SLOT
    mul
    ldx #FS_BUFFER
    leax d,x
    tst ,x
    beq vn_next
    leax MLFS_DENTRY_NAME,x
    ldy #FS_DENTRY+MLFS_DENTRY_NAME
    ldb #48
vn_bytes:
    lda ,x+
    cmpa ,y+
    bne vn_next
    tsta
    lbeq vv_bad
    decb
    bne vn_bytes
vn_next:
    inc V_DUP_SLOT
    lda V_DUP_SLOT
    cmpa #4
    blo vn_slot
    ldq V_DUP_LBA
    addw #1
    adcb #0
    adca #0
    stq V_DUP_LBA
    bra vn_sector
vn_ok:
    ldd #0
    andcc #$FE
    rts
