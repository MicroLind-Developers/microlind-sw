; Scheduler defaults: privileged core/DP0/common, IRQ/FIRQ masked unless the
; explicit idle SYNC waits for a timer/serial event. All context/map changes
; occur as one transaction. One thread per PCB; configured capacity8.

; Function: runtime_tick. Inputs U=current ROM record, R_PRIV marks nested entry.
; Outputs tick/wakeup accounting; selects an app only at an outer return.
; Clobbers D,W,X,Y; U restored/ENTRY_BASE. Stack<=48 plus native bridges.
runtime_tick:
    pshs u
    ldq TICKS
    addw #1
    adcb #0
    adca #0
    stq TICKS
    tst BOOT_FEEDBACK_ACTIVE
    beq tick_feedback_done
    ldd TICKS+2
    jsr ROM_BOOT_PULSE
tick_feedback_done:
    puls u
    tst R_PRIV,u
    bne tick_nested
    ldx CURRENT_PROC
    beq tick_nested
    dec P_QUANTUM,x
    bne tick_nested
    inc SCHED_PENDING
    jmp runtime_finish
tick_nested:
    rts

; Function: runtime_finish. Inputs U=outer canonical application record.
; Outputs selected/current record, PID/maps; core returns through fixed ROM.
; Clobbers all scratch; stack<=64; bounded transactions, no user pointer retained.
runtime_finish:
    ldu #ENTRY_BASE
    ldx CURRENT_PROC
    beq rf_pick
    lda P_STATE,x
    cmpa #PS_RUNNING
    bne rf_save
    tst SCHED_PENDING
    beq rf_unchanged
rf_save:
    leay P_CONTEXT,x
    ldw #ENTRY_SIZE
    pshs x
    tfr u,x
    tfm x+,y+
    puls x
    ldd PROCESS_MAP
    std P_MAP,x
    lda PROCESS_MAP+2
    sta P_MAP+2,x
    ldd PROCESS_ROLE
    std P_ROLE,x
    lda PROCESS_ROLE+2
    sta P_ROLE+2,x
    lda P_STATE,x
    cmpa #PS_RUNNING
    bne rf_pick
    tst SCHED_PENDING
    beq rf_current
    lda #PS_READY
    sta P_STATE,x
rf_pick:
    jsr tty_progress
    jsr driver_progress
    jsr loader_progress
    jsr process_cleanup
    jsr process_wake
    jsr scheduler_select
    bcc rf_selected
    ; Every application is blocked. Kernel/common remain mapped and privileged;
    ; a nested timer IRQ wakes candidates without abandoning this kernel stack.
    andcc #$EF
    sync
    orcc #$50
    bra rf_pick
rf_selected:
    stx CURRENT_PROC
    lda #PS_RUNNING
    sta P_STATE,x
    lda #MLOS_QUANTUM_TICKS
    sta P_QUANTUM,x
rf_current:
    clr SCHED_PENDING
    ldd P_PID,x
    std CURRENT_PID
    ldd P_MAP,x
    std PROCESS_MAP
    lda P_MAP+2,x
    sta PROCESS_MAP+2
    ldd P_ROLE,x
    std PROCESS_ROLE
    lda P_ROLE+2,x
    sta PROCESS_ROLE+2
    leax P_CONTEXT,x
    ldy #ENTRY_BASE
    ldw #ENTRY_SIZE
    tfm x+,y+
    ldu #ENTRY_BASE
    clr R_REASON,u
    clr R_PRIV,u
    rts

rf_unchanged:
    rts

; Function: scheduler_select. Inputs READY PCBs/cursors. Outputs X=selected/C0
; or C1 empty. Clobbers D,Y,U. Stack<=8; <=7*8 probes; weights4:2:1, RR per class.
scheduler_select:
    ; Empty runnable sets need one PCB pass, not all seven weighted phases.
    ldx #PROC_TABLE
ss_any:
    lda P_STATE,x
    cmpa #PS_READY
    beq ss_nonempty
    leax PROC_SIZE,x
    cmpx #PROC_TABLE+PROC_COUNT*PROC_SIZE
    blo ss_any
    orcc #1
    rts
ss_nonempty:
    lda #SCHED_WEIGHT_COUNT
    sta SCHED_TEMP
ss_phase:
    ldb SCHED_PHASE
    ldx #ss_weights
    lda b,x
    sta SCHED_TEMP+1
    inc SCHED_PHASE
    lda SCHED_PHASE
    cmpa #SCHED_WEIGHT_COUNT
    blo ss_cursor
    clr SCHED_PHASE
ss_cursor:
    ldb SCHED_TEMP+1
    ldx #SCHED_CURSOR
    lda b,x
    sta SCHED_TEMP+2
    lda #PROC_COUNT
    sta SCHED_TEMP+3
ss_process:
    inc SCHED_TEMP+2
    lda SCHED_TEMP+2
    cmpa #PROC_COUNT
    blo ss_index
    clra
    sta SCHED_TEMP+2
