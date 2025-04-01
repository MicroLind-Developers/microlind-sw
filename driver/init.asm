; -----------------------------------------------------------------
; Bios init functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024
;

STACK EQU $E000

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

    ; Set up the stack
	lds #STACK

	; Initialize the MMU, must be done first
    ; jsr MMU_INIT

	; Initialize the serial port
	; jsr SERIAL_INIT

	; Initialize the parallel port
	; jsr PARALLEL_INIT

	; Initialize the IRQ
	; jsr IRQ_INIT

    lbra _START


CPU_DETECTION:
	

HANG:
    bra HANG







    org $FFF0

vtrap: fdb hook_trap
vswi3: fdb hook_swi3
vswi2: fdb hook_swi2
vfirq: fdb hook_firq
virq: fdb hook_irq
vswi: fdb hook_swi
vnmi: fdb hook_nmi
vrestart: fdb hook_restart