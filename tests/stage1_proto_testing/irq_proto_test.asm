
    org $f000
hook_trap:
hang:
    bra hang
hook_swi3:
hook_swi2:
hook_firq:
    bra found_irq
hook_irq:
hook_swi:
hook_nmi:
hook_reset:
    ; Setup stack pointer for gods sake!!!
    lds #$0200              ;Set system stack pointer to bottom of stack
    jsr INIT
    jsr SERIAL_INIT_A
    
wait_for_cr:
    jsr SERIAL_INPUT_A
    cmpa #$0d
    bne wait_for_cr

    ldx #str_greet
    jsr SERIAL_PRINT_A
    jsr IRQ_INIT
    lda #$0e
    jsr SET_IRQ_FILTER
    tfr a,e

    
wait_next:
    ldx #str_wait_for_irq
    jsr SERIAL_PRINT_A
    tfr e,a
    inca
    jsr PRBYTE
    lda #$0d
    jsr ECHO

    andcc #$bf           ; Turn on FIRQ
    bra hang

found_irq:
    orcc #$50
    jsr GET_ACTIVE_IRQ
    tfr a,e
    ldx #str_found_irq
    jsr SERIAL_PRINT_A

    tfr e,a
    jsr PRBYTE
    lda #$0d
    jsr ECHO

    dece
    dece
    tfr e,a
    beq end
    jsr SET_IRQ_FILTER
    bra wait_next

end:
    orcc #$50
    ldx #str_test_complete
    jsr SERIAL_PRINT_A
    bra hang

; System init function
INIT:
    jsr CLEAR_REGS
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
    orcc   #$50         ; Turn off IRQ
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
str_found_irq:
    fcn 'Found irq: '
str_wait_for_irq:
    fcn 'Wait for irq: '
str_test_complete:
    fcn 'Test complete, jobs done!'
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

