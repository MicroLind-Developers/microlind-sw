; Process module defaults: privileged native core, DP0, common stack, IRQ/FIRQ
; masked. No kernel stack suspension: waits retain process-owned copied state,
; and the outer return resumes a selected application's complete native frame.

; Function: process_init. Inputs cleared common RAM. Outputs frame reservations,
; empty bounded PCB table; clobbers D,X,Y. Stack<=6; nonblocking serialized boot.
process_init:
    jsr memory_init
    ; Unlike the S02 fixture no application has been allocated yet.
    clr FRAME_TABLE+3*FRAME_RECORD_SIZE
    clr FRAME_TABLE+3*FRAME_RECORD_SIZE+1
    clr FRAME_TABLE+3*FRAME_RECORD_SIZE+F_FLAGS
    lda #29
    sta FREE_COUNT
    ldd #1
    std NEXT_PID
    ldd #0
    std CURRENT_PID
    std CURRENT_PROC
    ldx #PROC_TABLE
pi_clear:
    clr ,x+
    cmpx #PROC_TABLE+PROC_COUNT*PROC_SIZE
    blo pi_clear
    ldx #CHANNEL_TABLE
pi_channels:
    clr ,x+
    cmpx #CHANNEL_TABLE+CHANNEL_COUNT*CHANNEL_SIZE
    blo pi_channels
    rts

; Function: process_spawn. Inputs X=trusted root filename, B=class0..2.
; Outputs D=PID/C0 only after full image validation/loading, or error/C1.
; Clobbers X,Y,U,W,V. Stack<96; IRQs masked, bounded image<=65535; no publish
; on failed admission. The restricted boot provider is the initial image source.
process_spawn:
    lda DEVICE_TABLE+D_ACTIVE
    cmpa #$FF
    lbne cio_again
    cmpb #3
    lbhs ps_invalid
    stb SCHED_TEMP+12
    ldy #ps_suffix
    jsr image_name_check
    lbcs ps_invalid
    tst BOOT_FEEDBACK_ACTIVE
    beq ps_feedback_done
    jsr ROM_BOOT_IMAGE
ps_feedback_done:
    ldu #PROC_TABLE
ps_slot:
    tst P_STATE,u
    beq ps_slot_found
    leau PROC_SIZE,u
    cmpu #PROC_TABLE+PROC_COUNT*PROC_SIZE
    blo ps_slot
    ldd #SYS_ENOMEM
    orcc #1
    rts
ps_slot_found:
    stu LOADER_PROC
    ldd CURRENT_PID
    std LOADER_PARENT
    ldd NEXT_PID
    cmpd #$7FFF
    lbhs ps_no_memory
    std LOADER_PID
    std P_PID,u
    addd #1
    std NEXT_PID
    ; Clear unpublished metadata, preserving its newly assigned unique PID.
    pshs x
    tfr u,x
    ldy #PROC_SIZE
ps_zero:
    clr ,x+
    leay -1,y
    bne ps_zero
    puls x
    ldd LOADER_PID
    std P_PID,u
    ldd LOADER_PARENT
    std P_PARENT,u
    ldy CURRENT_PROC
    beq ps_root_session
    ldd P_JOB_SCOPE,y
    std P_JOB_SCOPE,u
    ldd P_SESSION,y
    bra ps_session
ps_root_session:
    ldd LOADER_PID
ps_session:
    std P_SESSION,u
    lda SCHED_TEMP+12
    sta P_CLASS,u
    lda #2
    sta P_MAP,u
    sta P_MAP+1,u
    sta P_MAP+2,u
    jsr ROM_FILE_FIND
    lbcs ps_bad_image
    ldq BOOT_FILE_LBA
    stq LOADER_LBA
    ldd BOOT_FILE_SIZE
    std LOADER_LEFT
    cmpd #APP_HEADER_SIZE+APP_SEGMENT_SIZE
    lblo ps_bad_image
    lda MMU2
    sta LOADER_SAVED_MAP
    ldq LOADER_LBA
    ldx #BOOT_BUFFER
    jsr ROM_CF_READ
    lbcs ps_io_error
    ; Header/table fit the first sector; every reserved field is checked.
    ldx #BOOT_BUFFER
    ldy #LOADER_HEADER
    ldw #APP_HEADER_SIZE+APP_SEGMENT_MAX*APP_SEGMENT_SIZE
    tfm x+,y+
    ldd LOADER_HEADER
    cmpd #$4D4C
    lbne ps_bad_image
    ldd LOADER_HEADER+2
    cmpd #$5831
    lbne ps_bad_image
    ldd LOADER_HEADER+4
    cmpd #1
    lbne ps_bad_image
    ldd LOADER_HEADER+28
    cmpd #ABI_VERSION
    lbne ps_bad_image
    ldd LOADER_HEADER+30
    lbne ps_bad_image
    ldd LOADER_HEADER+22
    lbne ps_bad_image
    tst LOADER_HEADER+17
    lbne ps_bad_image
    lda LOADER_HEADER+14
    cmpa #1
    beq ps_mask_ok
    cmpa #3
    beq ps_mask_ok
    cmpa #7
    lbne ps_bad_image
