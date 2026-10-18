; Heap module defaults: serialized native core/DP0; IRQ/FIRQ masked, common fixed.
; Whole allocations have stable logical addresses; frames need not be adjacent.
; Search excludes every image segment, stack/argv, resource window and live block.

; Function: heap_alloc. Inputs D=bytes1..32768. Outputs D=stable pointer/C0 or
; ENOMEM/EINVAL/C1 with no published allocation; clobbers X,Y,U,W,V. Stack<=32.
; Metadata32 records; first-fit candidate jumps over whole conflicting intervals.
heap_alloc:
    tstd
    lbeq rx_invalid
    cmpd #$8000
    lbhi rx_invalid
    addd #1
    andb #$FE
    std HEAP_LENGTH
    ldx #HEAP_TABLE
ha_slot:
    tst HP_LIVE,x
    beq ha_slot_found
    leax HEAP_SIZE,x
    cmpx #HEAP_TABLE+HEAP_COUNT*HEAP_SIZE
    blo ha_slot
    jmp ps_no_memory
ha_slot_found:
    stx HEAP_SLOT
    ldd #$0400
    std HEAP_CANDIDATE
ha_search:
    ldd HEAP_CANDIDATE
    addd HEAP_LENGTH
    lbcs ps_no_memory
    cmpd #$C000
    lbhi ps_no_memory
    std HEAP_END
    ldu CURRENT_PROC
    ldx #0
    ldb P_SEGC,u
    stb HEAP_LIMIT
    leay P_SEGMENTS,u
ha_segment:
    ldd 2,y
    addd 4,y
    addd ,y
    tfr d,x
    ldd ,y
    jsr heap_overlap              ; D=start, X=end; candidate advances on conflict.
    bcs ha_search
    leay 8,y
    dec HEAP_LIMIT
    bne ha_segment
    ldd P_STACK_TOP,u
    subd P_STACK_SIZE,u
    ldx P_STACK_TOP,u
    leax 128,x
    jsr heap_overlap
    bcs ha_search
    ldy #HEAP_TABLE
ha_blocks:
    tst HP_LIVE,y
    beq ha_block_next
    ldd HP_PID,y
    cmpd CURRENT_PID
    bne ha_block_next
    ldd HP_ADDRESS,y
    addd HP_LENGTH,y
    tfr d,x
    ldd HP_ADDRESS,y
    jsr heap_overlap
    bcs ha_search
ha_block_next:
    leay HEAP_SIZE,y
    cmpy #HEAP_TABLE+HEAP_COUNT*HEAP_SIZE
    blo ha_blocks
    ; Exclude swappable or executable-reserved resource windows.
    clr HEAP_NEW_COUNT
    ldd HEAP_CANDIDATE
    jsr heap_window_index
    stb HEAP_WINDOW
    ldd HEAP_END
    subd #1
    jsr heap_window_index
    stb HEAP_LIMIT
ha_windows:
    ldb HEAP_WINDOW
    ldx #PROCESS_ROLE
    lda b,x
    cmpa #ROLE_RESOURCE
    beq ha_skip_window
    lda #1
    ldb HEAP_WINDOW
ha_resource_bit:
    tstb
    beq ha_resource_test
    lsla
    decb
    bra ha_resource_bit
ha_resource_test:
    bita P_RESOURCES,u
    bne ha_skip_window
    ldb HEAP_WINDOW
    ldx #PROCESS_ROLE
    tst b,x
    bne ha_window_live
    inc HEAP_NEW_COUNT
ha_window_live:
    inc HEAP_WINDOW
    lda HEAP_WINDOW
    cmpa HEAP_LIMIT
    bls ha_windows
    ldb HEAP_NEW_COUNT
    beq ha_admitted
    jsr frame_alloc_many
    lbcs ha_return
ha_admitted:
    clr HEAP_INDEX
    ldd HEAP_CANDIDATE
    jsr heap_window_index
    stb HEAP_WINDOW
ha_commit_window:
    ldb HEAP_WINDOW
    ldx #PROCESS_ROLE
    tst b,x
    bne ha_reference
    lda #ROLE_RESIDENT
    sta b,x
    ldx #ALLOC_LIST
    ldb HEAP_INDEX
    lda b,x
    inc HEAP_INDEX
    ldx #PROCESS_MAP
    ldb HEAP_WINDOW
    sta b,x
    jsr frame_address
    lda #F_RESIDENT+F_HEAP
    sta F_FLAGS,x
