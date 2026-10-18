MLOS_RUNTIME equ 1
    include "layout.inc"
    include "syscalls.inc"
    include "hardware.inc"
    include "rom.inc"
    include "runtime/state.inc"
    org 0
    jmp >runtime_init
    jmp >syscall_dispatch
    jmp >runtime_tick
    jmp >runtime_trap
    jmp >runtime_finish
    include "memory.asm"
    include "copy.asm"
    include "syscalls.asm"
    include "runtime/process.asm"
    include "runtime/scheduler.asm"
    include "runtime/calls.asm"
    include "runtime/heap.asm"
    include "runtime/ipc.asm"
    include "runtime/wait.asm"
    include "runtime/services.asm"
    include "runtime/backplane.asm"
    include "runtime/driver.asm"
    include "runtime/modules.asm"
    include "runtime/arguments.asm"
    include "runtime/tty.asm"
    include "runtime/namespace.asm"
; Function: runtime_init. Inputs validated BOOT_INFO. Outputs first process RTI.
; Clobbers all; nonreturning privileged boot, bounded allocations/load failures.
runtime_init:
    lda #1
    sta BOOT_FEEDBACK_ACTIVE
    ldd #BOOT_FEEDBACK_INTERVAL
    std BOOT_FEEDBACK_NEXT
    ldb #BOOT_MSG_CORE
    jsr ROM_BOOT_STATUS
    jsr process_init
    jsr backplane_init
    jsr driver_init
    lbcs runtime_boot_error
    ldd #$A55A
    std KERNEL_CANARY
    std EMERGENCY_CANARY
    ldx #KERNEL_CANARY+2
    ldy #KERNEL_STACK-KERNEL_CANARY-2
    lda #$CD
runtime_fill_kernel:
    sta ,x+
    leay -1,y
    bne runtime_fill_kernel
    ldx #EMERGENCY_CANARY+2
    ldy #EMERGENCY_STACK-EMERGENCY_CANARY-2
    lda #$EE
runtime_fill_emergency:
    sta ,x+
    leay -1,y
    bne runtime_fill_emergency
    ldx #runtime_init_name
    clrb
    jsr process_spawn
    bcs runtime_boot_error
    inc SCHED_PENDING
    jsr runtime_finish
    jsr ROM_TIMER_ENABLE
    jmp ROM_START_APP
runtime_boot_error:
    lda #'L'
    jsr ROM_PUTC
    lda #$41
    jmp ROM_PANIC
runtime_init_name:
    fcn "init.mlx"
CORE_END equ *
    ifgt CORE_END-$3800
    error "Core code overlaps banked handle metadata"
    endc
