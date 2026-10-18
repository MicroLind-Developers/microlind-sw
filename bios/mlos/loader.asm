; Read-only 512-byte MLPT/MLFS 1.1.0 root provider. Partition0 is the designated
; boot partition. Bounds use checked 32-bit arithmetic; whole extents are checked
; against geometry. A file must have one direct extent and no indirect blocks.
; This provider is restricted to bootstrap/image reads, never filesystem writes.

; Function: boot_open_root. Inputs: geometry from IDENTIFY. Outputs: validated
; boot partition/root/data ranges in BOOT_INFO; C0 or C1. Clobbers all; <=24 stack.
boot_open_root:
    ldq #0
    ldx #BOOT_BUFFER
    jsr boot_read
    lbcs bl_fail
    ldx #BOOT_BUFFER
    ldy #bl_pt_magic
    jsr boot_magic
    lbcs bl_fail
    ldd BOOT_BUFFER+7
    beq bl_fail
    cmpd #16
    bhi bl_fail
    lda BOOT_BUFFER+17
    cmpa #1
    bne bl_fail
    lda BOOT_BUFFER+18
    cmpa #9
    bne bl_fail
    ldq BOOT_BUFFER+9
    stq BOOT_PART
    tstd
    bne bl_part_nonzero
    cmpw #0
    beq bl_fail
bl_part_nonzero:
    ldq BOOT_BUFFER+13
    stq BOOT_BLOCKS
    tstd
    bne bl_blocks_nonzero
    cmpw #4
    blo bl_fail
bl_blocks_nonzero:
    addw BOOT_PART+2
    adcb BOOT_PART+1
    adca BOOT_PART
    bcs bl_fail
    cmpd BOOT_SECTORS
    bhi bl_fail
    blo bl_part_ok
    cmpw BOOT_SECTORS+2
    bhi bl_fail
bl_part_ok:
    ldq BOOT_PART
    ldx #BOOT_BUFFER
    jsr boot_read
    bcs bl_fail
    ldx #BOOT_BUFFER
    ldy #bl_fs_magic
    jsr boot_magic
    bcs bl_fail
    lda BOOT_BUFFER+7
    cmpa #9
    bne bl_fail
    ldq BOOT_BUFFER+9
    cmpd BOOT_BLOCKS
    bne bl_fail
    cmpw BOOT_BLOCKS+2
    bne bl_fail
    ldq BOOT_BUFFER+45
    stq BOOT_SUM
    ldq #0
    stq BOOT_BUFFER+45
    ldx #BOOT_BUFFER
    ldy #512
    jsr boot_checksum
    cmpd BOOT_SUM
    bne bl_fail
    cmpw BOOT_SUM+2
    bne bl_fail
    ldq #1
    stq BOOT_MIN
    ldx #BOOT_BUFFER+13
    jsr boot_range
    bcs bl_fail
    ldx #BOOT_BUFFER+21
    jsr boot_range
    bcs bl_fail
    ldq BOOT_FILE_LBA
    stq BOOT_ROOT
    ldq BOOT_FILE_END
    stq BOOT_ROOT_END
    ldq BOOT_MIN
    stq BOOT_DATA_MIN
    ; Bound root traversal independently of malformed disk size.
    ; Root count must fit <=64 sectors (high word zero).
    ldd BOOT_BUFFER+25
    bne bl_fail
    ldd BOOT_BUFFER+27
    cmpd #BOOT_DIR_LIMIT
    bhi bl_fail
    andcc #$FE
    rts
bl_fail:
    orcc #1
    rts
bl_pt_magic:
    fcc "MLPT"
    fcb 1,1,0
bl_fs_magic:
    fcc "MLFS"
    fcb 1,1,0

; Function: boot_magic. Inputs X/Y point at 7 bytes. Outputs C; clobbers D,X,Y.
; Serialized ROM; <=2 stack, bounded7. No ownership transfer.
boot_magic:
    ldb #7
bm_loop:
    lda ,x+
    cmpa ,y+
    bne bl_fail
    decb
    bne bm_loop
    andcc #$FE
    rts

; Function: boot_range. Inputs X=BE start/count, BOOT_MIN minimum relative start.
; Outputs validated absolute BOOT_FILE_LBA/END, advances minimum; C.
; Clobbers D,W; preserves X,Y,U; stack2. No data/metadata writes to disk.
boot_range:
    ldq ,x
    cmpd BOOT_MIN
    blo bl_fail
    bhi brr_start
    cmpw BOOT_MIN+2
    blo bl_fail
brr_start:
    ldd 4,x
    bne brr_nonzero
    ldd 6,x
    beq bl_fail
brr_nonzero:
    ldq ,x
    addw 6,x
    adcb 5,x
    adca 4,x
    bcs bl_fail
    cmpd BOOT_BLOCKS
    bhi bl_fail
    blo brr_end
    cmpw BOOT_BLOCKS+2
    bhi bl_fail
brr_end:
    stq BOOT_MIN
    addw BOOT_PART+2
    adcb BOOT_PART+1
    adca BOOT_PART
    bcs bl_fail
    stq BOOT_FILE_END
    ldq ,x
    addw BOOT_PART+2
    adcb BOOT_PART+1
    adca BOOT_PART
    bcs bl_fail
    stq BOOT_FILE_LBA
    andcc #$FE
    rts

