; Trusted module ABI1: fixed link $4000, one immutable code frame until reset;
; per-instance state occupies its own admitted frame at $8000. Serialized
; callbacks run on the bounded common kernel stack with IRQ/FIRQ masked.
MODULE_TABLE equ $C140
MODULE_COUNT equ 4
MODULE_SIZE equ 16
M_FRAME equ 0
M_LIVE equ 1
M_BYTES equ 2
M_BIND equ 4
M_POLL equ 6
M_STOP equ 8
MODULE_SLOT equ $C132
MODULE_FRAME equ $C134
MODULE_MAP1 equ $C135
MODULE_MAP2 equ $C136
MODULE_VECTOR equ $C138
MODULE_LEFT equ $C13A
MODULE_STATUS equ $C13C

; Function: module_load. Inputs name pointer; init or registered shell only.
; Outputs permanent module ID1..4/C0, failure releases provisional frame/C1.
; Clobbers all; stack<=64. Restricted boot-provider image, <=16KB payload/BSS.
module_load:
    tst LOADER_ACTIVE
    lbne cio_again
    ldd CURRENT_PID
    cmpd #1
    beq ml_authorized
    cmpd T_SHELL
    lbne rx_owner
ml_authorized:
    lda DEVICE_TABLE+D_ACTIVE
    cmpa #$FF
    lbne cio_again
    ldx PARAM_BUFFER
    ldy #LOADER_NAME
    ldb #48
ml_name:
    pshs b,x,y
    ldd #1
    jsr copy_in
    puls b,x,y
    lbcs rx_done
    tst ,y+
    beq ml_find
    leax 1,x
    decb
    bne ml_name
    ldd #SYS_ENAMETOOLONG
    orcc #1
    rts
ml_find:
    ldx #LOADER_NAME
    ldy #ml_suffix
    jsr image_name_check
    lbcs rx_invalid
    jsr ROM_FILE_FIND
    lbcs rx_invalid
    ldq BOOT_FILE_LBA
    stq LOADER_LBA
    ldd BOOT_FILE_SIZE
    cmpd #33
    lblo rx_invalid
    ldx #BOOT_BUFFER
    ldq LOADER_LBA
    jsr ROM_CF_READ
    lbcs ml_io
    ldx #BOOT_BUFFER
    ldy #LOADER_HEADER
    ldw #32
    tfm x+,y+
    ldd LOADER_HEADER
    cmpd #$4D4C
    lbne rx_invalid
    ldd LOADER_HEADER+2
    cmpd #$4431
    lbne rx_invalid
    ldd LOADER_HEADER+4
    cmpd #1
    lbne rx_invalid
    ldd LOADER_HEADER+6
    cmpd #32
    lbne rx_invalid
    ldd LOADER_HEADER+8
    cmpd #1
    lbne rx_invalid
    ldd LOADER_HEADER+10
    cmpd #$4000
    lbne rx_invalid
    ldd LOADER_HEADER+12
    lbeq rx_invalid
    addd #32
    cmpd BOOT_FILE_SIZE
    lbne rx_invalid
    ldd LOADER_HEADER+12
    addd LOADER_HEADER+14
    lbcs rx_invalid
    cmpd #$4000
    lbhi rx_invalid
    ldd LOADER_HEADER+22
    cmpd #1                     ; block request capability only
    lbne rx_invalid
    ldq LOADER_HEADER+28
    tstd
    lbne rx_invalid
    cmpw #0
    lbne rx_invalid
    ldx #LOADER_HEADER+16
ml_entries:
    ldd ,x++
    cmpd LOADER_HEADER+12
    lbhs rx_invalid
    cmpx #LOADER_HEADER+22
    blo ml_entries
    ldy #MODULE_TABLE
ml_slot:
    tst M_LIVE,y
    beq ml_slot_found
    leay MODULE_SIZE,y
    cmpy #MODULE_TABLE+MODULE_COUNT*MODULE_SIZE
    blo ml_slot
    jmp ps_no_memory
