; BIOS module entry preserves the launcher's context around CMOC's CRT.
    include "../../include/module.inc"
    org MLP_APPLICATION_BASE
    pshs cc,dp,x,y,u
    leax BIOS_MODULE_SERIAL_PUTC-BIOS_MODULE_API_BASE,x
    stx $041C
    clra
    tfr a,dp
    jsr $0420
    puls cc,dp,x,y,u,pc
    org $041C
    fdb 0
