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
        lda #$c1
        sta STATUS
        lda #$0d
        sta CTRL
        lda #$f0
        sta CTRL
NEXTCHAR:lda STATUS
        anda #$01
        beq NEXTCHAR
        lda DATA
	sta $0010
	lda $0010
	jsr ECHO
*	lda $10
*	jsr ECHO
	bra NEXTCHAR

ECHO:   ldb STATUS
        andb #$40
        beq ECHO
        sta DATA
        rts

	org $fff0
TRAPv:  FDB RESET
SWI3v:  FDB RESET
SWI2v:  FDB RESET
FIRQv:  FDB RESET
IRQv:   FDB RESET
SWIv:   FDB RESET
NMIv:   FDB RESET
RESETv: FDB RESET

