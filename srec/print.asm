xtemp   = $00
bioszp  = $c0

DATA    = $f7c3
STATUS  = $f7c0
CTRL    = $f7c1

        org $e000
RESET:  orcc #$50
        lds #$e000
        lda #bioszp
        tfr a,dp
        lda #$c1
        sta STATUS
        lda #$0d
        sta CTRL
        lda #$f0
        sta CTRL
        lda #$0d
        jsr ECHO
        ldx #text
        jsr PRINT
ESCAPE: ldx #$3fff
        lda #$0d
        jsr ECHO
        lda #'>'
BACKSPACE:leax 1,x
        cmpx #$4001
        bpl ESCAPE
        jsr ECHO
NEXTCHAR:lda STATUS
        anda #$01
        beq NEXTCHAR
        lda DATA
        cmpx #$0000
        beq ESCAPE
        cmpa #$7f
        beq BACKSPACE
        cmpa #$07
        beq RESET
        sta ,-x
        jsr ECHO
        cmpa #$1b
        beq ESCAPE
        cmpa #$0d
        bne NEXTCHAR
        lda #$00
        sta ,-x
        stx xtemp
        ldx #$4000
        jsr NPRINT
        bra ESCAPE

NPRT0:  ldb STATUS
        andb #$40
        beq NPRT0
        sta DATA
NPRINT: lda ,-x
        bne NPRT0
        rts

PRT0:   ldb STATUS
        andb #$40
        beq PRT0
        sta DATA
PRINT:  lda ,x+
        bne PRT0
        rts

PRBYTE: tfr a,e
        lsra
        lsra
        lsra
        lsra
        jsr PRHEX
        tfr e,a
PRHEX:  anda #$0f
        ora #'0'
        cmpa #$3a
        bcs ECHO
        adda #$07
ECHO:   ldb STATUS
        andb #$40
        beq ECHO
        sta DATA
        rts

text:   fcc '  **** Microlind Rev A0 Monitor v0.1 ****  '
        fcb $0d
        fcc ' 56k RAM system  507904 Monitor bytes free '
        fcb $0d,$00

        org $fff0
TRAPv:  FDB RESET
SWI3v:  FDB RESET
SWI2v:  FDB RESET
FIRQv:  FDB RESET
IRQv:   FDB RESET
SWIv:   FDB RESET
NMIv:   FDB RESET
RESETv: FDB RESET
