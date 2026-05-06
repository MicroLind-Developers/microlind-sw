; -----------------------------------------------------------------
; MLOS memory manager
; -----------------------------------------------------------------
; First-stage allocator for kernel/user C runtime bring-up.
;
; This is intentionally a linear heap, not a full physical page allocator.
; It gives C code an sbrk-style primitive now, while the later bitmap/page
; allocator can take over without changing the syscall API.
; -----------------------------------------------------------------

    IFNDEF MLOS_INC
        include "../include/mlos.inc"
    ENDC

; Current program break.
MEM_MANAGER_BRK:
    fdb MLOS_HEAP_START

; -----------------------------------------------------------------
; MEM_MANAGER_INIT
; input:    none
; output:   X = heap start
; clobbers: X
; -----------------------------------------------------------------
MEM_MANAGER_INIT:
    ldx #MLOS_HEAP_START
    stx MEM_MANAGER_BRK
    rts

; -----------------------------------------------------------------
; MEM_MANAGER_GET_BRK
; input:    none
; output:   X = current program break
; clobbers: X
; -----------------------------------------------------------------
MEM_MANAGER_GET_BRK:
    ldx MEM_MANAGER_BRK
    rts

; -----------------------------------------------------------------
; MEM_MANAGER_SBRK
; input:    D = signed byte count delta
; output:   X = previous break, C clear on success
;           X = 0, C set on failure
; clobbers: D, X, Y
; -----------------------------------------------------------------
MEM_MANAGER_SBRK:
    ldx MEM_MANAGER_BRK
    tfr x,y
    leay d,y

    cmpy #MLOS_HEAP_START
    blo .fail
    cmpy #MLOS_HEAP_END
    bhi .fail

    sty MEM_MANAGER_BRK
    andcc #$FE
    rts

.fail:
    ldx #0
    orcc #$01
    rts

; -----------------------------------------------------------------
; MEM_MANAGER_ALLOCATE
; input:    A = number of 256-byte pages to allocate
; output:   X = allocated address, C clear on success
;           X = 0, C set on failure
; clobbers: A, B, D, X, Y
; -----------------------------------------------------------------
MEM_MANAGER_ALLOCATE:
    tsta
    beq MEM_MANAGER_ALLOCATE_FAIL
    cmpa #$80
    bhs MEM_MANAGER_ALLOCATE_FAIL
    tfr a,b
    clra
    ; D = pages * 256 by moving page count into the high byte.
    exg a,b
    bra MEM_MANAGER_SBRK

MEM_MANAGER_ALLOCATE_FAIL:
    ldx #0
    orcc #$01
    rts
