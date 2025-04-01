        
        include io.asm

        org $f800 *Jumptable*
init:   jmp init_
ppinit: jmp init22
serinit:jmp init681

init_:  orcc #$50
        lds #$0100
        jsr init681
        jsr init22
        rts
init681:lda #$0a
        sta CRA_681
        sta CRB_681
        clra
        sta IMR_681
        sta OPCR_681
        lda #$80
        sta ACR_681
        lda #$53
        sta MRnA_681
        sta MRnB_681
        lda #$07
        sta MRnA_681
        sta MRnB_681
        rts
init22: clra
        sta DDRA_22
        sta DDRB_22
        sta ACR_22
        sta PCR_22
        lda #$7f
        sta IER_22
        rts