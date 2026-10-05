    org $C000
ENTRY:
    orcc #$50
    ldmd #1
    lds #$E000
    lda #$12
    tfr a,dp
    ldx #NAME
    clrb
    jsr BIOS_MODULE_LOAD
    bcs LOAD_FAILED
    stx ENTRY_POINTER
    ifndef TEST_FAULT_WRITE
TEST_FAULT_WRITE equ 0
    endc
    ifndef TEST_FAULT_AFTER
TEST_FAULT_AFTER equ 0
    endc
    ifne TEST_FAULT_WRITE
    ldx #FAULT_BIOS_API
    else
    ldx #BIOS_MODULE_API_BASE
    endc
    ldy #1
    jsr [ENTRY_POINTER]
    std $0310                     ; Initialization/mount result.
    ldb #TEST_PARTITION
    jsr FS_API_MOUNT
    std $0312                     ; Selected partition mount result.
    ldx #TEST_REQUEST
    ldy #$1357
    ldu #$2468
    ldb #TEST_PARTITION
    jsr TEST_SERVICE
    std $0300
    tfr cc,a
    sta $0302
    stx $0304
    sty $0306
    stu $0308
    sts $030A
    tfr dp,a
    sta $030C
    lda #$A5
    sta $030F
DONE:
    bra DONE
LOAD_FAILED:
    sta $0301
    lda #$FF
    sta $030F
    bra DONE
ENTRY_POINTER:
    rmb 2
NAME:
    fcn "/biosfs.mlp"
    org $C100
C_ENTRY:
    pshs dp,x,y,u
    jsr $0400
    puls dp,x,y,u,pc
    ifne TEST_FAULT_WRITE
    org $C200
FAULT_BIOS_API:
    fcc "MBR1"
    fdb BIOS_MODULE_API_VERSION,6
    jmp BIOS_MODULE_CF_INIT
    jmp BIOS_MODULE_CF_READ
    jmp FAULT_WRITE
    jmp BIOS_MODULE_SERIAL_PRINT
    jmp BIOS_MODULE_SERIAL_PUTC
    jmp BIOS_MODULE_SERIAL_GETC
FAULT_WRITE:
    pshs a
    inc $0330
    lda $0330
    cmpa #TEST_FAULT_WRITE
    puls a
    ifeq TEST_FAULT_AFTER
    beq FAULT_ERROR
    endc
    jsr BIOS_MODULE_CF_WRITE
    bcs FAULT_RETURN
    lda $0330
    cmpa #TEST_FAULT_WRITE
    ifne TEST_FAULT_AFTER
    beq FAULT_ERROR
    endc
    clra
    andcc #$FE
FAULT_RETURN:
    rts
FAULT_ERROR:
    lda #2
    orcc #1
    rts
    endc
