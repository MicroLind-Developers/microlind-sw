XAML    = $24
XAMH    = $25
STL     = $26
STH     = $27
L       = $28
H       = $29
YSAV    = $2A
MODE    = $2C

IN      = $0200
DATA    = $c300
STATUS  = $c301
CMD     = $c302
CTRL    = $c303

        ORG $FF00
RESET:  orcc #$50
        lda #$1f
        sta CTRL
        lda #$0b
        sta CMD
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
        anda #$08
        beq NEXTCHAR
        lda DATA
        ora #$80
        sta IN,y+
        jsr ECHO
        cmpa #$8d
        bne NOTCR
        ldy #$ffff
        clrw
        clra
SETSTOR:asla
SETMODE:sta MODE
NEXTITEM:lda IN,y+
        cmpa #$8d
        beq GETLINE
        cmpa #'.'+$80
        bcs NEXTITEM
        beq SETMODE
        cmpa #':'+$80
        beq SETSTOR
        cmpa #'R'+$80
        beq RUN
        stw L
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
        lda IN,y+
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
XAMNEXT:ste MODE
        ldx XAML
        cmpx L
        bcc TONEXTITEM
        leax 1,x
        stx XAML
        tfr x,b
        andb #$0f
        bra NXTPRNT
PRBYTE: sta ,-s
        lsra
        lsra
        lsra
        lsra
        jsr PRHEX
        lda ,s+
PRHEX:  anda #$0f
        ora #'0'+$80
        cmpa #$ba
        bcs ECHO
        adda #$07
ECHO:   sta ,-s
        anda #$7f
        sta DATA
POLL:   lda STATUS
        anda #$10
        beq POLL
        lda ,s+
        rts