ha_reference:
    ldx #PROCESS_MAP
    ldb HEAP_WINDOW
    lda b,x
    jsr frame_address
    inc F_REFS,x
    inc HEAP_WINDOW
    lda HEAP_WINDOW
    cmpa HEAP_LIMIT
    bls ha_commit_window
    ldx HEAP_SLOT
    ldd CURRENT_PID
    std HP_PID,x
    ldd HEAP_CANDIDATE
    std HP_ADDRESS,x
    ldd HEAP_LENGTH
    std HP_LENGTH,x
    inc HP_LIVE,x
    ldd HEAP_CANDIDATE
    andcc #$FE
ha_return:
    rts
ha_skip_window:
    lda HEAP_WINDOW
    inca
    lsla
    lsla
    lsla
    lsla
    lsla
    lsla
    clrb
    std HEAP_CANDIDATE
    bra ha_search

; Function: heap_overlap. Inputs D=start,X=exclusive end of reserved range.
; Outputs C1 and advances candidate if conflict, C0 disjoint. Clobbers D,CC;
; preserves X,Y,U,W,V. Stack4; constant time, no mutation except candidate.
heap_overlap:
    cmpd HEAP_END
    bhs ho_clear
    cmpx HEAP_CANDIDATE
    bls ho_clear
    tfr x,d
    addd #1
    andb #$FE
    std HEAP_CANDIDATE
    orcc #1
    rts
ho_clear:
    andcc #$FE
    rts
; Function: heap_window_index. Inputs D=logical address. Outputs B=window0..2.
; Clobbers A,CC; preserves X,Y,U,W,V. Stack2, six shifts.
heap_window_index:
    lsra
    lsra
    lsra
    lsra
    lsra
    lsra
    tfr a,b
    rts

; Function: heap_free. Inputs D=exact live pointer owned by current process.
; Outputs0/C0 or EINVAL/C1; clobbers all. Empty heap-only frames are revoked,
; parked, then released; pins keep an empty frame reserved for deferred reclaim.
heap_free:
    std HEAP_CANDIDATE
    ldy #HEAP_TABLE
hf_find:
    tst HP_LIVE,y
    beq hf_next
    ldd HP_PID,y
    cmpd CURRENT_PID
    bne hf_next
    ldd HP_ADDRESS,y
    cmpd HEAP_CANDIDATE
    beq hf_found
hf_next:
    leay HEAP_SIZE,y
    cmpy #HEAP_TABLE+HEAP_COUNT*HEAP_SIZE
    blo hf_find
    jmp rx_invalid
hf_found:
    clr HP_LIVE,y
    ldd HP_ADDRESS,y
    addd HP_LENGTH,y
    subd #1
    jsr heap_window_index
    stb HEAP_LIMIT
    ldd HEAP_CANDIDATE
    jsr heap_window_index
    stb HEAP_WINDOW
hf_frame:
    ldb HEAP_WINDOW
    ldx #PROCESS_MAP
    lda b,x
    jsr frame_address
    dec F_REFS,x
    bne hf_window_next
    tst F_PINS,x
    bne hf_window_next
    lda F_FLAGS,x
    bita #F_HEAP
    beq hf_window_next
    ldb HEAP_WINDOW
    ldy #PROCESS_MAP
    lda #2
    sta b,y
    ldy #PROCESS_ROLE
    clr b,y
    ; Only window1/2 can be mapped temporarily here; core window0 stays live.
    tstb
    beq hf_release
    ldy #MMU0
    sta b,y
hf_release:
    clr F_OWNER,x
    clr F_OWNER+1,x
    clr F_FLAGS,x
    inc FREE_COUNT
hf_window_next:
    inc HEAP_WINDOW
    lda HEAP_WINDOW
    cmpa HEAP_LIMIT
    bls hf_frame
    ldd #0
    andcc #$FE
    rts

; Function: heap_release_owner. Inputs CURRENT_PID/PROC of a dying process.
; Outputs withdraws its live allocations and frame live-object references.
; Clobbers D,X,Y,U; stack<=12. Pins/other frame references remain intact.
heap_release_owner:
    ldy #HEAP_TABLE
hro_scan:
    tst HP_LIVE,y
    beq hro_next
    ldd HP_PID,y
    cmpd CURRENT_PID
    bne hro_next
    clr HP_LIVE,y
    ldd HP_ADDRESS,y
    addd HP_LENGTH,y
    subd #1
    jsr heap_window_index
    stb HEAP_LIMIT
    ldd HP_ADDRESS,y
    jsr heap_window_index
    stb HEAP_WINDOW
hro_window:
    ldu CURRENT_PROC
    leax P_MAP,u
    ldb HEAP_WINDOW
    lda b,x
    jsr frame_address
    dec F_REFS,x
    inc HEAP_WINDOW
    lda HEAP_WINDOW
    cmpa HEAP_LIMIT
    bls hro_window
hro_next:
    leay HEAP_SIZE,y
    cmpy #HEAP_TABLE+HEAP_COUNT*HEAP_SIZE
    blo hro_scan
    rts
