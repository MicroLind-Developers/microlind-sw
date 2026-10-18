; Storage backend defaults: native privileged ROM, DP0, common mapped; serialized.
; All polls are bounded. No process pointer is retained; caller owns a 512-byte
; mapped buffer for the duration. Q is LBA28, hardware geometry comes from IDENTIFY.
CF_NATIVE_TFM equ 1
CF_BASE equ $F418
IO_INC equ 1
MEMORY_INC equ 1
STORAGE_BUFFER_START equ BOOT_BUFFER
STORAGE_BUFFER_SIZE equ 512
    include "../driver/compactflash.asm"

; Function: boot_read / boot_write. Inputs: Q=LBA, X=buffer512. Outputs: C/D.
; Clobbers: D,X,CC; preserves Y,U,W. Reject device bounds before command writes.
boot_read:
    pshs d
    cmpd BOOT_SECTORS
    blo br_valid
    bhi br_bad
    cmpw BOOT_SECTORS+2
    bhs br_bad
br_valid:
    puls d
    jmp CF_READ_SECTOR
br_bad:
    puls d
    ldd #-9
    orcc #1
    rts
boot_write:
    cmpd BOOT_SECTORS
    blo bw_valid
    bhi bw_bad
    cmpw BOOT_SECTORS+2
    bhs bw_bad
bw_valid:
    jmp CF_WRITE_SECTOR
bw_bad:
    ldd #-9
    orcc #1
    rts

; Function: boot_identify. Inputs: privileged UART/MMU initialized. Outputs:
; BOOT_SECTORS u32, C0 or C1. Clobbers D,W,X,Y,U; stack<=12. No filesystem use.
boot_identify:
    jsr CF_INIT
    bcs bi_bad
    lda #$EC
    sta CF_COMMAND
    jsr CF_WAIT_DRQ
    bcs bi_bad
    ldx #BOOT_BUFFER
    ldy #512
bi_bytes:
    lda CF_DATA
    sta ,x+
    leay -1,y
    bne bi_bytes
    lda BOOT_BUFFER+123
    ldb BOOT_BUFFER+122
    std BOOT_SECTORS
    lda BOOT_BUFFER+121
    ldb BOOT_BUFFER+120
    std BOOT_SECTORS+2
    ldq BOOT_SECTORS
    bita #$F0
    bne bi_bad
    tstd
    bne bi_ok
    cmpw #2
    blo bi_bad
bi_ok:
    andcc #$FE
    rts
bi_bad:
    orcc #1
    rts
