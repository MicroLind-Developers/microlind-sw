; Target profile configuration. Tick frequency=3686400/(32*preload).
    ifndef MLOS_QUANTUM_TICKS
MLOS_QUANTUM_TICKS equ 5
    endc
    ifndef MLOS_TIMER_PRELOAD
MLOS_TIMER_PRELOAD equ 115
    endc
    iflt MLOS_QUANTUM_TICKS-1
    error "Quantum must be1..255 ticks"
    endc
    ifgt MLOS_QUANTUM_TICKS-255
    error "Quantum must be1..255 ticks"
    endc
    iflt MLOS_TIMER_PRELOAD-1
    error "Timer preload must be1..65535"
    endc
    ifgt MLOS_TIMER_PRELOAD-65535
    error "Timer preload must be1..65535"
    endc

; Bounded initialized/BSS image bytes per loader safe point. Register subtotal
; checksum supports at most128 bytes; sector and window boundaries split runs.
    ifndef MLOS_LOADER_QUOTA
MLOS_LOADER_QUOTA equ 128
    endc
    iflt MLOS_LOADER_QUOTA-1
    error "Loader quota must be1..128 bytes"
    endc
    ifgt MLOS_LOADER_QUOTA-128
    error "Loader quota must be1..128 bytes"
    endc

; Bounded CF PIO bytes per device per safe point; divide512 exactly.
    ifndef MLOS_IO_QUOTA
MLOS_IO_QUOTA equ 128
    endc
    iflt MLOS_IO_QUOTA-1
    error "I/O quota must be1..256 bytes"
    endc
    ifgt MLOS_IO_QUOTA-256
    error "I/O quota must be1..256 bytes"
    endc
    ifne 512%MLOS_IO_QUOTA
    error "I/O quota must divide512"
    endc
