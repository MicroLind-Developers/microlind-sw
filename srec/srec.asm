xtemp   = $00
bioszp  = $c0
zero    = $fe

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
        clr $ff
        clr $fe
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
        sta ,-x
        jsr ECHO
        cmpa #$1b
        beq ESCAPE
        cmpa #$05
        bne NEXTCHAR
        stx xtemp
        ldx #$4000

srec:   jsr PARSE
        bcc 

PARSE:  lda ,-x
        cmpx zero
        bmi 
        cmpa #$0d
        beq PRS4
        cmpa #'S'
        beq PRS1
        jsr ASCIIHEX
        bcs PARSE
        lsla
        lsla
        lsla
        lsla
        sta ,-s
        lda ,-x
        jsr ASCIIHEX
        bcs PRS2
        ora ,s+
        andcc #$fc
        rts
PRS4:   andcc #$fc
        orcc #$02
        rts
PRS5:   ldx #undererr
        jmp ERR
PRS2:   ldx #charerr
        jmp ERR
PRS1:   lda ,-x
        jsr ASCIIHEX
        bcs PRS3
        cmpa #$02
        bmi PRS0
        cmpa #$05
        beq PRS0
        cmpa #$09
        beq PRS0
PRS3:   ldx #headererr
        jmp ERR
PRS0:   andcc #$fc
        orcc #$01
        rts

ASCIIHEX:
        cmpa #'0'
        bmi ASC0
        cmpa #':'
        bmi ASC1
        cmpa #'A'
        bmi ASC0
        cmpa #'F'
        bpl ASC0
        suba #$07
ASC1:   anda #$0f
        andcc #$fe
        rts
ASC0:   orcc #$01
        rts

PRBYTE: sta ,-s
        lsra
        lsra
        lsra
        lsra
        jsr PRHEX
        lda ,s+
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

ERR:    jsr PRINT
        jmp RESET

PRT0:   ldb STATUS
        andb #$40
        beq PRT0
        sta DATA
PRINT:  lda ,x+
        bne PRT0
        rts

headererr:fcn '?unexpected charecter in header'
charerr:fcn '?unexpected charecter'
undererr:fcn '?bufer underrun'

        org $fff0
TRAPv:  FDB RESET
SWI3v:  FDB RESET
SWI2v:  FDB RESET
FIRQv:  FDB RESET
IRQv:   FDB RESET
SWIv:   FDB RESET
NMIv:   FDB RESET
RESETv: FDB RESET