ps_mask_ok:
    lda LOADER_HEADER+15
    bita #$F8
    lbne ps_bad_image
    bita LOADER_HEADER+14
    lbne ps_bad_image
    lda LOADER_HEADER+16
    beq ps_bad_image
    cmpa #6
    lbhi ps_bad_image
    ldb #8
    mul
    addd #32
    cmpd LOADER_HEADER+6
    lbne ps_bad_image
    addd LOADER_HEADER+20
    lbcs ps_bad_image
    cmpd LOADER_LEFT
    lbne ps_bad_image
    ldd LOADER_HEADER+18
    cmpd #128
    lbne ps_bad_image
    ldd LOADER_HEADER+12
    cmpd #128
    lblo ps_bad_image
    ldd LOADER_HEADER+10
    cmpd #$BF80
    lbhi ps_bad_image
    bitb #1
    lbne ps_bad_image
    subd LOADER_HEADER+12
    lbcs ps_bad_image
    ; Stack range must be resident and must not overlap any segment.
    tfr d,x
    ldd LOADER_HEADER+12
    addd #128
    lbcs ps_bad_image
    jsr image_resident_range
    lbcs ps_bad_image
    ldd #0
    std LOADER_LAST_END
    std LOADER_PAYLOAD
    clr LOADER_ENTRY
    ldx #LOADER_HEADER+32
    ldb LOADER_HEADER+16
ps_check_segment:
    pshs b,x
    ldd ,x
    cmpd LOADER_LAST_END
    lblo ps_check_pop_bad
    ldd 2,x
    addd 4,x
    lbcs ps_check_pop_bad
    lbeq ps_check_pop_bad
    ldy ,x
    pshs x
    tfr y,x
    jsr image_resident_range
    puls x
    lbcs ps_check_pop_bad
    ldd ,x
    addd 2,x
    addd 4,x
    std LOADER_LAST_END
    ; Check no live segment overlaps the fixed stack reservation.
    pshs d
    ldd LOADER_HEADER+10
    addd #128
    cmpd ,x
    puls d
    bls ps_check_entry
ps_check_stack_start:
    ldd LOADER_HEADER+10
    subd LOADER_HEADER+12
    cmpd LOADER_LAST_END
    blo ps_check_pop_bad
ps_check_entry:
    ldd LOADER_HEADER+8
    cmpd ,x
    blo ps_check_offset
    pshs d
    ldd ,x
    addd 2,x
    cmpd ,s++
    bls ps_check_offset
    inc LOADER_ENTRY
ps_check_offset:
    ldd 6,x
    cmpd LOADER_PAYLOAD
    bne ps_check_pop_bad
    addd 2,x
    bcs ps_check_pop_bad
    std LOADER_PAYLOAD
    puls b,x
    leax 8,x
    decb
    bne ps_check_segment
    tst LOADER_ENTRY
    lbeq ps_bad_image
    ldd LOADER_PAYLOAD
    cmpd LOADER_HEADER+20
    lbne ps_bad_image
    ; Acquire every resident bank in a single transaction under the child's PID.
    ldd LOADER_PID
    std CURRENT_PID
    lda LOADER_HEADER+14
    ldb #1
    cmpa #1
    beq ps_allocate
    incb
    cmpa #3
    beq ps_allocate
    incb
ps_allocate:
    jsr frame_alloc_many
    lbcs ps_restore_error
    ldu LOADER_PROC
    ldx #ALLOC_LIST
    clr SCHED_TEMP+13
