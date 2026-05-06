; -----------------------------------------------------------------
; MLOS syscall dispatcher
; -----------------------------------------------------------------
; Register ABI for the first-stage dispatcher:
;   A = syscall number
;   B = small argument / exit code / character
;   X = arg0 pointer or value
;   Y = arg1 pointer or value
;
; Return:
;   D or X, depending on syscall, C clear on success
;   D = negative SYS_E* value, C set on failure
; -----------------------------------------------------------------

    IFNDEF MLOS_INC
        include "../include/mlos.inc"
    ENDC

    IFNDEF MLOS_SYSCALL_INC
        include "../include/syscall.inc"
    ENDC

MLOS_SYSCALL_DISPATCH:
    cmpa #SYS_EXIT
    beq .exit
    cmpa #SYS_PUTC
    beq .putc
    cmpa #SYS_WRITE
    beq .write
    cmpa #SYS_READ
    beq .read
    cmpa #SYS_SBRK
    beq .sbrk
    cmpa #SYS_TICKS
    beq .ticks
    bra .enosys

.exit:
    jmp MLOS_HALT

.putc:
    tfr b,a
    jsr BIOS_SERIAL_PUTC
    clra
    clrb
    andcc #$FE
    rts

.write:
    ; X = NUL-terminated string for now. Y/len is reserved for the later
    ; counted-buffer implementation.
    jsr BIOS_SERIAL_PRINT
    clra
    clrb
    andcc #$FE
    rts

.read:
    ; X = buffer, Y = size
    jsr BIOS_SERIAL_INPUT
    clra
    clrb
    andcc #$FE
    rts

.sbrk:
    ; X carries a 16-bit delta for this dispatcher entry.
    tfr x,d
    jsr MEM_MANAGER_SBRK
    rts

.ticks:
    ; Timer support is not wired yet.
    clra
    clrb
    andcc #$FE
    rts

.enosys:
    ldd #SYS_ENOSYS
    orcc #$01
    rts
