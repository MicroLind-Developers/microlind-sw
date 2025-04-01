XAML    = $24
XAMH    = $25
STL     = $26
STH     = $27
L       = $28
H       = $29
XSAV    = $2A
MODE    = $2C

IN      = $0400
DATA    = $F400
STATUS  = $f401
CMD     = $f402
CTRL    = $f403

        ORG $FD00
RESET:  
        lds #$0200              ;Set system stack pointer to bottom of stack
        jsr INIT
        jsr SERIAL_INIT_A
WAIT:
        jsr SERIAL_INPUT_A
        cmpa #$0d
        bne WAIT
        ldx #STRING
        jsr SERIAL_PRINT_A

NOTCR:  
        cmpa #'_'+$80
        beq BACKSPACE
        cmpa #$9b
        beq ESCAPE
        cmpx #$0080
        bmi NEXTCHAR
ESCAPE: 
        lda #'\'+$80
        jsr ECHO
GETLINE:
        lda #$8d
        jsr ECHO
        ldx #$0001
BACKSPACE:
        leax -1,x
        cmpx #$0000
        bmi GETLINE
NEXTCHAR:
        lda STATUS
        anda #$08
        beq NEXTCHAR
        lda DATA
        ora #$80
        sta IN,x
        leax 1,x
        jsr ECHO
        cmpa #$8d
        bne NOTCR
        ldx #$ffff
        clra
SETSTOR:
        asla
SETMODE:
        sta MODE
NEXTITEM:
        lda IN,x
        leax 1,x
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
NEXTHEX:
        eora #$b0
        cmpa #$fa
        bcs DIG
        adda #$89
        cmpa #$fa
        bcs NOTHEX
DIG:    
        asla
        asla
        asla
        asla
        ldb #$04
HEXSHIFT:
        asla
        rol L
        rol H
        decb
        bne HEXSHIFT
        lda IN,x
        leax 1,x
        bra NEXTHEX
NOTHEX: 
        cmpx XSAV
        beq ESCAPE
        ldb MODE
        bitb #%01000000
        beq NOTSTOR
        lda L
        sta [STL]
        ldd STL
        incd
        std STL
TONEXTITEM:
        bra NEXTITEM
RUN:    
        jmp [XAML]
NOTSTOR:
        bitb #%10000000
        bne XAMNEXT
        ldy #$0002
SETADR: 
        lda L-1,y
        sta STL-1,y
        sta XAML-1,y
        leay -1,y
        bne SETADR
NXTPRNT:
        bne PRDATA
        lda #$8d
        jsr ECHO
        lda XAMH
        jsr PRBYTE
        lda XAML
        jsr PRBYTE
        lda #':'+$80
        jsr ECHO
PRDATA: 
        lda #$a0
        jsr ECHO
        lda [XAML]
        jsr PRBYTE
XAMNEXT:
        clr MODE
        ldy XAML
        cmpy L
        bcc TONEXTITEM
        leay 1,y
        sty XAML
        tfr y,b
        andb #$0f
        bra NXTPRNT
PRBYTE: 
        pshs a
        lsra
        lsra
        lsra
        lsra
        jsr PRHEX
        puls a
PRHEX:  
        anda #$0f
        ora #'0'+$80
        cmpa #$ba
        bcs ECHO
        adda #$07
ECHO:   
        pshs a
        anda #$7f
        sta DATA
POLL:   
        lda STATUS
        anda #$10
        beq POLL
        puls a
        rts

INIT:
    jsr CLEAR_REGS
    orcc #$50       ; Turn off IRQ
    lda #$c0
    tfr a,dp
    rts

CLEAR_REGS:
    ldq     #$00000000
    tfr     a,dp
    tfr     d,x
    tfr     d,y
    tfr     d,u
    tfr     d,v
    andcc   #$00
    rts

str_greet:
    fcn 'microLind initialized...'
STRING:
    FCB $1B,'[','3','7',';','4','1','m' ; ANSI escape sequence for red color
    FCC "Hello, World!"         ; The actual text
    FCB $1B,'[','0','m'      ; ANSI escape sequence to reset color
    FCB 0