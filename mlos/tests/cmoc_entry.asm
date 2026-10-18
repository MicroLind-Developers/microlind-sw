    org $0400
; Function: cmoc_test_entry — temporary S02 CMOC fixture startup.
; Inputs: core initialized, native application maps/stack. Outputs: TEST_RESULT.
; Clobbers: application registers. Stack: CMOC program <1KiB; no resume/exit ABI.
cmoc_test_entry:
    jsr $0420
    cmpd #0
    bne cmoc_failed
    lda #$A5
    sta $C008
cmoc_done:
    bra cmoc_done
cmoc_failed:
    stb $C009
    lda #$FF
    sta $C008
    bra cmoc_failed
