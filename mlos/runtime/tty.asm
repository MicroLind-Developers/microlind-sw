; TTY provider defaults: privileged core/DP0, bounded nonblocking progress.
; Interactive UART A, output-only fixed-size log records on UART B. Typeahead
; stays in the provider FIFO across foreground handoff; per-process SPSC stdout.

; Function: tty_standard. Inputs none. Outputs standard endpoints installed/C0
; or rollback error/C1. Clobbers all; stack<=48; two whole channel frames charged.
tty_standard:
    ldu CURRENT_PROC
    ldd P_FDS+2,u
    bne ts_existing
    ldd CURRENT_PID
    std TTY_OWNER
    ldd #$FFFE
    std PARAM_BUFFER
    ldd #256
    std PARAM_BUFFER+2
    clr PARAM_BUFFER+4
    clr PARAM_BUFFER+5
    jsr channel_new
    bcs ts_return
    std TTY_TX_HANDLE
    ldd IPC_RX
    std TTY_RX_HANDLE
    ldy IPC_SLOT
    lda #2
    sta C_FLAGS,y
    ldu CURRENT_PROC
    ldd CURRENT_PID
    std C_TTY_OWNER,y
    ldd P_PARENT,u
    std C_TTY_PARENT,y
    ldd T_SHELL
    beq ts_new_session
    ldd P_SESSION,u
    bra ts_session_known
ts_new_session:
    ldd CURRENT_PID
ts_session_known:
    std C_TTY_SESSION,y
    ldd TTY_OWNER
    std PARAM_BUFFER
    ldd #$FFFE
    std CURRENT_PID
    jsr channel_new
    pshs cc,d
    ldd TTY_OWNER
    std CURRENT_PID
    puls cc,d
    bcs ts_undo
    ldy IPC_SLOT
    lda #4
    sta C_FLAGS,y
    ldu CURRENT_PROC
    ldd IPC_RX
    std P_FDS,u
    ldd TTY_TX_HANDLE
    std P_FDS+2,u
    ldd #$FFFF
    std P_FDS+4,u
ts_existing:
    ldd #0
    andcc #$FE
ts_return:
    rts
ts_undo:
    ldd TTY_TX_HANDLE
    jsr channel_close
    ldd #$FFFE
    std CURRENT_PID
    ldd TTY_RX_HANDLE
    jsr channel_close
    ldd TTY_OWNER
    std CURRENT_PID
    jmp ps_no_memory

; Function: tty_write. Inputs legacy SYS_WRITE copied source/count. Outputs
; copied stdout stream count/C0 or EAGAIN/error. Clobbers all; no UART busy wait.
tty_write:
    ldu CURRENT_PROC
    ldd P_FDS+2,u
    beq tw_diagnostic
    ldd PARAM_BUFFER
    std PARAM_BUFFER+2
    ldd TTY_LAST
    std PARAM_BUFFER+4
    ldd P_FDS+2,u
    std PARAM_BUFFER
    ldd #0
    std PARAM_BUFFER+6
    std PARAM_BUFFER+8
    jmp channel_send
tw_diagnostic:
    jmp sc_write

; Function: tty_getc. Inputs none, current foreground owner. Outputs Latin1 byte
; or EAGAIN/EOWNER/ECANCELLED. Clobbers D,X,U; stack<=4. No input draining by background.
tty_getc:
    ldd CURRENT_PID
    cmpd T_FG
    lbne rx_owner
    tst T_INTERRUPTED
    beq tg_read
    clr T_INTERRUPTED
    ldd #SYS_ECANCELLED
    orcc #1
    rts
tg_read:
    tst T_MODE
    lbeq tty_line_read
tg_raw_read:
    ldd T_RX_COUNT
    lbeq cio_again
    subd #1
    std T_RX_COUNT
    ldx #TTY_RX
    ldb T_RX_HEAD
    abx
    clra
    ldb ,x
    inc T_RX_HEAD
    andcc #$FE
    rts

T_OUTPUT_PENDING equ TTY_STATE+40
; Function: tty_wait. Inputs none, current foreground owner. Outputs0/C0 when
; input/edit/EOF/interrupt work is available, otherwise sleeps with P_FLAGS=4.
; Clobbers D,X,U; stack<=4. Atomic check/arm, no input consumed, GETC unchanged.
tty_wait:
    ldd CURRENT_PID
    cmpd T_FG
    lbne rx_owner
    jsr tty_input_ready
    tstd
    bne ti_return
    ldx CURRENT_PROC
    lda #4
    sta P_FLAGS,x
    lda #PS_WAIT
    sta P_STATE,x
    jmp rx_yield