ss_index:
    clrb
    addd #PROC_TABLE
    tfr d,x
    lda P_STATE,x
    cmpa #PS_READY
    bne ss_next
    lda P_CLASS,x
    cmpa SCHED_TEMP+1
    bne ss_next
    pshs x
    ldx #SCHED_CURSOR
    ldb SCHED_TEMP+1
    lda SCHED_TEMP+2
    sta b,x
    puls x
    andcc #$FE
    rts
ss_next:
    dec SCHED_TEMP+3
    bne ss_process
    dec SCHED_TEMP
    bne ss_phase
    orcc #1
    rts
ss_weights:
    include "schedule_phases.inc"
SCHED_WEIGHT_COUNT equ *-ss_weights

; Function: process_wake. Inputs monotonic u32 ticks and wait records.
; Outputs sleeping/exited-child waiters READY with final result; clobbers all
; scratch except U. Stack<=12; serialized <=8*8 records, no lost check/sleep gap.
process_wake:
    pshs u
    jsr ipc_wake
    ldx #PROC_TABLE
pw_scan:
    lda P_STATE,x
    cmpa #PS_SLEEP
    beq pw_deadline
    cmpa #PS_WAIT
    bne pw_next
    lda P_FLAGS,x
    cmpa #4
    beq pw_input
    cmpa #1
    bne pw_next
    pshs x
    ldd P_PENDING,x
    jsr process_lookup
    puls x
    bcs pw_next
    lda P_STATE,u
    cmpa #PS_ZOMBIE
    bne pw_next
    ldd P_EXIT,u
    std P_CONTEXT+N_A,x
    lda P_CONTEXT+N_CC,x
    anda #$FE
    sta P_CONTEXT+N_CC,x
    clr P_STATE,u
    bra pw_ready
pw_input:
    ldd P_PID,x
    cmpd T_FG
    bne pw_input_owner
    jsr tty_input_ready
    tstd
    beq pw_next
    ldd #0
    bra pw_input_result
pw_input_owner:
    ldd #SYS_EOWNER
pw_input_result:
    std P_CONTEXT+N_A,x
    lda P_CONTEXT+N_CC,x
    anda #$FE
    tst P_CONTEXT+N_A,x
    bpl pw_input_flags
    ora #1
pw_input_flags:
    sta P_CONTEXT+N_CC,x
    bra pw_ready
pw_deadline:
    ldq TICKS
    subw P_WAKE+2,x
    sbcb P_WAKE+1,x
    sbca P_WAKE,x
    bita #$80
    bne pw_next
pw_ready:
    lda #PS_READY
    sta P_STATE,x
pw_next:
    leax PROC_SIZE,x
    cmpx #PROC_TABLE+PROC_COUNT*PROC_SIZE
    blo pw_scan
    puls u
    rts

; Function: process_lookup. Inputs D=unique nonreused session PID. Outputs U=PCB,
; C0 or EHANDLE/C1. Clobbers CC. Preserves X,Y,W,V. Stack2; <=8 probes.
process_lookup:
    ldu #PROC_TABLE
pl_scan:
    tst P_STATE,u
    beq pl_next
    tim #8,P_STATE,u
    bne pl_next
    cmpd P_PID,u
    beq pl_found
pl_next:
    leau PROC_SIZE,u
    cmpu #PROC_TABLE+PROC_COUNT*PROC_SIZE
    blo pl_scan
    ldd #SYS_EHANDLE
    orcc #1
    rts
pl_found:
    andcc #$FE
    rts

; Function: process_exit. Inputs D=exit code, current PID/PCB. Outputs ZOMBIE
; after handles/maps/frames are withdrawn; clobbers all. Stack<=24; bounded.
; Pinned/referenced resources delay cleanup in DYING state (progress hook).
process_exit:
    pshs d
    ldd CURRENT_PID
    cmpd #1
    lbeq rpt_core
    jsr lifecycle_exit
    ldd CURRENT_PID
    cmpd T_FG
    bne pe_tty_done
    ldd T_SHELL
    std T_FG
    lda T_SAVED_MODE
    sta T_MODE
    ldd #0
    std T_EDIT_COUNT
    std T_LINE_LEFT
    clr T_LINE_EOF
pe_tty_done:
    puls d
    ldu CURRENT_PROC
    std P_EXIT,u
    inc CLEANUP_PENDING
    lda #PS_DYING
    sta P_STATE,u
    jsr heap_release_owner
    jsr ipc_release_owner
    jsr driver_release_owner
    lda #2
    sta MMU1
    sta MMU2
    ldx #HANDLE_TABLE
pe_handle:
    ldd H_OWNER,x
    cmpd CURRENT_PID
    bne pe_handle_next
    tst H_REFS,x
    bne pe_deferred
    tst H_PINS,x
    bne pe_deferred
    clr H_LIVE,x
    clr H_OWNER,x
    clr H_OWNER+1,x
pe_handle_next:
    leax HANDLE_RECORD_SIZE,x
    cmpx #HANDLE_TABLE+HANDLE_COUNT*HANDLE_RECORD_SIZE
    blo pe_handle
    ldx #FRAME_TABLE+3*FRAME_RECORD_SIZE