ps_set_maps:
    ldb SCHED_TEMP+13
    lda b,x
    pshs d,x
    jsr frame_address
    ldb #F_RESIDENT
    stb F_FLAGS,x
    puls d,x
    leau P_MAP,u
    sta b,u
    leau -P_MAP,u
    leau P_ROLE,u
    lda #ROLE_RESIDENT
    sta b,u
    leau -P_ROLE,u
    inc SCHED_TEMP+13
    ldb SCHED_TEMP+13
    cmpb ALLOC_COUNT
    blo ps_set_maps
    ; Copy validated segment descriptors to kernel-owned process metadata.
    ldx #LOADER_HEADER+32
    leay P_SEGMENTS,u
    lda LOADER_HEADER+16
    sta P_SEGC,u
    ldb #8
    mul
    tfr d,w
    tfm x+,y+
    lda LOADER_HEADER+15
    sta P_RESOURCES,u
    ; Image checksum includes the entire header/table with checksum zeroed.
    ldq LOADER_HEADER+24
    stq BOOT_SUM
    ldq #0
    stq LOADER_HEADER+24
    ldx #LOADER_HEADER
    ldy LOADER_HEADER+6
    jsr image_sum
    stq LOADER_SUM
    ldd LOADER_HEADER+6
    std LOADER_OFFSET
    ldd LOADER_HEADER+20
    std LOADER_LEFT
    ldx #LOADER_HEADER+32
    stx LOADER_SEG
    tst LOADER_MODE
    lbne ps_async_start
ps_load_segment:
    ldx LOADER_SEG
    ldd ,x
    std LOADER_DEST
    ldd 2,x
    std LOADER_COUNT
    beq ps_bss
ps_load_byte:
    tst LOADER_ACTIVE
    beq ps_read_one
    tst LOADER_BUDGET
    beq ps_pause_data
ps_read_one:
    jsr image_data_run
    lbcs ps_unwind
    ldd LOADER_COUNT
    bne ps_load_byte
ps_bss:
    ldx LOADER_SEG
    ldd 4,x
    std LOADER_COUNT
    beq ps_next_segment
ps_zero_byte:
    tst LOADER_ACTIVE
    beq ps_zero_one
    tst LOADER_BUDGET
    beq ps_pause_bss
ps_zero_one:
    jsr image_zero_run
    ldd LOADER_COUNT
    bne ps_zero_byte
ps_next_segment:
    ldx LOADER_SEG
    leax 8,x
    stx LOADER_SEG
    ldd LOADER_HEADER+6
    addd #LOADER_HEADER
    pshs d
    cmpx ,s++
    blo ps_load_segment
    ldq LOADER_SUM
    cmpd BOOT_SUM
    lbne ps_unwind
    cmpw BOOT_SUM+2
    lbne ps_unwind
    ldu LOADER_PROC
    ldd LOADER_HEADER+10
    subd #N_SIZE
    std P_CONTEXT+R_S,u
    ldd LOADER_HEADER+8
    std P_CONTEXT+N_PC,u
    lda #$C0
    sta P_CONTEXT+N_CC,u
    jsr arguments_install
    ldu LOADER_PROC
    lda #'/'
    sta P_CWD,u
    clr P_CWD+1,u
    tst LOADER_ACTIVE
    beq ps_inherit_current
    ldx LOADER_PARENT_PROC
    bra ps_inherit_parent
ps_inherit_current:
    ldx CURRENT_PROC
ps_inherit_parent:
    beq ps_no_inherit
    ldd P_CWD_GENERATION,x
    std P_CWD_GENERATION,u
    ldd P_CWD_VOLUME,x
    std P_CWD_VOLUME,u
    ldd P_SERVICE,x
    std P_SERVICE,u
    leay P_CWD,u
    leax P_CWD,x
    ldw #64
    tfm x+,y+
ps_no_inherit:
    ldd LOADER_HEADER+10
    std P_STACK_TOP,u
    ldd LOADER_HEADER+12
    std P_STACK_SIZE,u
    lda #MLOS_QUANTUM_TICKS
    sta P_QUANTUM,u
    lda #PS_READY
    sta P_STATE,u                 ; publish last
    lda LOADER_SAVED_MAP
    sta MMU2
    ldd LOADER_PARENT
    std CURRENT_PID
    lda #3
    sta LOADER_PHASE
    ldd LOADER_PID
    andcc #$FE
    rts