; Function: tty_input_ready. Inputs provider state. Outputs D=1/0,C0, preserves
; X,Y,U,W,V; stack2. Editing is performed by GETC after waking, not by this probe.
tty_input_ready:
    ldd T_RX_COUNT
    bne ti_ready
    ldd T_LINE_LEFT
    bne ti_ready
    tst T_LINE_EOF
    bne ti_ready
    tst T_INTERRUPTED
    beq ti_return
ti_ready:
    ldd #1
ti_return:
    andcc #$FE
    rts

; Function: tty_line_read. Inputs provider FIFO, foreground owner. Outputs one
; completed edited-line byte, EOF, or EAGAIN; remainder retained in provider.
; Clobbers all; <=16 input bytes per syscall,109 editable bytes, bounded echo.
tty_line_read:
    ldd T_LINE_LEFT
    bne tline_deliver
    tst T_LINE_EOF
    beq tline_edit
    clr T_LINE_EOF
    ldd #SYS_EOF
    orcc #1
    rts
tline_edit:
    lda #16
    sta TTY_BUDGET
tline_next:
    jsr tg_raw_read
    bcs tline_return
    cmpb #4
    beq tline_eof
    cmpb #13
    beq tline_enter
    cmpb #10
    beq tline_enter
    cmpb #8
    beq tline_backspace
    cmpb #127
    beq tline_backspace
    cmpb #32
    blo tline_skip
    pshs b
    ldd T_EDIT_COUNT
    cmpd #109
    bhs tline_full
    ldx #TTY_TX
    leax d,x
    puls a
    sta ,x
    jsr tty_echo_byte
    ldd T_EDIT_COUNT
    addd #1
    std T_EDIT_COUNT
    bra tline_skip
tline_full:
    leas 1,s
    bra tline_skip
tline_backspace:
    ldd T_EDIT_COUNT
    beq tline_skip
    subd #1
    std T_EDIT_COUNT
    lda #8
    jsr tty_echo_byte
    lda #' '
    jsr tty_echo_byte
    lda #8
    jsr tty_echo_byte
tline_skip:
    dec TTY_BUDGET
    bne tline_next
    jmp cio_again
tline_eof:
    ldd T_EDIT_COUNT
    bne tline_enter
    lda #1
    sta T_LINE_EOF
    jmp tty_line_read
tline_enter:
    ldd T_EDIT_COUNT
    ldx #TTY_TX
    leax d,x
    lda #10
    sta ,x
    ldd T_EDIT_COUNT
    addd #1
    std T_LINE_LEFT
    ldd #0
    std T_EDIT_COUNT
    clr T_LINE_POS
    lda #13
    jsr tty_echo_byte
    lda #10
    jsr tty_echo_byte
tline_deliver:
    ldd T_LINE_LEFT
    subd #1
    std T_LINE_LEFT
    ldx #TTY_TX
    ldb T_LINE_POS
    abx
    inc T_LINE_POS
    clra
    ldb ,x
    andcc #$FE
tline_return:
    rts

; Function: tty_echo_byte. Inputs A=echo byte. Outputs bounded provider echo
; enqueue, discard-new count if full. Clobbers B,X,CC; preserves A; stack<=4.
tty_echo_byte:
    ldb T_ECHO_COUNT
    cmpb #128
    bhs te_full
    ldb T_ECHO_TAIL
    ldx #TTY_ECHO
    abx
    sta ,x
    inc T_ECHO_COUNT
    inc T_ECHO_TAIL
    ldb T_ECHO_TAIL
    andb #127
    stb T_ECHO_TAIL
    rts
te_full:
    inc T_ECHO_DROPPED+1
    rts

; Function: tty_control. Inputs actionbyte,modebyte,targetPID. Action0 establishes
; shell session,1 hands foreground to own child/self,2 sets line/raw and returns
; prior mode,3 restores shell. Clobbers all; unauthorized background returns EOWNER.
tty_control:
    lda PARAM_BUFFER
    beq tc_session
    cmpa #1
    beq tc_foreground
    cmpa #2
    beq tc_mode
    cmpa #3
    beq tc_restore
    cmpa #4
    beq tc_log_info
    cmpa #5
    beq tc_geometry
    jmp rx_invalid
