; Authoritative BIOS image layout. Assemble this file from the bios directory.
; Keep the legacy C jump-table range $F800-$F87F reserved.
    include "../include/io.inc"
    include "../include/memory.inc"

    include "mlbios.asm"
    include "config.asm"
    include "mlfs.asm"
    include "bootstrap.asm"
    include "compactflash.asm"
    include "serial_xr88c92.asm"
    include "mmu.asm"
    include "parallel_6522.asm"
    include "vdc.asm"
    include "irq.asm"
    include "memory.asm"
BIOS_LOW_END:
    ifgt BIOS_LOW_END-$F400
        error "BIOS code overlaps the I/O window"
    endc

    include "module_vectors.asm"
    org $F900
    include "vdc_font.asm"
BIOS_FONT_END:
    ifgt BIOS_FONT_END-$FD00
        error "BIOS font overlaps upper-ROM data"
    endc

    org $FD00
    include "upper_rom.asm"
BIOS_UPPER_END:
    ifgt BIOS_UPPER_END-$FE00
        error "BIOS data overlaps reset code"
    endc

    include "init.asm"