ps_async_start:
    clr LOADER_CANCEL
    ldu LOADER_PROC
    lda #PS_LOADING
    sta P_STATE,u
    ldu CURRENT_PROC
    stu LOADER_PARENT_PROC
    lda #3
    sta P_FLAGS,u
    lda #PS_WAIT
    sta P_STATE,u
    lda #1
    sta LOADER_ACTIVE
    clr LOADER_PHASE
    inc SCHED_PENDING
    ldd #0
    andcc #$FE
    rts
ps_pause_data:
    lda #1
    sta LOADER_PHASE
    rts
ps_pause_bss:
    lda #2
    sta LOADER_PHASE
    rts

ps_check_pop_bad:
    puls b,x
ps_bad_image:
    ldd #SYS_EINVAL
    bra ps_restore_error
ps_io_error:
    ldd #SYS_EIO
ps_restore_error:
    pshs d
    lda #3
    sta LOADER_PHASE
    ldd LOADER_PARENT
    std CURRENT_PID
    puls d
    orcc #1
    rts
ps_unwind:
    ldu LOADER_PROC
    ldb #3
    leay P_MAP,u
ps_unwind_frame:
    lda ,y+
    cmpa #3
    blo ps_unwind_next
    pshs b
    jsr frame_address
    clr F_OWNER,x
    clr F_OWNER+1,x
    clr F_FLAGS,x
    inc FREE_COUNT
    puls b
ps_unwind_next:
    decb
    bne ps_unwind_frame
    lda LOADER_SAVED_MAP
    sta MMU2
    bra ps_bad_image
ps_invalid:
    ldd #SYS_EINVAL
    orcc #1
    rts
ps_no_memory:
    ldd #SYS_ENOMEM
    orcc #1
    rts

; Function: image_resident_range. Inputs X=start,D=count>0; header resident mask.
; Outputs C; preserves X,Y,U; clobbers D. Stack<=8; validates before allocation.
image_resident_range:
    pshs x,y,u
    leau d,x
    cmpu #$C000
    bhi irr_bad
    cmpu ,s                        ; saved X is at0 after PSHS X,Y,U
    bls irr_bad
    leau -1,u
    tfr x,d
    lsra
    lsra
    lsra
    lsra
    lsra
    lsra
    tfr a,b
    lda #1
irr_shift:
    tstb
    beq irr_mask
    lsla
    decb
    bra irr_shift
irr_mask:
    bita LOADER_HEADER+14
    beq irr_bad
    tfr u,d
    lsra
    lsra
    lsra
    lsra
    lsra
    lsra
    tfr a,b
    lda #1
irr_end_shift:
    tstb
    beq irr_end_mask
    lsla
    decb
    bra irr_end_shift
irr_end_mask:
    bita LOADER_HEADER+14
    beq irr_bad
    puls x,y,u
    andcc #$FE
    rts
irr_bad:
    puls x,y,u
    orcc #1
    rts

; Function: image_sum. Inputs X,Y bytes/count>0. Outputs Q=sum32; clobbers X,Y,CC.
; Stack<=4, bounded; no calls/device access.
image_sum:
    ldq #0
is_loop:
    pshs d
    clra
    ldb ,x+
    addr d,w
    puls d
    adcb #0
    adca #0
    leay -1,y
    bne is_loop
    rts

LOADER_RUN equ $C5B6             ; u16, serialized loader scratch
LOADER_ZERO equ $C5B8            ; run mode, plus fixed zero source
LOADER_CANCEL equ $C5BC          ; pending suspended foreground spawn only
LOADER_ZERO_BYTE equ $C5B9
; Function: image_data_run / image_zero_run. Inputs validated loader segment,
; count>0, budget>0 when asynchronous. Outputs bounded span installed, cursors
; advanced, C0; data returns C1 on truncated input/CF error before destination
; changes. Clobbers all; stack<=24 including ROM read. At most128 bytes, split
; at sector/window/quota boundaries; maps only MMU2, restored by loader caller.
; No retained user pointers; checksum remains the MLX1 additive32 encoding.
image_data_run:
    clr LOADER_ZERO
    ldd LOADER_OFFSET
    cmpd #512
    blo ir_size
    ldq LOADER_LBA
    addw #1
    adcb #0
    adca #0
    stq LOADER_LBA
    ldx #BOOT_BUFFER
    jsr ROM_CF_READ
    lbcs ib_fail
    ldd #0
    std LOADER_OFFSET
    bra ir_size
