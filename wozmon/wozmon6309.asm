XAML    = $24
XAMH    = $25
STL     = $26
STH     = $27
L       = $28
H       = $29
XSAV    = $2A
MODE    = $2C

IN      = $0200
DATA    = $c300
STATUS  = $c301
CMD     = $c302
CTRL    = $c303

        ORG $FF00
RESET:  orcc #$50
        lds #$0100
        tfr 0,dp
        lda #$1f
        sta CTRL
        lda #$0b
        sta CMD
NOTCR:  cmpa #'_'+$80
        beq BACKSPACE
        cmpa #$9b
        beq ESCAPE
        cmpx #$0080
        bmi NEXTCHAR
ESCAPE: lda #'\'+$80
        jsr ECHO
GETLINE:lda #$8d
        jsr ECHO
        ldx #$0001
BACKSPACE:leax -1,x
        cmpx #$0000
        bmi GETLINE
NEXTCHAR:lda STATUS
        anda #$08
        beq NEXTCHAR
        lda DATA
        ora #$80
        sta IN,x+
        jsr ECHO
        cmpa #$8d
        bne NOTCR
        ldx #$ffff
        clra
SETSTOR:asla
SETMODE:sta MODE
NEXTITEM:lda IN,x+
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
        stx XSAV
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
        lda IN,x+
        bra NEXTHEX
NOTHEX: cmpx XSAV
        beq ESCAPE
        ldb MODE
        bitb #%01000000
        beq NOTSTOR
        lda L
        sta [STL]
        ldd STL
        incd
        std STL
TONEXTITEM:bra NEXTITEM
RUN:    jmp [XAML]
NOTSTOR:bitb #%10000000
        bne XAMNEXT
        ldy #$0002
SETADR: lda L-1,y
        sta STL-1,y
        sta XAML-1,y
        leay -1,y
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
        ldy XAML
        cmpy L
        bcc TONEXTITEM
        leay 1,y
        sty XAML
        tfr y,b
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
        anda #$10
        beq POLL
        puls a
        rts