tc_log_info:
    ldd T_LOG_DROPPED
    andcc #$FE
    rts
tc_geometry:
    ldd #$1950
    andcc #$FE
    rts
tc_session:
    ldd T_SHELL
    bne tc_already
    ldd CURRENT_PID
    std T_SHELL
    std T_FG
    ldu CURRENT_PROC
    std P_SESSION,u
    tst BOOT_FEEDBACK_ACTIVE
    beq tc_boot_done
    clr BOOT_FEEDBACK_ACTIVE
    ldb #BOOT_MSG_READY
    jsr ROM_BOOT_STATUS
tc_boot_done:
    ldd #0
    andcc #$FE
    rts
tc_already:
    ldd CURRENT_PID
    cmpd T_SHELL
    lbne rx_owner
    ldd #0
    andcc #$FE
    rts
tc_foreground:
    ldd CURRENT_PID
    cmpd T_SHELL
    lbne rx_owner
    ldd PARAM_BUFFER+2
    jsr process_lookup
    lbcs rx_done
    ldd P_PARENT,u
    cmpd CURRENT_PID
    lbne rx_owner
    ldd PARAM_BUFFER+2
    std T_FG
    std P_JOB_SCOPE,u
    lda T_MODE
    sta T_SAVED_MODE
    lda P_STATE,u
    cmpa #PS_SUSPENDED
    bne tc_foreground_ready
    lda #PS_READY
    sta P_STATE,u
tc_foreground_ready:
    clr T_MODE
    ldd #0
    andcc #$FE
    rts
tc_mode:
    ldd CURRENT_PID
    cmpd T_FG
    lbne rx_owner
    lda PARAM_BUFFER+1
    cmpa #1
    lbhi rx_invalid
    ldb T_MODE
    sta T_MODE
    clra
    andcc #$FE
    rts
tc_restore:
    ldd CURRENT_PID
    cmpd T_SHELL
    lbne rx_owner
    ldd T_SHELL
    std T_FG
    lda T_SAVED_MODE
    sta T_MODE
    ldd #0
    andcc #$FE
    rts

; Function: tty_log. Inputs source/count<=31. Outputs count/C0, discard-oldest
; accounting when full. Clobbers all; stack<=32. Accepted records are copied.
tty_log:
    ldd PARAM_BUFFER+2
    cmpd #31
    lbhi rx_invalid
    std TTY_LAST
    ldx PARAM_BUFFER
    ldy #COPY_BUFFER
    jsr copy_in
    lbcs rx_done
    lda T_LOG_COUNT
    cmpa #8
    blo tl_room
    tst T_LOG_OFFSET
    bne tl_drop_queued
    inc T_LOG_HEAD
    lda T_LOG_HEAD
    anda #7
    sta T_LOG_HEAD
    bra tl_dropped
tl_drop_queued:
    lda T_LOG_HEAD
    inca
    anda #7
    sta TTY_FIRST
    lda #6
    sta TTY_BUDGET
tl_shift_record:
    lda TTY_FIRST
    ldb #32
    mul
    ldy #LOG_BUFFER
    leay d,y
    lda TTY_FIRST
    inca
    anda #7
    ldb #32
    mul
    ldx #LOG_BUFFER
    leax d,x
    ldw #32
    tfm x+,y+
    inc TTY_FIRST
    lda TTY_FIRST
    anda #7
    sta TTY_FIRST
    dec TTY_BUDGET
    bne tl_shift_record
    lda T_LOG_TAIL
    deca
    anda #7
    sta T_LOG_TAIL
tl_dropped:
    ldd T_LOG_DROPPED
    addd #1
    std T_LOG_DROPPED
    dec T_LOG_COUNT
tl_room:
    lda T_LOG_TAIL
    ldb #32
    mul
    ldy #LOG_BUFFER
    leay d,y
    ldb TTY_LAST+1
    stb ,y+
    tstb
    beq tl_publish
    ldx #COPY_BUFFER
    clra
    tfr d,w
    tfm x+,y+
