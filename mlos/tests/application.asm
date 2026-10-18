    include "layout.inc"
    include "syscalls.inc"
    include "hardware.inc"
    org APP_START
; Function: application_test — real native application exercising public SWI ABI.
; Inputs: window0=resident, window1/2 vacant, gate locked. Outputs: TEST_RESULT.
; Clobbers: test process state only. Stack: application reserve 1KiB; no return.
application_test:
    lda #$11
    sta TEST_STEP
    lda GATE
    bita #$80
    lbne app_failed
    lda #31
    sta MMU0                        ; denied, application continues in same bank.
    lda MMU0
    cmpa #APP_FRAME
    lbne app_failed
    lda #$A7
    sta $0100
    lda #$00
    sta $0101
    ; Native registers/CC and stack preservation across nested entry.
    ldw #$1234
    ldy #$5678
    ldu #$9ABC
    ldd #$DEF0
    tfr d,v
    lda #$12
    tfr a,dp
    ldx #$0110
    lda #SYS_ENTRY_TEST
    swi
    lbcs app_failed
    cmpd #$6309
    lbne app_failed
    cmpx #$0110
    lbne app_failed
    cmpy #$5678
    lbne app_failed
    cmpu #$9ABC
    lbne app_failed
    cmpw #$1234
    lbne app_failed
    tfr v,d
    cmpd #$DEF0
    lbne app_failed
    tfr dp,a
    cmpa #$12
    lbne app_failed
    cmps #APP_STACK
    lbne app_failed
    clra
    tfr a,dp
    lda GATE
    bita #$80
    lbne app_failed
    lda MMU2
    cmpa #DISCARD_FRAME
    lbne app_failed
    lda #$12
    sta TEST_STEP
    lda #SYS_PROBE
    swi
    lbcs app_failed
    cmpd #ABI_VERSION
    lbne app_failed
    lda #$FE
    swi
    lbcc app_failed
    cmpd #SYS_ENOSYS
    lbne app_failed

    lda #$13
    sta TEST_STEP
    lda #SYS_BANK_ALLOC
    swi
    lbcs app_failed
    std token
    std map_params
    lda #1
    sta map_params+2
    ldx #map_params
    lda #SYS_BANK_MAP
    swi
    lbcs app_failed
    ; A real spanning source: last2 bytes of window0 + first2 of resource window1.
    ldd #$4142
    std $3FFE
    ldd #$4344
    std $4000
    ldx #copy_params
    lda #SYS_COPY
    swi
    lbcs app_failed
    cmpd #4
    lbne app_failed
    ldd copy_result
    cmpd #$4142
    lbne app_failed
    ldd copy_result+2
    cmpd #$4344
    lbne app_failed

    ; Destination at a bank boundary: inverse path, including app window0.
    ldd #copy_result
    std copy_params
    ldd #$3FFE
    std copy_params+2
    lda #SYS_COPY
    swi
    lbcs app_failed
    ldd $3FFE
    cmpd #$4142
    lbne app_failed
    ldd $4000
    cmpd #$4344
    lbne app_failed

    ; Reject live resident replacement and leave map/role unchanged.
    clr map_params+2
    ldx #map_params
    lda #SYS_BANK_MAP
    swi
    lbcc app_failed
    cmpd #SYS_EBUSY
    lbne app_failed
    lda MMU0
    cmpa #APP_FRAME
    lbne app_failed

    lda #$14
    sta TEST_STEP
    ; Whole-range validation: source is valid but destination crosses into vacant2.
    ldd #copy_result
    std copy_params
    ldd #$7FFF
    std copy_params+2
    lda #$A5
    sta $7FFF
    ldx #copy_params
    lda #SYS_COPY
    swi
    lbcc app_failed
    cmpd #SYS_EFAULT
    lbne app_failed
    lda $7FFF
    cmpa #$A5
    lbne app_failed
    ; Invalid parameter pointer in common, then wrapped payload and zero length.
    ldx #$C000
    lda #SYS_COPY
    swi
    lbcc app_failed
    cmpd #SYS_EFAULT
    lbne app_failed
    ldd #$FFFF
    std copy_params
    std copy_params+2
    ldd #4
    std copy_params+4
    ldx #copy_params
    lda #SYS_COPY
    swi
    lbcc app_failed
    ldd #0
    std copy_params+4
    lda #SYS_COPY
    swi
    lbcs app_failed
    cmpd #0
    lbne app_failed

    lda #$15
    sta TEST_STEP
    ldx #token
    lda #SYS_BANK_FREE
    swi
    lbcs app_failed
    lda MMU1
    cmpa #DISCARD_FRAME
    lbne app_failed
    lda #SYS_BANK_FREE
    swi
    lbcc app_failed
    cmpd #SYS_ESTALE
    lbne app_failed
    ldx #info_params
    lda #SYS_MEMORY_INFO
    swi
    lbcs app_failed
    ldd info_result
    cmpd #$2003
    lbne app_failed
    ldd info_result+2
    cmpd #$1C01
    lbne app_failed
    ldd KERNEL_CANARY
    cmpd #$A55A
    lbne app_failed
    ldd EMERGENCY_CANARY
    cmpd #$A55A
    lbne app_failed
    tst ENTRY_DEPTH
    lbne app_failed
    ldx #write_params
    lda #SYS_WRITE
    swi
    lbcs app_failed
    lda #$A5
    sta TEST_RESULT
app_done:
    bra app_done
app_failed:
    lda #$FF
    sta TEST_RESULT
    bra app_failed

token:          fdb 0
map_params:     fdb 0
                fcb 1
copy_params:    fdb $3FFE,copy_result,4
copy_result:    fcb 0,0,0,0
info_params:    fdb info_result
info_result:    fcb 0,0,0,0
write_params:   fdb success_text,success_end-success_text
success_text:   fcc "MLOS S00-S02 PASS"
                fcb 13,10
success_end:
APP_END equ *
    ifgt APP_END-$3A00
    error "Application diagnostic overlaps stack reserve"
    endc
