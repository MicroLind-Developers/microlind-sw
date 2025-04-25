XAML    = $25
XAMH    = $24
STL     = $27
STH     = $26
L       = $29
H       = $28
YSAV    = $2A
MODE    = $2C

IN      = $0200
DATA    = $f7c3
STATUS  = $f7c0
CTRL    = $f7c1
        org $e000
        fill $00,$1dff
        org $FE00
RESET:  orcc #$50
        lds #$0100
        clra
        tfr a,dp
        lda #$7f
        sta STATUS
        lda #$0d
        sta CTRL
        lda #$f0
        sta CTRL
NOTCR:  cmpa #'_'+$80
        beq BACKSPACE
        cmpa #$9b
        beq ESCAPE
*        lda #'L'+$80    #
*        jsr ECHO        #
        cmpy #$0080
        bmi NEXTCHAR
ESCAPE: lda #'\'+$80
        jsr ECHO
GETLINE:lda #$8d
        jsr ECHO
        ldy #$0001
BACKSPACE:leay -1,y
        cmpy #$0000
        bmi GETLINE
NEXTCHAR:lda STATUS
        anda #$01
        beq NEXTCHAR
        lda DATA
        ora #$80
        sta IN,y
        leay 1,y
        jsr ECHO
        cmpa #$8d
        bne NOTCR
*        lda #'E'+$80    #DEBUG#
*        jsr ECHO        #DEBUG#
        ldy #$ffff
        clra
SETSTOR:asla
SETMODE:sta MODE
NEXTITEM:lda IN,y
        leay 1,y
        cmpa #$8d
        beq GETLINE
        cmpa #'.'+$80
        bcs NEXTITEM
        beq SETMODE
        cmpa #':'+$80
        beq SETSTOR
        cmpa #'R'+$80
        beq RUN
        clr L
        clr H
        sty YSAV
NEXTHEX:eora #$b0
        cmpa #$fa
        bcs DIG
        adda #$89
        cmpa #$fa
        bcs NOTHEX
DIG:    asla
        asla
        asla
        asla
        ldb #$04
HEXSHIFT:asla
        rol L
        rol H
        decb
        bne HEXSHIFT
        lda IN,y
        leay 1,y
        bra NEXTHEX
NOTHEX: cmpy YSAV
        lbeq ESCAPE
        ldb MODE
        bitb #%01000000
        beq NOTSTOR
        lda L
        sta [STH]
        ldx STH
        leax 1,x
        stx STH
TONEXTITEM:bra NEXTITEM
RUN:    jmp [XAMH]
NOTSTOR:bitb #%10000000
        bne XAMNEXT
        ldx #$0002
SETADR: lda L-1,x
        sta STL-1,x
        sta XAML-1,x
        leax -1,x
        bne SETADR
NXTPRNT:bne PRDATA
        lda #$8d
        jsr ECHO
        lda XAMH
        jsr PRBYTE
        lda XAML
        jsr PRBYTE
        lda #':'+$80
        jsr ECHO
PRDATA: lda #$a0
        jsr ECHO
        lda [XAMH]
        jsr PRBYTE
XAMNEXT:clr MODE
        ldx XAMH
        cmpx H
        bcc TONEXTITEM
        leax 1,x
        stx XAMH
        tfr x,b
        andb #$0f
        bra NXTPRNT
PRBYTE: pshs a
        lsra
        lsra
        lsra
        lsra
        jsr PRHEX
        puls a
PRHEX:  anda #$0f
        ora #'0'+$80
        cmpa #$ba
        bcs ECHO
        adda #$07
ECHO:   pshs a
        anda #$7f
        sta DATA
POLL:   lda STATUS
        anda #$40
        beq POLL
        puls a
        rts

        include boot.asm