tl_publish:
    inc T_LOG_TAIL
    lda T_LOG_TAIL
    anda #7
    sta T_LOG_TAIL
    inc T_LOG_COUNT
    ldd TTY_LAST
    andcc #$FE
    rts

; Function: tty_progress. Inputs UART/FIFO/channel/log state. Outputs <=16 RX
; bytes and<=16 output bytes per call, plus one bounded Ctrl-C group teardown.
; Clobbers all; stack<=48. Never sleeps/polls UART readiness in a loop without budget.
tty_progress:
    lda #16
    sta TTY_BUDGET
tp_rx:
    lda UART_SRA
    bita #1
    beq tp_stdout
    lda UART+3
    cmpa #3
    beq tp_interrupt
    tst T_MODE
    bne tp_keep_byte
    cmpa #10
    bne tp_cr_check
    tst T_PREV_CR
    bne tp_skip_lf
tp_cr_check:
    clr T_PREV_CR
    cmpa #13
    bne tp_keep_byte
    inc T_PREV_CR
tp_keep_byte:
    pshs a
    ldd T_RX_COUNT
    cmpd #256
    bhs tp_drop
    addd #1
    std T_RX_COUNT
    ldx #TTY_RX
    ldb T_RX_TAIL
    abx
    puls a
    sta ,x
    inc T_RX_TAIL
    bra tp_rx_next
tp_skip_lf:
    clr T_PREV_CR
    bra tp_rx_next
tp_drop:
    leas 1,s
    ldd T_DROPPED
    addd #1
    std T_DROPPED
tp_rx_next:
    dec TTY_BUDGET
    bne tp_rx
    bra tp_stdout
tp_interrupt:
    ldd #0
    std T_EDIT_COUNT
    std T_LINE_LEFT
    clr T_LINE_EOF
    ldd T_FG
    cmpd T_SHELL
    bne tp_kill
    ; A suspended foreground spawn belongs to the shell until handoff. Abort
    ; its private image transaction before READY publication/application entry.
    tst LOADER_ACTIVE
    beq tp_line_interrupt
    lda LOADER_MODE
    cmpa #1
    bne tp_line_interrupt
    ldd LOADER_PARENT
    cmpd T_SHELL
    bne tp_line_interrupt
    tim #1,LOADER_FLAGS+1
    beq tp_line_interrupt
    lda #1
    sta LOADER_CANCEL
    bra tp_rx_next
tp_line_interrupt:
    inc T_INTERRUPTED
    bra tp_rx_next
tp_kill:
    jsr process_lookup
    bcs tp_rx_next
    ldd CURRENT_PID
    pshs d
    ldd CURRENT_PROC
    pshs d
    stu CURRENT_PROC
    ldd P_PID,u
    std CURRENT_PID
    ldd #130
    jsr process_exit
    puls d
    std CURRENT_PROC
    puls d
    std CURRENT_PID
    ldd T_SHELL
    std T_FG
    clr T_MODE
    bra tp_stdout
tp_stdout:
    lda #16
    sta TTY_BUDGET
tp_echo:
    tst T_ECHO_COUNT
    beq tp_stdout_scan
    lda UART_SRA
    bita #4
    beq tp_stdout_scan
    ldb T_ECHO_HEAD
    ldx #TTY_ECHO
    abx
    lda ,x
    sta UART_TXA
    dec T_ECHO_COUNT
    inc T_ECHO_HEAD
    ldb T_ECHO_HEAD
    andb #127
    stb T_ECHO_HEAD
    dec TTY_BUDGET
    bne tp_echo
tp_stdout_scan:
    ldd CURRENT_PID
    std TTY_OWNER
    tst T_OUTPUT_PENDING
    lbeq tp_logs
    clr T_OUTPUT_PENDING
    ldy T_STD_CURSOR
    bne tp_cursor_valid
    ldy #CHANNEL_TABLE
tp_cursor_valid:
    sty TTY_SCAN
    lda #16
    sta TTY_BUDGET
    lda #CHANNEL_COUNT
    sta T_STD_VISITS
tp_channel:
    ldy TTY_SCAN
    tst C_STATE,y
    beq tp_channel_next
    lda C_FLAGS,y
    cmpa #4
    beq tp_input_orphan
    cmpa #2
    bne tp_channel_next
    ldd C_PRODUCER,y
    bne tp_session_live
    ldd C_TTY_SESSION,y
    cmpd T_SHELL
    bne tp_close_old_output
