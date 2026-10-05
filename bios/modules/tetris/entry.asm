    include "../../include/module.inc"
    org MLP_APPLICATION_BASE
; -------------------------------------------------------
;  Preserve BIOS launch context and enter the CMOC runtime.
; -------------------------------------------------------
; input:            X=MBR1 BIOS descriptor; Y=FSR1 filesystem descriptor
; output:           D=application result; caller context restored
; clobbers:         D, W; CC, DP, X, Y, U preserved
; -------------------------------------------------------
TETRIS_ENTRY:
    pshs cc,dp,x,y,u
    stx $04F0
    sty $04F2
    clra
    tfr a,dp
    jsr $0500
    puls cc,dp,x,y,u,pc
    org $04F0
    fdb 0,0