image_zero_run:
    lda #1
    sta LOADER_ZERO
ir_size:
    ldd LOADER_COUNT
    cmpd #128
    bls ir_quota
    ldd #128
ir_quota:
    tst LOADER_ACTIVE
    beq ir_window
    cmpb LOADER_BUDGET
    bls ir_window
    ldb LOADER_BUDGET
ir_window:
    std LOADER_RUN
    ldd LOADER_DEST
    anda #$3F
    pshs d
    ldd #$4000
    subd ,s++
    cmpd LOADER_RUN
    bhs ir_source
    std LOADER_RUN
ir_source:
    tst LOADER_ZERO
    bne ir_map
    ldd #512
    subd LOADER_OFFSET
    cmpd LOADER_RUN
    bhs ir_left
    std LOADER_RUN
ir_left:
    ldd LOADER_LEFT
    cmpd LOADER_RUN
    lblo ib_fail
    ldx #BOOT_BUFFER
    ldd LOADER_OFFSET
    leax d,x
    ldy LOADER_RUN
    clrw
ir_sum:
    clra
    ldb ,x+
    addr d,w
    leay -1,y
    bne ir_sum
    ; A run <=128 has sum<=32640, so a16-bit subtotal cannot overflow.
    tfr w,d
    addd LOADER_SUM+2
    std LOADER_SUM+2
    ldd LOADER_SUM
    adcb #0
    adca #0
    std LOADER_SUM
ir_map:
    ldu LOADER_PROC
    ldd LOADER_DEST
    lsra
    lsra
    lsra
    lsra
    lsra
    lsra
    leax P_MAP,u
    lda a,x
    sta MMU2
    ldd LOADER_DEST
    anda #$3F
    ora #$80
    tfr d,y
    ldw LOADER_RUN
    tst LOADER_ZERO
    beq ir_copy
    clr LOADER_ZERO_BYTE
    ldx #LOADER_ZERO_BYTE
    tfm x,y+
    bra ir_advance
ir_copy:
    ldx #BOOT_BUFFER
    ldd LOADER_OFFSET
    leax d,x
    tfm x+,y+
    ldd LOADER_OFFSET
    addd LOADER_RUN
    std LOADER_OFFSET
    ldd LOADER_LEFT
    subd LOADER_RUN
    std LOADER_LEFT
ir_advance:
    tst LOADER_ACTIVE
    beq ir_count
    ldb LOADER_BUDGET
    subb LOADER_RUN+1
    stb LOADER_BUDGET
ir_count:
    ldd LOADER_DEST
    addd LOADER_RUN
    std LOADER_DEST
    ldd LOADER_COUNT
    subd LOADER_RUN
    std LOADER_COUNT
    andcc #$FE
    rts

; Function: image_byte. Inputs loader cursor. Outputs A=next initialized byte/C0
; or C1 EOF/I/O; clobbers D,W,X,Y. Stack<=24; bounded sector read on refill.
image_byte:
    ldd LOADER_LEFT
    beq ib_fail
    ldd LOADER_OFFSET
    cmpd #512
    blo ib_available
    ldq LOADER_LBA
    addw #1
    adcb #0
    adca #0
    stq LOADER_LBA
    ldx #BOOT_BUFFER
    jsr ROM_CF_READ
    bcs ib_fail
    ldd #0
    std LOADER_OFFSET
ib_available:
    ldx #BOOT_BUFFER
    ldd LOADER_OFFSET
    lda d,x
    pshs a
    ldq LOADER_SUM
    pshs d
    clra
    ldb 2,s
    addr d,w
    puls d
    adcb #0
    adca #0
    stq LOADER_SUM
    ldd LOADER_OFFSET
    addd #1
    std LOADER_OFFSET
    ldd LOADER_LEFT
    subd #1
    std LOADER_LEFT
    puls a
    andcc #$FE
    rts
ib_fail:
    orcc #1
    rts

