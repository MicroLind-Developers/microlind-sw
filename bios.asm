        
        include io.asm
                
        * 65c22 at $f780*
ORB_22  = $f780
ORA_22  = $f781
DDRA_22 = $f782
DDRB_22 = $f783
ACR_22  = $f78b
PCR_22  = $f78c
IFR_22  = $f78d
IER_22  = $f78e

        *68c681 at $f7c0*
        *Port A registers*
MRnA_681 = $f7c0
SRA_681 = $f7c1
CSRA_681 = $f7c1
CRA_681 = $f7c2
RHRA_681 = $f7c3
THRA_681 = $f7c3
        *Interupt, timer, and control registers*
ACR_681 = $f7c4
MISR_681 = $f7c2
ISR_681 = $f7c5
IMR_681 = $f7c5
CTU_681 = $f7c6
CTL_681 = $f7c7
        *Port B registers*
MRnB_681 = $f7c8
SRB_681 = $f7c9
CSRB_681 = $f7c9
CRB_681 = $f7ca
RHRB_681 = $f7cb
THRB_681 = $f7cb
        *IP & OP data and control registers*
IPCR_681 = $f7c4
IP_681  = $f7cd
OPCD_681 = $f7cd
SOP_681 = $f7ce
COP_681 = $f7cf
MMU0    = $f440

        *MMU at $f440*
MMU1    = $f441
MMU2    = $f442
MMU3    = $f443

        *bios constants and variables*
bioszp  = $c0
sinit   = $e000

        org $f800 *Jumptable*
init:   jmp init_
ppinit: jmp init22
serinit:jmp init681
meminit:jmp initmemmap
setbank:jmp movb
multibank:jmp superb
jsrbank:jmp process
rmbank: jmp 

init_:  orcc #$50
        clra
        sta MMU3
        lds #sinit
        jsr init681
        jsr init22
        jsr initmemmap
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

initmemmap:pshs cc,a
        orcc #$50
        clra
        sta MMU3
        inca
        sta MMU0
        inca
        sta MMU1
        inca
        sta MMU2
        puls cc,a
        rts

movb:   pshs cc,x
        orcc #$50
        anda #$03
        ldx #MMU0+$80
        stb a,x
        puls cc,x
        rts

superb: pshs cc,dp,x,b
        orcc #$50
        ldb #bioszp
        tfr b,dp
        ldx #MMU0
        clr $00
        inc $00
        bra sup1
sup0:   lsl $00
        leax 1,x
        cmpx #MMU0+$04
        beq sup2
sup1:   bita $00
        beq sup0
        ldb ,u+
        stb ,x
        bra sup0
sup2:   puls cc,dp,x,b
        rts

process:pshs u,y,x,dp,b,a,cc
        orcc #$50
        stx $100*bioszp
        sta $100*bioszp+2
        ld
        ldx MMU0
        stx ,--s
        ldx MMU2
        stx ,--s
        anda #$07
        jsr superb
        lda $100*bioszp+2
        ldx $100*bioszp
        bita #%00001000
        beq prc1
        stb MMU3
prc1:   bcs prc0
        pulu x,dp,b,a,cc
prc0:   jsr ,y
        ldx ,s++
        stx MMU2
        ldx ,s++
        stx MMU0
        puls cc,a,b,dp,x,y,u,pc

tfrb:   tfr cc,dp
        orcc #$50
        ldx ,u++
        stx ,s--
        stx $100*bioszp
        ldx ,u++
        stx ,s--
        stx $10*bioszp+2
        ldb ,s+
        bita #%00000001
        beq tfr0
        stb MMU0
tfr0:   ldb ,s+
        bita #%00000010
        beq tfr1
        stb MMU1
tfr1:   
        ldb ,s+
        bita #%00000001
        beq tfr2
        stb MMU2
tfr2:   ldb ,s+
        bita #%00000010
        beq tfr3
        stb MMU3
tfr3:   ldy ,s++
        tfr dp,cc
        jmp ,y


