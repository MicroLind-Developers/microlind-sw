    org $0400
; Function: application_start. Inputs D=argc,X=argv from loader. Outputs exit
; through SYS_EXIT after CMOC CRT/main. Clobbers process registers; native mode.
; Fixed private argument words are per-process; S05 loader owns stack placement.
application_start:
    std $0300
    stx $0302
    jsr $0420
    std $0304
    ldx #$0304
    lda #12
    swi
app_exit_wait:
    bra app_exit_wait