ml_slot_found:
    sty MODULE_SLOT
    ldd CURRENT_PID
    pshs d
    ldd #$FFFE
    std CURRENT_PID
    ldb #1
    jsr frame_alloc_many
    puls d
    std CURRENT_PID
    lbcs rx_done
    lda ALLOC_LIST
    sta MODULE_FRAME
    ldq LOADER_HEADER+24
    stq BOOT_SUM
    ldq #0
    stq LOADER_HEADER+24
    ldx #LOADER_HEADER
    ldy #32
    jsr image_sum
    stq LOADER_SUM
    ldd #32
    std LOADER_OFFSET
    ldd LOADER_HEADER+12
    std LOADER_LEFT
    ldd #$4000
    std LOADER_DEST
    ldd LOADER_HEADER+14
    std LOADER_COUNT
    ldu CURRENT_PROC
    stu LOADER_PARENT_PROC
    ldd CURRENT_PID
    std LOADER_PARENT
    lda #PS_WAIT
    sta P_STATE,u
    lda #3
    sta P_FLAGS,u
    lda #2
    sta LOADER_MODE
    lda #1
    sta LOADER_ACTIVE
    clr LOADER_PHASE
    inc SCHED_PENDING
    ldd #0
    andcc #$FE
    rts

; Function: module_step. Inputs admitted loader state,private mapped code frame.
; Outputs <=32 payload/BSS bytes or final publication/unwind; no suspended
; kernel stack. Clobbers all; stack<=40, no borrowed application pointers.
module_step:
    lda LOADER_PHASE
    bne ml_bss
ml_payload:
    tst LOADER_BUDGET
    beq ml_pause
    ldd LOADER_LEFT
    beq ml_verify
    dec LOADER_BUDGET
    jsr image_byte
    lbcs ml_unwind
    ldy LOADER_DEST
    sta ,y+
    sty LOADER_DEST
    bra ml_payload
ml_verify:
    ldq LOADER_SUM
    cmpd BOOT_SUM
    lbne ml_unwind
    cmpw BOOT_SUM+2
    lbne ml_unwind
    lda #1
    sta LOADER_PHASE
ml_bss:
    ldd LOADER_COUNT
    beq ml_publish
    tst LOADER_BUDGET
    beq ml_pause
    dec LOADER_BUDGET
    ldy LOADER_DEST
    clr ,y+
    sty LOADER_DEST
    ldd LOADER_COUNT
    subd #1
    std LOADER_COUNT
    bra ml_bss
ml_pause:
    rts
ml_publish:
    ldy MODULE_SLOT
    lda MODULE_FRAME
    sta M_FRAME,y
    ldd LOADER_HEADER+12
    std M_BYTES,y
    ldx #LOADER_HEADER+16
    leay M_BIND,y
    ldb #3
ml_vectors:
    ldd ,x++
    addd #$4000
    std ,y++
    cmpx #LOADER_HEADER+22
    blo ml_vectors
    ldy MODULE_SLOT
    lda #1
    sta M_LIVE,y
    lda #3
    sta LOADER_PHASE
    tfr y,d
    subd #MODULE_TABLE
    lsrd
    lsrd
    lsrd
    lsrd
    addd #1
    andcc #$FE
    rts
ml_unwind:
    lda #3
    sta LOADER_PHASE
    lda MODULE_FRAME
    jsr frame_address
    clr F_OWNER,x
    clr F_OWNER+1,x
    clr F_FLAGS,x
    inc FREE_COUNT
    jmp rx_invalid
ml_io:
    ldd #SYS_EIO
    orcc #1
    rts

; Function: module_bind. Inputs moduleID word,device2/3,reserved0,delay1..32767.
; Outputs0/C0 only after private state allocation and successful bind callback.
; Clobbers all; stack<=64; second-instance failure leaves first instance live.
module_bind:
    ldd CURRENT_PID
    cmpd #1
    beq mb_auth
    cmpd T_SHELL
    lbne rx_owner