; Function: image_store. Inputs A=byte, LOADER_DEST process logical address.
; Outputs destination advanced. Clobbers D,X,Y,U; preserves W,V; stack<=6.
; Map through MMU2; never changes code or common mappings.
image_store:
    pshs a
    ldu LOADER_PROC
    ldd LOADER_DEST
    lsra
    lsra
    lsra
    lsra
    lsra
    lsra
    leax P_MAP,u
    lda a,x
    sta MMU2
    ldd LOADER_DEST
    anda #$3F
    ora #$80
    tfr d,x
    puls a
    sta ,x
    ldd LOADER_DEST
    addd #1
    std LOADER_DEST
    rts

; Function: loader_progress. Inputs one admitted private image transaction.
; Outputs at most MLOS_LOADER_QUOTA initialized/BSS bytes per safe point, then publishes child
; and wakes parent with final PID/error. No suspended kernel stack or borrowed
; pointer. Clobbers all; stack<=112; other processes/drives progress meanwhile.
loader_progress:
    tst LOADER_ACTIVE
    beq lp_done
    lda DEVICE_TABLE+D_ACTIVE
    cmpa #$FF
    bne lp_done
    lda LOADER_MODE
    cmpa #2
    lbeq module_progress
    ldd CURRENT_PID
    pshs d
    lda MMU2
    pshs a
    ldd LOADER_PARENT
    std CURRENT_PID
    tst LOADER_CANCEL
    bne lp_cancel_request
    ldu LOADER_PARENT_PROC
    lda P_STATE,u
    cmpa #PS_WAIT
    bne lp_cancel
    ldu LOADER_PROC
    lda P_STATE,u
    cmpa #PS_LOADING
    bne lp_cancel
    lda #MLOS_LOADER_QUOTA
    sta LOADER_BUDGET
    lda LOADER_PHASE
    beq lp_begin
    cmpa #1
    beq lp_data
    jsr ps_zero_byte
    bra lp_after
lp_begin:
    jsr ps_load_segment
    bra lp_after
lp_data:
    jsr ps_load_byte
lp_after:
    pshs cc,d
    lda LOADER_PHASE
    cmpa #3
    bne lp_paused
lp_final:
    puls cc,d
    pshs cc,d
    ldu LOADER_PARENT_PROC
    std P_CONTEXT+N_A,u
    bcs lp_failure
    lda LOADER_FLAGS+1
    bita #1
    beq lp_success
    ldx LOADER_PROC
    lda #PS_SUSPENDED
    sta P_STATE,x
lp_success:
    lda P_CONTEXT+N_CC,u
    anda #$FE
    bra lp_result
lp_failure:
    ldx LOADER_PROC
    clr P_STATE,x
    lda P_CONTEXT+N_CC,u
    ora #1
lp_result:
    sta P_CONTEXT+N_CC,u
    lda #PS_READY
    sta P_STATE,u
    clr LOADER_ACTIVE
    clr LOADER_MODE
lp_paused:
    leas 3,s
lp_restore:
    puls a
    sta MMU2
    puls d
    std CURRENT_PID
lp_done:
    rts
lp_cancel_request:
    jsr ps_unwind
    ldd #SYS_ECANCELLED
    orcc #1
    bra lp_after
lp_cancel:
    jsr ps_unwind
    ldu LOADER_PROC
    clr P_STATE,u
    clr LOADER_ACTIVE
    clr LOADER_MODE
    bra lp_restore

; Function: image_name_check. Inputs trusted X=basename,Y=4-byte suffix.
; Outputs C0 for an immutable installed image name, C1 otherwise; preserves X.
; Clobbers D,Y,CC; stack<=4; at most48 source bytes and4 suffix bytes.
image_name_check:
    pshs x
    ldb #48
inc_name:
    lda ,x+
    beq inc_suffix
    cmpa #'/'
    beq inc_bad
    decb
    bne inc_name
    bra inc_bad
inc_suffix:
    tfr x,d
    subd ,s
    cmpd #5
    bls inc_bad
    leax -5,x
    ldb #4
inc_compare:
    lda ,x+
    cmpa ,y+
    bne inc_bad
    decb
    bne inc_compare
    puls x
    andcc #$FE
    rts
inc_bad:
    puls x
    orcc #1
    rts
ps_suffix: fcn ".mlx"
