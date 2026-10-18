    include "layout.inc"
    include "syscalls.inc"
    include "hardware.inc"
    include "rom.inc"
    org CORE_START
    jmp >core_init
    jmp >syscall_dispatch
    include "memory.asm"
    include "copy.asm"
    include "syscalls.asm"

; Function: core_init — initialize the S02 single-process core.
; Inputs: native mode, bank0=0/common=1, ROM has loaded app frame3.
; Outputs: starts application via fixed ROM; no return. Clobbers: all.
; Context: privileged boot; nonreentrant, IRQ/FIRQ masked; common stack.
; Ownership: reserves whole frames0/1/2; app3 resident for PID1.
core_init:
    jsr memory_init
    ldd #$A55A
    std KERNEL_CANARY
    std EMERGENCY_CANARY
    jsr core_selftest
    lbcs core_failed
    lda #$10
    sta TEST_STEP
    jmp ROM_START_APP
core_failed:
    lda #$21
    jmp ROM_PANIC

    include "selftest.asm"
CORE_END equ *
    ifgt CORE_END-$4000
    error "MLOS core exceeds physical frame 0"
    endc
