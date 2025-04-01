; IMPORTANTE!!! This code together with the parallel protoboard requires 
;   an address chip with positive logic on the parallel enable
; ************************************************************************

    org $f000
hook_trap:
hang:
    bra hang
hook_swi3:
hook_swi2:
hook_firq:
hook_irq:
hook_swi:
hook_nmi:
hook_reset:
    ; Setup stack pointer for gods sake!!!
    lds #$0200              ;Set system stack pointer to bottom of stack
    jsr INIT
    jsr SERIAL_INIT_A
    jsr PARALLEL_INIT

wait_for_cr:
    jsr SERIAL_INPUT_A
    cmpa #$0d
    bne wait_for_cr
    ldx #str_greet
    jsr SERIAL_PRINT_A
    
loop:
    lda ORA_22
    cmpa #$FF
    beq check_b
    tfr a,e
    ldx #str_p_a
    jsr SERIAL_PRINT_A
    tfr e,a
    coma
    jsr PRBYTE
    lda #$0d
    jsr ECHO

check_b:
    lda ORB_22
    cmpa #$FF
    beq loop
    tfr a,e
    ldx #str_p_b
    jsr SERIAL_PRINT_A
    tfr e,a
    coma
    jsr PRBYTE
    lda #$0d
    jsr ECHO

    bra loop

; System init function
INIT:
    jsr CLEAR_REGS
    orcc #$50       ; Turn off IRQ
    lda #$c0
    tfr a,dp
    rts

CLEAR_REGS:
    ldq     #$00000000
    tfr     a,dp
    tfr     d,x
    tfr     d,y
    tfr     d,u
    tfr     d,v
    andcc   #$00
    rts

PRBYTE: sta ,-s
        lsra
        lsra
        lsra
        lsra
        jsr PRHEX
        lda ,s+
PRHEX:  anda #$0f
        ora #'0'
        cmpa #$3a
        bcs ECHO
        adda #$07
ECHO:   ldb ISR1
        andb #$40
        beq ECHO
        sta TDR1
        rts

    org $E000
str_greet:
    fcn 'microLind initialized...'
str_p_a:
    fcn 'Port A: $'
str_p_b:
    fcn 'Port B: $'

; Setup vectors
    org $FFF0

V_TRAP:     fdb hook_trap
V_SWI3:     fdb hook_swi3
V_SWI2:     fdb hook_swi2
V_FIRQ:     fdb hook_firq
V_IRQ:      fdb hook_irq
V_SWI:      fdb hook_swi
V_NMI:      fdb hook_nmi
V_RESET:    fdb hook_reset

