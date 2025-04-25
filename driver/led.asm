PWR_LED EQU $F405

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

; -----------------------------------------------------------------
; SET_LED
; input:            A = LED state, 0 = OFF, 1 = RED, 2 = GREEN, 4 = BLUE
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SET_LED:
    sta PWR_LED
    rts

; -----------------------------------------------------------------
; SET_LED_RED
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SET_LED_RED:
    lda #4
    sta PWR_LED
    rts

; -----------------------------------------------------------------
; SET_LED_GREEN
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SET_LED_GREEN:
    lda #2
    sta PWR_LED
    rts

; -----------------------------------------------------------------
; SET_LED_BLUE
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SET_LED_BLUE:
    lda #1
    sta PWR_LED
    rts

; -----------------------------------------------------------------
; SET_LED_OFF
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
SET_LED_OFF:
    lda #0
    sta PWR_LED
    rts