pe_frame:
    ldd F_OWNER,x
    cmpd CURRENT_PID
    bne pe_frame_next
    tst F_REFS,x
    bne pe_deferred
    tst F_PINS,x
    bne pe_deferred
    clr F_OWNER,x
    clr F_OWNER+1,x
    clr F_FLAGS,x
    inc FREE_COUNT
pe_frame_next:
    leax FRAME_RECORD_SIZE,x
    cmpx #FRAME_TABLE+FRAME_COUNT*FRAME_RECORD_SIZE
    blo pe_frame
    ldu CURRENT_PROC
    lda #2
    sta P_MAP,u
    sta P_MAP+1,u
    sta P_MAP+2,u
    clr P_ROLE,u
    clr P_ROLE+1,u
    clr P_ROLE+2,u
    lda #PS_ZOMBIE
    sta P_STATE,u
    tst P_ORPHAN,u
    beq pe_deferred
    clr P_STATE,u
pe_deferred:
    inc SCHED_PENDING
    ldd #0
    andcc #$FE
    rts

; Function: runtime_trap. Inputs U=ROM trap bridge with pre-entry privilege.
; Outputs terminate application and select survivor, or emergency halt for core.
; Clobbers all; no application trap resumes. Stack<64, no filesystem dependency.
runtime_trap:
    tst R_PRIV,u
    bne rpt_core
    ldd CURRENT_PID
    cmpd #1
    beq rpt_core
    inc TRAP_COUNT+1
    lda #'T'
    jsr ROM_PUTC
    ldd #128
    jsr process_exit
    jmp runtime_finish
rpt_core:
    lda #$31
    jmp ROM_PANIC

; Function: process_cleanup. Inputs DYING records. Outputs retries only bounded
; reference-safe cleanup; clobbers all. Preserves current PID/PCB across retries.
CLEANUP_PENDING equ $C5BB
process_cleanup:
    tst CLEANUP_PENDING
    beq pclean_done
    clr CLEANUP_PENDING
    ldy #PROC_TABLE
pclean_scan:
    lda P_STATE,y
    cmpa #PS_DYING
    bne pclean_next
    pshs y
    ldd CURRENT_PID
    pshs d
    ldd CURRENT_PROC
    pshs d
    sty CURRENT_PROC
    ldd P_PID,y
    std CURRENT_PID
    ldd P_EXIT,y
    jsr process_exit
    puls d
    std CURRENT_PROC
    puls d
    std CURRENT_PID
    puls y
    lda P_STATE,y
    cmpa #PS_DYING
    bne pclean_next
    inc CLEANUP_PENDING
pclean_next:
    leay PROC_SIZE,y
    cmpy #PROC_TABLE+PROC_COUNT*PROC_SIZE
    blo pclean_scan
pclean_done:
    rts

; Function: lifecycle_exit. Inputs dying CURRENT_PID. Outputs parents adopted,
; filesystem service group or terminal session withdrawn before cleanup. Clobbers
; D,X,Y,U; stack<=4. Marking is bounded; callbacks/requests settle in DYING.
lifecycle_exit:
    ldd CURRENT_PID
    cmpd FS_OWNER
    bne lx_tty
    clr FS_OWNER
    clr FS_OWNER+1
    lda #1
    sta FS_FAILED
    clr FS_VOLUME_FLAGS
lx_tty:
    ldd CURRENT_PID
    cmpd T_SHELL
    bne lx_scan_start
    clr T_SHELL
    clr T_SHELL+1
    clr T_FG
    clr T_FG+1
    clr T_MODE
lx_scan_start:
    ldu #PROC_TABLE
lx_scan:
    tst P_STATE,u
    beq lx_next
    ldd P_PID,u
    cmpd CURRENT_PID
    beq lx_next
    ldd P_SERVICE,u
    beq lx_session
    cmpd CURRENT_PID
    beq lx_end_scope
lx_session:
    ldd P_JOB_SCOPE,u
    beq lx_session_id
    cmpd CURRENT_PID
    beq lx_end_scope
lx_session_id:
    ldd P_SESSION,u
    cmpd CURRENT_PID
    beq lx_end_scope
    bra lx_parent
lx_end_scope:
    lda P_STATE,u
    cmpa #PS_ZOMBIE
    beq lx_parent
    inc CLEANUP_PENDING
    lda #PS_DYING
    sta P_STATE,u
    ldd #130
    std P_EXIT,u
lx_parent:
    ldd P_PARENT,u
    cmpd CURRENT_PID
    bne lx_next
    ldd #1
    std P_PARENT,u
    lda #1
    sta P_ORPHAN,u
    lda P_STATE,u
    cmpa #PS_ZOMBIE
    bne lx_next
    clr P_STATE,u
lx_next:
    leau PROC_SIZE,u
    cmpu #PROC_TABLE+PROC_COUNT*PROC_SIZE
    blo lx_scan
    rts
