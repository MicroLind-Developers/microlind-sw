; -----------------------------------------------------------------
; Call jump table for µLind BIOS
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2026
;
    INCLUDE "../include/memory.inc"
    org $F800

; -----------------------------------------------------------------
; Jump table for bios calls

; System calls
BC_RESET:          fdb INIT

; Memory Management calls
BC_MMU_SET_REG:    fdb MMU_SET_REGISTER
BC_MMU_GET_REG:    fdb MMU_GET_REGISTER

; IRQ Management calls
BC_IRQ_SET_FILTER: fdb IRQ_SET_FILTER
BC_IRQ_GET_FILTER: fdb IRQ_GET_CURRENT_FILTER
BC_IRQ_GET_ACTIVE: fdb IRQ_GET_ACTIVE