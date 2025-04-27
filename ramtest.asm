; Name:     ramtest
; Purpose:  Test a RAM (read/write memory) area as follows:
;            1) Write all O and test
;            2) Write all 11111111 binary and test
;            3) Write all 10101010 binary and test
;            4) Write all 01010101 binary and test
;            5) Shift a single 1 through each bit,
;               while clearing all other bits
; Entry:    Stack in order from top:
;            * HB of return address
;            * LB of return address
;            * HB area size (bytes)
;            * LB area size (bytes)
;            * HB base of area
;            * LB base of area
;Exit       If no errors: 
;            * carry = 0
;           Else:
;            * carry = 1
;            * X = address at fault
;            * A = test value
;Registers used:
;           CC, X, Y
    ORG $FF30

ramtest:
    puls    u           ;Save return address
    andcc   #$fe        ;Clear Carry, Indicate no error
    ldx     ,s          ;Get area size
    beq     exitrt      ;Exit if area = 0

    ;Fill memory with 0x00 and test
    clra                ;Get zero value
    bsr     filcmp      ;Fill and test memory
    bcs     exitrt      ;Exit if errors

    ;Fill memory with 0xFF and test
    lda     #$FF        ;Get FF value
    bsr     filcmp      ;Fill and test memory
    bcs     exitrt      ;Exit if errors

    ;Fill memory with 0x55 and test
    lda     #$55        ;Get 55 value (01010101)
    bsr     filcmp      ;Fill and test memory
    bcs     exitrt      ;Exit if errors

    ;Fill memory with 0xAA and test
    lda     #$AA        ;Get AA value (10101010)
    bsr     filcmp      ;Fill and test memory
    bcs     exitrt      ;Exit if errors

    ;Perform walkin bit test. Place a 1 in bit 7 and
    ;see if it can be read back. Then move it down 
    ;thru all bit positions and repeat test.
    ldx     2,s         ;Get base address of test area
    ldy     ,s          ;Get area size in bytes
    clrb                ;Get 0 in B

walklp:
    lda     #%10000000  ;Make bit 7 a 1
walklp1:
    sta     ,x          ;Store test pattern in memory
    cmpa    ,x          ;read and compare
    bne     exitcs      ;Exit if errors
    lsra                ;Bitshift pattern
    bne     walklp1     ;Repeat test with shifted pattern
                        ;until pattern is 00000000
    stb     ,x+         ;clear byte just checked
    leay    -1,y        ;decrement counter
    bne     walklp      ;continue check on next byte
                        ;until counter is 0
    andcc   #$fe        ;Clear Carry, Indicate no error
    bra     exitrt

    ;Found error, set carry
exitcs:
    orcc    #$01        ;Set Carry

    ;Remove parameters from stack and exit
exitrt:
    leas    4,s         ;Remove parameters from stack
    jmp     ,u          ;Exit to return address


;Name: filcmp
;Purpose:   Fill memory with a test value and
;           test that it can be read back correct.
;Entry:     A = test value
;           Stack in order from top:
;            * Return address
;            * area size (bytes)
;            * base of area
;Exit       If no errors: 
;            * carry = 0
;           Else:
;            * carry = 1
;            * X = address at fault
;            * A = test value
;Registers used:
;           CC, X, Y

filcmp:
    ldy     2,s
    ldx     4,s
    
    ;Fill memory with value in A
fillp:
    sta     ,x+         ;Fill pos X with test value A and step to next X
    leay    -1,y        ;Continue till area if filled
    bne     fillp

    ;Compare memory and test value
    ldy     2,s         ;Get size from stack
    ldx     4,s         ;Get base address from 
cmplp:
    cmpa    ,x+         ;Compare memory and test value
    bne     erexit      ; exit if not equal

    ;no errors found, clear carry and exit
    andcc   #$fe        ;Clear Carry, Indicate no error
    rts

    ;Errors found, set carry move ptr back to indicate faulty memory position, and exit
erexit:
    orcc    #$01        ;Set Carry
    leax    -1,X        ;Point to faulty memory
    rts