mb_auth:
    tst PARAM_BUFFER+3
    lbne rx_invalid
    ldd PARAM_BUFFER
    beq mb_invalid
    cmpd #MODULE_COUNT
    bhi mb_invalid
    subd #1
    lslb
    lslb
    lslb
    lslb
    ldx #MODULE_TABLE
    leax b,x
    tst M_LIVE,x
    beq mb_invalid
    ldb PARAM_BUFFER+2
    cmpb #2
    blo mb_invalid
    cmpb #DEVICE_COUNT
    bhs mb_invalid
    lda #DEVICE_SIZE
    mul
    ldy #DEVICE_TABLE
    leay d,y
    ldd D_OWNER,y
    lbne mem_busy
    lda D_ACTIVE,y
    cmpa #$FF
    lbne mem_busy
    tst D_MODULE,y
    lbne mem_busy
    sty IO_DEVICE
    ldd CURRENT_PID
    pshs d
    ldd #$FFFE
    std CURRENT_PID
    ldb #1
    jsr frame_alloc_many
    puls d
    std CURRENT_PID
    lbcs rx_done
    ldy IO_DEVICE
    lda ALLOC_LIST
    sta D_STATE_FRAME,y
    lda PARAM_BUFFER+1
    sta D_MODULE,y
    ldd PARAM_BUFFER+4
    std D_DELAY,y
    ; Bind initializes its private fields; unused state bytes are unspecified.
    ldx #0
    clrb
    jsr module_callback
    bcs mb_unwind
    ldd #0
    andcc #$FE
    rts
mb_unwind:
    pshs d
    ldy IO_DEVICE
    clr D_MODULE,y
    lda D_STATE_FRAME,y
    clr D_STATE_FRAME,y
    jsr frame_address
    clr F_OWNER,x
    clr F_OWNER+1,x
    clr F_FLAGS,x
    inc FREE_COUNT
    puls d
    orcc #1
    rts
mb_invalid:
    jmp rx_invalid

; Function: module_callback. Inputs X=request/0,Y=device,B=vector byteoffset0/2/4.
; Module receives D=low ticks,X=request,Y=$8000 state,U=device; D/C result.
; Outputs restores both maps and caller X/Y/U/W. No syscall, sleep or recursive
; callback permitted. Trusted CPU fault uses core panic; module must bound work.
module_callback:
    pshs x,y,u
    pshsw
    pshs b
    ldb D_MODULE,y
    decb
    lda #MODULE_SIZE
    mul
    ldu #MODULE_TABLE
    leau d,u
    puls b
    leau M_BIND,u
    ldd b,u
    std MODULE_VECTOR
    leau -M_BIND,u
    lda MMU1
    sta MODULE_MAP1
    lda MMU2
    sta MODULE_MAP2
    lda M_FRAME,u
    sta MMU1
    lda D_STATE_FRAME,y
    sta MMU2
    tfr y,u
    ldy #$8000
    ldd TICKS+2
    jsr [MODULE_VECTOR]
    pshs cc,d
    lda MODULE_MAP1
    sta MMU1
    lda MODULE_MAP2
    sta MMU2
    puls cc,d
    pulsw
    puls x,y,u,pc

ml_suffix: fcn ".mld"
; Function: module_progress. Inputs private pending module transaction. Outputs
; bounded code/BSS progress, then module ID/error in saved parent context.
; Clobbers all; restores PID and both borrowed maps; stack<=80. Dead parent
; cancels unpublished code safely; accepted code is retained until reset.
module_progress:
    ldd CURRENT_PID
    pshs d
    lda MMU1
    pshs a
    lda MMU2
    pshs a
    ldd LOADER_PARENT
    std CURRENT_PID
    ldu LOADER_PARENT_PROC
    lda P_STATE,u
    cmpa #PS_WAIT
    bne mp_cancel
    lda MODULE_FRAME
    sta MMU1
    lda #32
    sta LOADER_BUDGET
    jsr module_step
    pshs cc,d
    lda LOADER_PHASE
    cmpa #3
    bne mp_paused
    puls cc,d
    pshs cc,d
    ldu LOADER_PARENT_PROC
    std P_CONTEXT+N_A,u
    bcs mp_error
    lda P_CONTEXT+N_CC,u
    anda #$FE
    bra mp_wake
mp_error:
    lda P_CONTEXT+N_CC,u
    ora #1
mp_wake:
    sta P_CONTEXT+N_CC,u
    lda #PS_READY
    sta P_STATE,u
    clr LOADER_ACTIVE
    clr LOADER_MODE
mp_paused:
    leas 3,s
mp_restore:
    puls a
    sta MMU2
    puls a
    sta MMU1
    puls d
    std CURRENT_PID
    rts
mp_cancel:
    jsr ml_unwind
    clr LOADER_ACTIVE
    clr LOADER_MODE
    bra mp_restore
