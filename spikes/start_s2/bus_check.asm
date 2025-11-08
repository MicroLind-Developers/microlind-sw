    org $FF00
hook_trap:
hook_swi3:
hook_swi2:
hook_swi:
hook_firq:
hook_irq:
hook_nmi:
hook_restart:
    lda #$5A
    lda #$A5
    ldx #$55AA
    ldx #$AA55
    ldq #$AA55AA55
    ldq #$55AA55AA
    jmp hook_restart

    org $FFF0

vtrap: fdb hook_trap
vswi3: fdb hook_swi3
vswi2: fdb hook_swi2
vfirq: fdb hook_firq
virq: fdb hook_irq
vswi: fdb hook_swi
vnmi: fdb hook_nmi
vrestart: fdb hook_restart