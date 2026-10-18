; Function: arguments_copy. Inputs copied spawn params argc byte,argv pointer.
; Outputs kernel-owned128-byte argv snapshot with relative string offsets.
; Clobbers all; stack<=40; <=8 arguments and110 string bytes including NULs.
; No borrowed caller pointer survives image loading/publication.
arguments_copy:
    lda PARAM_BUFFER+3
    cmpa #8
    lbhi rx_invalid
    sta ARGC
    ldx #ARG_BUFFER
    ldy #128
arg_clear:
    clr ,x+
    leay -1,y
    bne arg_clear
    lda #18
    sta ARG_USED
    clr ARG_INDEX
    ldd PARAM_BUFFER+4
    std ARG_VECTOR
arg_next:
    lda ARG_INDEX
    cmpa ARGC
    bhs arg_done
    ldx ARG_VECTOR
    ldy #COPY_BUFFER
    ldd #2
    jsr copy_in
    bcs arg_return
    ldd COPY_BUFFER
    std ARG_SOURCE
    ldd ARG_VECTOR
    addd #2
    std ARG_VECTOR
    ldx #ARG_BUFFER
    ldb ARG_INDEX
    lslb
    abx
    clra
    ldb ARG_USED
    std ,x
arg_string:
    ldb ARG_USED
    cmpb #128
    bhs arg_too_long
    ldy #ARG_BUFFER
    leay b,y
    ldx ARG_SOURCE
    ldd #1
    jsr copy_in
    bcs arg_return
    ldb ARG_USED
    ldx #ARG_BUFFER
    lda b,x
    inc ARG_USED
    ldd ARG_SOURCE
    addd #1
    std ARG_SOURCE
    ldb ARG_USED
    decb
    lda b,x
    tsta
    bne arg_string
    inc ARG_INDEX
    bra arg_next
arg_done:
    ldd #0
    andcc #$FE
arg_return:
    rts
arg_too_long:
    ldd #SYS_ENAMETOOLONG
    orcc #1
    rts

; Function: arguments_install. Inputs validated loaded child/stack, argument
; snapshot. Outputs argc in D slot, argv in X slot; copies128 bytes above stack.
; Clobbers all; stack<=12. Called before READY publication; no failure after admission.
arguments_install:
    ldu LOADER_PROC
    ldd LOADER_HEADER+10
    std LOADER_DEST
    std P_CONTEXT+N_X,u
    clra
    ldb ARGC
    std P_CONTEXT+N_A,u
    clr ARG_INDEX
ai_relocate:
    lda ARG_INDEX
    cmpa ARGC
    bhs ai_copy_start
    ldb ARG_INDEX
    lslb
    ldx #ARG_BUFFER
    abx
    ldd ,x
    addd LOADER_HEADER+10
    std ,x
    inc ARG_INDEX
    bra ai_relocate
ai_copy_start:
    ldd #ARG_BUFFER
    std LOADER_SEG
    ldd #128
    std LOADER_COUNT
ai_copy:
    ldx LOADER_SEG
    lda ,x+
    stx LOADER_SEG
    jsr image_store
    ldd LOADER_COUNT
    subd #1
    std LOADER_COUNT
    bne ai_copy
    rts
