; Boot diagnostics and menu prompt live outside the CPU vector-table page.
msg_vdc_present:
    fcc " * VDC text console ready."
    fcb 10,13,0
msg_no_vdc:
    fcc " * No VDC; serial console."
    fcb 10,13,0
msg_cf_present:
    fcc " * CompactFlash ready."
    fcb 10,13,0
msg_no_cf:
    fcc " * CompactFlash unavailable."
    fcb 10,13,0
msg_prompt0:
    fcc "  Press a number to continue... "
    fcb 10,13,0

msg_text7:
    fcc "7. Load MLFS extension"
    fcb 10,13,0
BL_FS_NAME:
    fcn "/biosfs.mlp"
BL_LOAD_ERROR:
    fcn "Module load error: "

; No cached extension yet: always reload, including after a destructive RAM test.
BIOS_LOAD_FS_UTIL:
    ldx #BL_FS_NAME
    clrb
    ldy #0
    jsr BIOS_RUN_MODULE
    bcc BIOS_LOAD_FS_DONE
BIOS_LOAD_FS_ERROR:
    pshs a
    ldx #BL_LOAD_ERROR
    jsr SERIAL_PRINT_A
    puls a
    jsr SERIAL_PRINT_BYTE_HEX_A
    jsr SERIAL_PRINT_CRLF_A
BIOS_LOAD_FS_DONE:
    rts
