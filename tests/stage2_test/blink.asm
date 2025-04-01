    org $FE00

PWR_LED EQU $F405
BANK_REG_0 EQU $F400
BANK_REG_1 EQU $F401
BANK_REG_2 EQU $F402
BANK_REG_3 EQU $F403

_START:
    clrb
LOOP:
    stb PWR_LED
    ldx #$03E8
    jsr DELAY_MS
    cmpb #$07
    beq _START
    incb
    bra LOOP


; -----------------------------------------------------------------
; DELAY_MS
; input:            X = Number of milliseconds to delay
; output:           None
; clobbers:         A, X
; There are 2000 cycles per millisecond
; The DELAY_MS function will delay for 11 extra cycles
; -----------------------------------------------------------------
DELAY_MS:
    lda #$7C            ; 2 cycles
DELAY_MS_LOOP:
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    deca                ; 1 cycles
    cmpa #$00           ; 4 cycles
    bne DELAY_MS_LOOP   ; 3 cycles
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    leax ,-x            ; 5 cycles
    cmpx #$0000         ; 4 cycles
    bne DELAY_MS        ; 3 cycles
    rts                 ; 4 cycles


STACK EQU $1000

    org $FF00
hook_trap:
hook_swi3:
hook_swi2:
hook_swi:
hook_firq:
hook_irq:
hook_nmi:
hook_restart:
    ; Initialize the CPU
    ldmd #$01

    ; Initialize the bank registers
    clra
    sta BANK_REG_0
    sta BANK_REG_1
    sta BANK_REG_2
    sta BANK_REG_3

    ; Set up the stack
    lds #STACK

    lbra _START

hang:
    bra hang


    org $FFF0

vtrap: fdb hook_trap
vswi3: fdb hook_swi3
vswi2: fdb hook_swi2
vfirq: fdb hook_firq
virq: fdb hook_irq
vswi: fdb hook_swi
vnmi: fdb hook_nmi
vrestart: fdb hook_restart