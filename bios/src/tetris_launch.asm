    include "../include/filesystem.inc"
; -------------------------------------------------------
;  Initialize the filesystem extension and launch the CF-loaded game.
; -------------------------------------------------------
; input:            Initialized BIOS hardware and an MLFS card in CF
; output:           Returns after game exit; serial loader error on failure
; clobbers:         D, W, X, Y, U, CC; DP and caller interrupt masks preserved
; -------------------------------------------------------
BIOS_LOAD_TETRIS_UTIL:
    ldx #BL_FS_NAME
    clrb
    ldy #1
    jsr BIOS_RUN_MODULE
    bcs BIOS_TETRIS_LOAD_ERROR
    ldx #BL_TETRIS_NAME
    ldb #MLP_KIND_APPLICATION
    ldy #FS_API_BASE
    jsr BIOS_RUN_MODULE
    bcs BIOS_TETRIS_LOAD_ERROR
    rts
; -------------------------------------------------------
;  Report a module loader failure through the existing serial error path.
; -------------------------------------------------------
; input:            A=MLP_ERR_*; S points to utility return address
; output:           Error printed; returns to BIOS menu caller
; clobbers:         D, X, CC
; -------------------------------------------------------
BIOS_TETRIS_LOAD_ERROR:
    jmp BIOS_LOAD_FS_ERROR
BL_TETRIS_NAME: fcn "/tetris.mlp"
msg_text8: fcc "8. Tetris"
    fcb 10,13,0
