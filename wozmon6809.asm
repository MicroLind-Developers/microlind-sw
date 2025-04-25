XAML    = $24
XAMH    = $25
STL     = $26
STH     = $27
L       = $28
H       = $29
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
        beq ESCAPE
        ldb MODE
        bitb #%01000000
        beq NOTSTOR
        lda L
        sta [STL]
        ldx STL
        leax 1,x
        stx STL
TONEXTITEM:bra NEXTITEM
RUN:    jmp [XAML]
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
        lda [XAML]
        jsr PRBYTE
XAMNEXT:clr MODE
        ldx XAML
        cmpx L
        bcc TONEXTITEM
        leax 1,x
        stx XAML
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