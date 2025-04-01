; Name: BN2HEX
; Purpose: Converts one byte of binary data to two
; ASCII characters
; Entry: Register A = Binary data
; Exit: Register A = ASCII more significant digit
; Register B = ASCII less significant digit
; Registers Used: A,B,CC
; Example:
;       *CONVERT 23 HEXADECIMAL TO ASCII '23'
;       LDA #$23
;       JSR BN2HEX *A='2'=32H, B='3'=33H 

bin2hex:
    ;CONVERT MORE SIGNIFICANT DIGIT TO ASCII
    tfr     a,b         ;SAVE ORIGINAL BINARY VALUE
    lsra                ;MOVE HIGH DIGIT TO LOW DIGIT
    lsra
    lsra
    lsra
    cmpa    #9
    bls     add30       ;BRANCH IF HIGH DIGIT IS DECIMAL
    adda    #7          ;ELSE ADD 7 SO AFTER ADDING 'O' THE
                        ;CHARACTER WILL BE IN ‘'A'..'F'

add30: 
    ADDA    #'0         ;ADD ASCII O TO MAKE A CHARACTER
    ;CONVERT LESS SIGNIFICANT DIGIT TO ASCII
    ANDB    #3$0F       ;MASK OFF LOW DIGIT
    CMPB    #9
    BLS     add30ld     ;BRANCH IF LOW DIGIT IS DECIMAL
    ADDB    #7          ;ELSE ADD 7 SO AFTER ADDING 'O! THE
    ;CHARACTER WILL BE IN '‘A'..'F!
add30ld: 
    addb    #'0         ;ADD ASCII O TO MAKE A CHARACTER
    rts 