; Function: boot_find. Inputs X=root name<=47 bytes, provider initialized.
; Outputs file sector range/size, C0; C1 on missing/corrupt. Clobbers all.
; Stack<=24; <=64 root-sector reads, validates the whole containing extent.
boot_find:
    stx BOOT_NAME
    ldq BOOT_ROOT
    stq BOOT_CURSOR
bf_sector:
    ldq BOOT_CURSOR
    cmpd BOOT_ROOT_END
    bne bf_read
    cmpw BOOT_ROOT_END+2
    beq bl_fail
bf_read:
    ldx #BOOT_BUFFER
    jsr boot_read
    bcs bl_fail
    ldq BOOT_CURSOR
    addw #1
    adcb #0
    adca #0
    stq BOOT_CURSOR
    ldu #BOOT_BUFFER
bf_entry:
    lda ,u
    cmpa #1
    bne bf_skip
    ldx BOOT_NAME
    leay 16,u
    ldb #48
bf_name:
    lda ,x+
    cmpa ,y+
    bne bf_skip
    tsta
    beq bf_found
    decb
    bne bf_name
bf_skip:
    leau 128,u
    cmpu #BOOT_BUFFER+512
    blo bf_entry
    bra bf_sector
bf_found:
    lda 1,u
    anda #3
    cmpa #2
    bne bl_fail
    lda 14,u
    cmpa #1
    bne bl_fail
    lda 15,u
    cmpa #1
    bhi bl_fail
    ldq 96,u
    tstd
    bne bl_fail
    cmpw #0
    bne bl_fail
    ldd 2,u
    bne bl_fail
    ldd 4,u
    beq bl_fail
    std BOOT_FILE_SIZE
    ldq BOOT_DATA_MIN
    stq BOOT_MIN
    leax 64,u
    jsr boot_range
    bcs bl_fail
    ; Any nonzero high extent length trivially fits a <=65535-byte file.
    ldd 68,u
    bne bf_ok
    ldd 70,u
    cmpd #128
    bhs bf_ok
    ; length<128: byte capacity is representable (max65024).
    aslb
    rola
    aslb
    rola
    aslb
    rola
    aslb
    rola
    aslb
    rola
    aslb
    rola
    aslb
    rola
    aslb
    rola
    aslb
    rola
    cmpd BOOT_FILE_SIZE
    blo bl_fail
bf_ok:
    andcc #$FE
    rts

; Function: boot_checksum. Inputs X=bytes,Y=count>0. Outputs Q=sum32, X advanced.
; Clobbers D,W,Y,CC. Stack4; O(count); no side effects except reading bytes.
boot_checksum:
    ldq #0
bc_sum:
    pshs d
    clra
    ldb ,x+
    addr d,w
    puls d
    adcb #0
    adca #0
    leay -1,y
    bne bc_sum
    rts

; Function: boot_kernel. Inputs validated provider. Outputs X=kernel entry,C0;
; C1 rejects without executing loaded bytes. Clobbers all; stack<=32.
boot_kernel:
    ldx #bk_name
    jsr boot_find
    bcs bl_fail
    ldd BOOT_FILE_SIZE
    cmpd #KERNEL_HEADER_SIZE+1
    blo bl_fail
    cmpd #$4000+KERNEL_HEADER_SIZE
    bhi bl_fail
    ldq BOOT_FILE_LBA
    ldx #BOOT_BUFFER
    jsr boot_read
    bcs bl_fail
    ldx #BOOT_BUFFER
    ldy #BOOT_HEADER
    ldw #20
    tfm x+,y+
    ldd BOOT_HEADER
    cmpd #$4D4C
    bne bl_fail
    ldd BOOT_HEADER+2
    cmpd #$4B31
    bne bl_fail
    ldd BOOT_HEADER+4
    cmpd #1
    bne bl_fail
    ldd BOOT_HEADER+6
    bne bl_fail
    ldd BOOT_HEADER+8
    bne bl_fail
    ldd BOOT_HEADER+14
    cmpd #$4000
    bne bl_fail
    ldd BOOT_HEADER+12
    beq bl_fail
    cmpd #$4000
    bhi bl_fail
    std BOOT_LEFT
    addd #20
    cmpd BOOT_FILE_SIZE
    bne bl_fail
    ldd BOOT_HEADER+10
    cmpd BOOT_LEFT
    bhs bl_fail
    clr BOOT_DEST
    clr BOOT_DEST+1
    ldx #BOOT_BUFFER+20
    ldy #492
bk_copy:
    lda ,x+
    ldu BOOT_DEST
    sta ,u+
    stu BOOT_DEST
    ldd BOOT_LEFT
    subd #1
    std BOOT_LEFT
    beq bk_verify
    leay -1,y
    bne bk_copy
    ldq BOOT_FILE_LBA
    addw #1
    adcb #0
    adca #0
    stq BOOT_FILE_LBA
    ldx #BOOT_BUFFER
    jsr boot_read
    bcs bl_fail
    ldx #BOOT_BUFFER
    ldy #512
    bra bk_copy
bk_verify:
    ldx #0
    ldy BOOT_HEADER+12
    jsr boot_checksum
    cmpd BOOT_HEADER+16
    bne bl_fail
    cmpw BOOT_HEADER+18
    bne bl_fail
    ldx BOOT_HEADER+10
    andcc #$FE
    rts
bk_name:
    fcn "mlos.bin"
