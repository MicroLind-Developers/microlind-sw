IN      = $3000
BUFFER  = 
COUNT_L =
COUNT_H =

; Entry point for parser
; Input:
;  X = Address to inputbuffer (where srec is stored, null terminated)
;  ( In future, input extra location offset ) 
PARSE:  lda ,x+
        beq _PRS0       #null
        cmpa #$53       # 'S'
        bne PARSE       # repeat until 'S' is found
        lda ,x+
        clrb            # symbol error
        suba #$30       # recenter on '0'
        lbmi ERR        # error on lower ascii value than '0'
        cmpa #$0a       # check if character value is higher than '9'
        lbpl ERR        # error on value higher than '9'
        ldb #no_start_err       # no start record error
        cmpa #$00       # check if first record is a start record
        lbne ERR
        jsr S0_PARSE    # parse start record
_entry: clrb            # symbol error
        lda ,x+
        cmpa #$53       # 'S'
        lbne ERR        # error on no record header
        lda ,x+
        suba #$30       # recenter on '0'
        beq _PRS1       # error on second start record
        lbmi ERR        # error on lower ascii value than '0'
        cmpa #$0a       # check if character value is higher than '9'
        lbpl ERR        # error on value higher than '9'
        cmpa #$01       # check if '1'
        bne _PRS2       # if not hop to next check
        jsr S1_PARSE    # parse data record
        bra _entry 
_PRS2:  cmpa #$05       # check if '5'
        bne _PRS3       # if not hop to next check
        jsr S5_PARSE    # parse count record
        bra _entry
_PRS3:  cmpa #$09       # check if '9'
        bne _PRS4       # if not hop to next check
        jsr S9_PARSE    # parse 16-bit terminator
        bra _entry 
_PRS4:  
        ldb #incorect_record_err        # parse rest of records or error
        jmp ERR         # incorrect record error, no other record types supported
_PRS0:  ldb #no_records_err
        jmp ERR
_PRS1:  ldb #second_start_err
        jmp ERR

ERR:    lslb
        ldx b,err_table
        ; print error 
        ; exit srec

S1_PARSE:
        ldy #BUFFER     # load temp buffer addres
        lda ,x+         # get count
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        lbcs ERR        # symbol error
        tfr a,e         # transfer count to e
        clra
        clrf            # clear f to hold checksum
        bra _S1_1       # enter loop
_S1_0:  addr a,f        # add value to checksum
        sta ,-y         # store value in buffer
_S1_1:  lda ,x+
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        bcs ERR         # symbol error
        dece
        bne _S1_0       # loop if count is not zero
        comf            # checksum calculasion
        cmpr a,f        # compare checksum
        bne _SX_1       #   if wrong, checksum error
        pshs x          # store x
        ldx #BUFFER     # load buffer addres in x
        jsr             # write BUFEFR to addres stored in first bytes of BUFFER
        puls x          # restore x
        jsr _PARSE_TERMINATOR   # parse the terminator
        ldb #length_err # terminator parsed corectly?
        lbcs ERR        #   if not, length error
        inc COUNT_L     # increment count
        beq _S1_2       # if overflow increment high byte
        rts
_S1_2:  inc COUNT_H
        rts

S5_PARSE:
        lda ,x+         # load count
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        lbcs ERR        # symbol error
        ldb #length_err
        cmpa #$03       # length fixed
        lbne ERR        #   if wrong, length error
        ldf #$03
        lda ,x+         # count high
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        lbcs ERR        # symbol error
        ldb #mising_data_err
        cmpa COUNT_H    # compare counts to see if a record was lost
        lbne ERR        #   if so, data error
        addr a,f        # add byte to checksum
        lda ,x+         # count low
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        lbcs ERR        # symbol error
        ldb #mising_data_err
        cmpa COUNT_L    # compare counts to see if a record was lost
        lbne ERR        #   if so, data error
        addr a,f
        comf            # checksum calculasion
        cmpr a,f
        ldb #checksum_err
        lbne ERR        # error on bad checksum
        jsr _PARSE_TERMINATOR   # parse the terminator
        ldb #length_err # terminator parsed corectly?
        lbcs ERR        #   if not, length error
        rts

S9_PARSE:


; TODO: Add header parsing to print out module name and comments.

S0_PARSE:
        lda ,x+         #load count
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        lbcs ERR        # symbol error
        tfr a,e         # transfer count to e
        clra
        clrf            # clear f to hold checksum
_S0_0:  addr a,f        # add byte to checksum
        lda ,x+         # load byte
        ldb ,x+
        jsr ASCII_BYTE
        clrb
        bcs ERR         #symbol error
        dece            # decrement count
        bne _S0_0       # loop if not last byte
        comf            # checksum calculation
        cmpr a,f
        bne _SX_1       # if checksum is not equal, checksum error
        jsr _PARSE_TERMINATOR   # parse the terminator
        ldb #length_err # terminator parsed corectly?
        lbcs ERR        #   if not, length error
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
_ASB0:  orcc #$01
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

symbol_err  = $00
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

symErr:     FCC "Unexpected symbol error"
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

