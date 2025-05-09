; -----------------------------------------------------------------
; IRQ Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2025
;

IRQ_BASE           EQU $f404

IRQ_JUMP_TABLE:
    FDB SERIAL_IRQ_HANDLER
    FDB _UNUSED_IRQ_
    FDB _UNUSED_IRQ_
    FDB _UNUSED_IRQ_
    FDB EXPANSION_IRQ_HANDLER
    FDB _UNUSED_IRQ_
    FDB VIDEO_IRQ_HANDLER
    FDB AUDIO_IRQ_HANDLER
    FDB _UNUSED_IRQ_
    FDB _UNUSED_IRQ_
    FDB _UNUSED_IRQ_
    FDB _UNUSED_IRQ_
    FDB _UNUSED_IRQ_
    FDB _UNUSED_IRQ_
    FDB _UNUSED_IRQ_
    FDB _ILLEGAL_IRQ_
; -----------------------------------------------------------------
; IRQ INIT
; input:            None
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
IRQ_INIT:
        ; Set least interupt mask
        lda #$0F
        jsr IRQ_SET_FILTER
        orcc #$50
        rts

; -----------------------------------------------------------------
; SET IRQ FILTER
; input:            A = IRQ filter (0-15)
; output:           None
; clobbers:         A
; -----------------------------------------------------------------
IRQ_SET_FILTER:
        lsla                ; Shift to correct position
        lsla
        lsla
        lsla
        sta IRQ_BASE        ; Store in IRQ_BASE
        rts

; -----------------------------------------------------------------
; GET ACTIVE IRQ
; input:            None
; output:           A = Active IRQ
; clobbers:         A
; -----------------------------------------------------------------
IRQ_GET_ACTIVE:
        lda IRQ_BASE
        anda #$0F
        rts

; -----------------------------------------------------------------
; GET CURRENT IRQ FILTER
; input:            None
; output:           A = Current IRQ filter
; clobbers:         A
; -----------------------------------------------------------------
IRQ_GET_CURRENT_FILTER:
        lda IRQ_BASE
        lsra
        lsra
        lsra
        lsra 
        rts

; Temporary FIRQ Handler
FIRQ_HANDLER:
       jsr IRQ_GET_ACTIVE
       ldx IRQ_JUMP_TABLE
       asla
       jmp [a,x]

IRQ_HANDLER:
       jmp PARALLEL_IRQ_HANDLER

_ILLEGAL_IRQ_:
_UNUSED_IRQ_:
    ;TODO: Tell user about the illegal IRQ
       rti

    IFNDEF VIDEO_IRQ_HANDLER
VIDEO_IRQ_HANDLER:
        rti 
    ENDC

    IFNDEF AUDIO_IRQ_HANDLER
AUDIO_IRQ_HANDLER:
       rti
    ENDC

    IFNDEF EXPANSION_IRQ_HANDLER
EXPANSION_IRQ_HANDLER:
       rti
    ENDC