tp_session_live:
    lda #16
    sta T_STD_BYTES
tp_channel_bytes:
    ldd C_USED,y
    beq tp_output_empty
    lda #1
    sta T_OUTPUT_PENDING
    lda UART_SRA
    bita #4
    beq tp_logs
    lda MMU2
    sta IO_MAP
    lda C_FRAME,y
    sta MMU2
    ldx #$8000
    ldd C_READ,y
    leax d,x
    lda ,x
    sta UART_TXA
    lda #1
    sta IPC_WAKE_PENDING
    lda IO_MAP
    sta MMU2
    ldd C_READ,y
    addd #1
    cmpd C_CAPACITY,y
    blo tp_stdout_position
    ldd #0
tp_stdout_position:
    std C_READ,y
    ldd C_USED,y
    subd #1
    std C_USED,y
    dec TTY_BUDGET
    beq tp_channel_next
    dec T_STD_BYTES
    bne tp_channel_bytes
    bra tp_channel_next
tp_output_empty:
    ldd C_PRODUCER,y
    bne tp_channel_next
tp_close_old_output:
    ldd #$FFFE
    std CURRENT_PID
    ldd C_RX,y
    jsr channel_close
    bra tp_channel_next
tp_input_orphan:
    ldd C_CONSUMER,y
    bne tp_channel_next
    ldd #$FFFE
    std CURRENT_PID
    ldd C_TX,y
    jsr channel_close
tp_channel_next:
    ldd TTY_SCAN
    addd #CHANNEL_SIZE
    cmpd #CHANNEL_TABLE+CHANNEL_COUNT*CHANNEL_SIZE
    blo tp_next_store
    ldd #CHANNEL_TABLE
tp_next_store:
    std TTY_SCAN
    std T_STD_CURSOR
    tst TTY_BUDGET
    beq tp_logs
    dec T_STD_VISITS
    bne tp_channel
tp_logs:
    ldd TTY_OWNER
    std CURRENT_PID
    lda UART+9
    bita #4
    beq tp_done
    ldd T_LOG_DROPPED
    cmpd T_LOG_REPORTED
    bne tp_loss_marker
    tst T_LOG_COUNT
    beq tp_done
    lda T_LOG_HEAD
    ldb #32
    mul
    ldx #LOG_BUFFER
    leax d,x
    ldb T_LOG_OFFSET
    cmpb ,x
    bhs tp_log_complete
    leax 1,x
    lda b,x
    sta UART+11
    inc T_LOG_OFFSET
    bra tp_done
tp_log_complete:
    clr T_LOG_OFFSET
    inc T_LOG_HEAD
    lda T_LOG_HEAD
    anda #7
    sta T_LOG_HEAD
    dec T_LOG_COUNT
tp_done:
    rts
tp_loss_marker:
    ldx #tp_loss_text
    ldb T_LOG_MARK_OFFSET
    lda b,x
    beq tp_loss_complete
    sta UART+11
    inc T_LOG_MARK_OFFSET
    rts
tp_loss_complete:
    ldd T_LOG_DROPPED
    std T_LOG_REPORTED
    clr T_LOG_MARK_OFFSET
    rts
tp_loss_text: fcc "![log records discarded]"
    fcb 13,10,0


; Function: tty_drain. Inputs child PID. Outputs0/C0 when its provider stdout is
; drained, EAGAIN/C1 while retained bytes exist; only recorded parent may wait.
; Clobbers D,Y; stack<=4. No timeout/forced data discard for a live TTY session.
tty_drain:
    ldy #CHANNEL_TABLE
td_scan:
    tst C_STATE,y
    beq td_next
    lda C_FLAGS,y
    cmpa #2
    bne td_next
    ldd C_TTY_OWNER,y
    cmpd PARAM_BUFFER
    bne td_next
    ldd C_TTY_PARENT,y
    cmpd CURRENT_PID
    lbne rx_owner
    ldd C_USED,y
    lbne cio_again
td_next:
    leay CHANNEL_SIZE,y
    cmpy #CHANNEL_TABLE+CHANNEL_COUNT*CHANNEL_SIZE
    blo td_scan
    ldd #0
    andcc #$FE
    rts
