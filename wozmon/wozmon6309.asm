; ---------------------------------------------------------------------------
; Woz Monitor for the Hitachi 6309 / MicroLind
;
; Based on Steve Wozniak's 1976 Apple-1 monitor.  The command language and
; high-bit-set input buffer are retained, while the console is translated to
; the MicroLind XR88C92 serial channel A.
;
; Entry requirements:
;   DP = $00
;   S  = valid stack
;   XR88C92 channel A initialized and enabled
;
; Serial input and output are polled directly so the monitor does not depend
; on BIOS serial routines.
; ---------------------------------------------------------------------------

        org     $E800
        setdp   $00

; Direct-page workspace.  Words use the 6309's native big-endian layout.
XAMADDR equ     $00             ; Last opened/examine address
XAMH    equ     XAMADDR
XAML    equ     XAMADDR+1
STADDR  equ     $02             ; Current store address
STH     equ     STADDR
STL     equ     STADDR+1
VALUE   equ     $04             ; Parsed hexadecimal value
H       equ     VALUE
L       equ     VALUE+1
XSAV    equ     $06             ; Input index before hexadecimal parse
MODE    equ     $08             ; $00=XAM, $74=STOR, $AE=BLOCK XAM

; Input buffer.  Characters are stored with bit 7 set, as in the Apple-1.
IN      equ     $0200
IN_SIZE equ     $0080

; MicroLind XR88C92 channel-A registers.
SERIAL_SRA      equ     $F431
SERIAL_RXA      equ     $F433
SERIAL_TXA      equ     $F433
SERIAL_RX_READY equ     $01
SERIAL_TX_READY equ     $04

_START:
        clra
        tfr     a,dp            ; Select direct page $0000-$00FF.

ESCAPE:
        lda     #$DC            ; Backslash with bit 7 set.
        jsr     ECHO

GETLINE:
        lda     #$8D            ; Carriage return, Apple-1 encoding.
        jsr     ECHO
        ldx     #$0001          ; BACKSPACE changes this to buffer index 0.

BACKSPACE:
        leax    -1,x
        cmpx    #$0000
        lblt    GETLINE

NEXTCHAR:
        lda     SERIAL_SRA
        bita    #SERIAL_RX_READY
        beq     NEXTCHAR
        lda     SERIAL_RXA
        ora     #$80
        sta     IN,x
        jsr     ECHO

NOTCR:
        cmpa    #$DF            ; Underscore with bit 7 set.
        beq     BACKSPACE
        cmpa    #$9B            ; Escape.
        beq     ESCAPE
        cmpa    #$8D            ; Carriage return.
        beq     PARSELINE
        leax    1,x
        cmpx    #IN_SIZE
        blo     NEXTCHAR
        bra     ESCAPE          ; Auto-escape when the buffer is full.

PARSELINE:
        ldx     #$FFFF          ; BLSKIP advances this to buffer index 0.
        clra                    ; Start in examine mode.

SETSTOR:
        asla                    ; ':' ($BA) becomes store mode $74.

SETMODE:
        sta     <MODE

BLSKIP:
        leax    1,x

NEXTITEM:
        lda     IN,x
        cmpa    #$8D
        lbeq    GETLINE
        cmpa    #$AE            ; Period with bit 7 set.
        blo     BLSKIP          ; Skip spaces and other delimiters.
        beq     SETMODE         ; '.' selects block examine mode ($AE).
        cmpa    #$BA            ; Colon with bit 7 set.
        beq     SETSTOR
        cmpa    #$D2            ; 'R' with bit 7 set.
        beq     RUN

        clr     <H
        clr     <L
        stx     <XSAV

NEXTHEX:
        lda     IN,x
        eora    #$B0            ; Map '0'-'9' to $00-$09.
        cmpa    #$0A
        blo     DIG
        adda    #$89            ; Map 'A'-'F' to $FA-$FF.
        cmpa    #$FA
        blo     NOTHEX

DIG:
        asla
        asla
        asla
        asla                    ; Move the digit into A's high nibble.
        ldb     #$04

HEXSHIFT:
        asla
        rol     <L
        rol     <H
        decb
        bne     HEXSHIFT
        leax    1,x
        bra     NEXTHEX

NOTHEX:
        cmpx    <XSAV
        lbeq    ESCAPE          ; No hexadecimal digits were supplied.

        ldb     <MODE
        bitb    #$40
        beq     NOTSTOR

        ldy     <STADDR
        lda     <L
        sta     ,y
        leay    1,y
        sty     <STADDR
        bra     NEXTITEM

RUN:
        ldx     <XAMADDR
        jmp     ,x

NOTSTOR:
        bitb    #$80
        bne     XAMNEXT         ; Continue an existing block examine.

        ldd     <VALUE
        std     <STADDR
        std     <XAMADDR

PRINTADDR:
        lda     #$8D
        jsr     ECHO
        lda     <XAMH
        jsr     PRBYTE
        lda     <XAML
        jsr     PRBYTE
        lda     #$BA            ; Colon with bit 7 set.
        jsr     ECHO

PRDATA:
        lda     #$A0            ; Space with bit 7 set.
        jsr     ECHO
        ldy     <XAMADDR
        lda     ,y
        jsr     PRBYTE

XAMNEXT:
        clr     <MODE
        ldd     <XAMADDR
        cmpd    <VALUE
        lbhs    NEXTITEM        ; Stop after displaying the requested end.
        incd
        std     <XAMADDR
        andb    #$07
        bne     PRDATA
        bra     PRINTADDR

PRBYTE:
        pshs    a
        lsra
        lsra
        lsra
        lsra
        jsr     PRHEX
        puls    a

PRHEX:
        anda    #$0F
        ora     #$B0            ; ASCII '0' with bit 7 set.
        cmpa    #$BA
        blo     ECHO
        adda    #$07

ECHO:
        pshs    a
ECHO_WAIT:
        lda     SERIAL_SRA
        bita    #SERIAL_TX_READY
        beq     ECHO_WAIT
        puls    a
        anda    #$7F
        sta     SERIAL_TXA
        ora     #$80            ; Preserve Apple-1 encoding for the caller.
        rts
