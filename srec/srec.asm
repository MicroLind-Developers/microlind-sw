IN      = $3000
BUFFER  = 
COUNT_L =
COUNT_H =


PARSE:  lda ,x+
        beq _PRS0
        cmpa #$52
        bne PARSE
        lda ,x+
        clrb
        suba #$30
        lbmi ERR
        cmpa #$0a
        lbpl ERR
        ldb #no_start_err
        cmpa #$00
        lbne ERR
        jsr S0_PARSE
        clrb
        lda ,x+
        cmpa #$53
        lbne ERR
        lda ,x+
        suba #$30
        beq _PRS1
        lbmi ERR
        cmpa #$0a
        lbpl ERR
        cmpa #$01
        bne _PRS2
        jsr 
        jmp 
_PRS3:  cmpa #$09
        jsr 
        jmp 
_PRS2:  cmpa #$05
        jsr 
        jmp 

_PRS0:  ldb #no_records_err
        jmp ERR
_PRS1:  ldb #second_start_err
        jmp ERR

ERR:    lslb
        ldx b,err_table
        ; print
        ; hang

S1_PARSE:
        ldy #BUFFER
        lda ,x+
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        lbcs ERR
        tfr a,e #count
        clra
        clrf #checksum
        bra _S1_1
_S1_0:  addr a,f
        sta ,-y
_S1_1:  lda ,x+
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        bcs ERR
        dece
        bne _S1_0 # loop
        comf    # checksum calculasion
        cmpr a,f
        bne _SX_1
        pshs x
        ldx #BUFFER
        jsr  # write BUFEFR to addres stored in first bytes of BUFFER
        puls x
        jsr _PARSE_TERMINATOR
        ldb #length_err
        lbcs ERR
        inc COUNT_L
        bne _S1_2
        inc COUNT_H
_S1_2:  rts

S5_PARSE:
        lda ,x+         # length
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        lbcs ERR
        ldb #length_err
        cmpa #$03
        lbne ERR
        ldf #$03
        lda ,x+         # count high
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        lbcs ERR
        ldb #mising_data_err
        cmpa COUNT_H
        lbne ERR
        addr a,f
        lda ,x+         #count low
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        lbcs ERR
        ldb #mising_data_err
        cmpa COUNT_L
        lbne ERR
        addr a,f
        comf    # checksum calculasion
        cmpr a,f
        ldb #checksum_err
        lbne ERR
        rts

S0_PARSE:
        lda ,x+
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        lbcs ERR
        tfr a,e         #count
        clra
        clrf            #checksum
_S0_0:  addr a,f
        lda ,x+
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        bcs ERR
        dece
        bne _S0_0       # loop
        comf            # checksum calculasion
        cmpr a,f
        bne _SX_1
        jsr _PARSE_TERMINATOR
        ldb #length_err
        lbcs ERR
        rts
_SX_1:  ldb #checksum_err
        lbra ERR
        
; -----------------------------------------------------------------
; _WRITE_BUFFER_TO_MEM
; input:            x Buffer start addres, y Buffer end addres
;                       first bytes of the buffer is the addres
; output:           None
; clobbers:         None
; -----------------------------------------------------------------


_PARSE_TERMINATOR:       ; Parses end of line characters
        lda ,x+
        cmpa #$0d
        beq _TRM0
        cmpa #$0a
        beq _TRM0
        leax -1,x
        orcc #$01
        rts
_TRM0:  lda ,x+
        cmpa #$0d
        beq _TRM0
        cmpa #$0a
        beq _TRM0
        leax -1,x
        andcc #$fe
        rts

ASCII_BYTE:     ; converts two ASCII hex characters in D to byte in A, sets carry on error.
        jsr ASCIIHEX
        bcs _ASB0
        exg a,b
        jsr ASCIIHEX
        bcs _ASB0
        lslb
        lslb
        lslb
        lslb
        andr b,a
        andcc #$fe
        rts
_ASB0:  orcc #$00
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
_ASC1:   anda #$0f
        andcc #$fe
        rts
_ASC0:   orcc #$01
        rts

symbal_err  = $00
no_start_err = $01
length_err = $02
checksum_err = $03
no_records_err = $04
second_start_err = $05
incorect_record_err = $06
mising_data_err = $07

err_table:
        fdb symErr
        fdb noStrErr
        fdb lgthErr
        fdb chkSumErr
        fdb noRecErr
        fdb secStrErr
        fdb icrRecErr
        fdb misDatErr

symErr:     FCC "Unexpected symbal error"
                fcb $0d,$00
noStrErr:   fcc "Mising start record error"
                fcb $0d,$00
lgthErr:     fcc "Incorect length or terminator error"
                fcb $0d,$00
chkSumErr:   fcc "Incorect checksum error"
                fcb $0d,$00
noRecErr: fcc "Input does not contain any records error"
                fcb $0d,$00
secStrErr:fcc "multiple start records error"
                fcb $0d,$00
icrRecErr:    fcc "Ilegal record type error"
                        fcb $0d,$00
misDatErr:        fcc "Incorect number of records error"
                        fcb $0d,$00

