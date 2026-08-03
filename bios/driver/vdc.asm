; -----------------------------------------------------------------
; MOS 8568 VDC driver for microLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2026
;
; The VDC is accessed indirectly through GRAPHICS_BASE. All waits are
; bounded so an absent or failed device cannot hang the BIOS.
;
    IFNDEF IO_INC
        include "../include/io.inc"
    ENDC
    IFNDEF MEMORY_INC
        include "../include/memory.inc"
    ENDC

VDC_CONTROL                 EQU GRAPHICS_BASE
VDC_DATA                    EQU GRAPHICS_BASE+1

VDC_REG_HORIZONTAL_TOTAL    EQU 0
VDC_REG_HORIZONTAL_DISPLAY  EQU 1
VDC_REG_HORIZONTAL_SYNC     EQU 2
VDC_REG_SYNC_WIDTH          EQU 3
VDC_REG_VERTICAL_TOTAL      EQU 4
VDC_REG_VERTICAL_ADJUST     EQU 5
VDC_REG_VERTICAL_DISPLAY    EQU 6
VDC_REG_VERTICAL_SYNC       EQU 7
VDC_REG_INTERLACE           EQU 8
VDC_REG_CHARACTER_HEIGHT    EQU 9
VDC_REG_CURSOR_START        EQU 10
VDC_REG_CURSOR_END          EQU 11
VDC_REG_DISPLAY_START_HI    EQU 12
VDC_REG_DISPLAY_START_LO    EQU 13
VDC_REG_CURSOR_HI           EQU 14
VDC_REG_CURSOR_LO           EQU 15
VDC_REG_UPDATE_HI           EQU 18
VDC_REG_UPDATE_LO           EQU 19
VDC_REG_ATTRIBUTE_HI        EQU 20
VDC_REG_ATTRIBUTE_LO        EQU 21
VDC_REG_CHARACTER_WIDTH     EQU 22
VDC_REG_CHARACTER_DISPLAY   EQU 23
VDC_REG_VERTICAL_SCROLL     EQU 24
VDC_REG_HORIZONTAL_SCROLL   EQU 25
VDC_REG_COLOR               EQU 26
VDC_REG_ROW_INCREMENT       EQU 27
VDC_REG_CHARACTER_BASE      EQU 28
VDC_REG_UNDERLINE           EQU 29
VDC_REG_WORD_COUNT          EQU 30
VDC_REG_DATA                EQU 31
VDC_REG_BLOCK_HI            EQU 32
VDC_REG_BLOCK_LO            EQU 33
VDC_REG_DISPLAY_BEGIN       EQU 34
VDC_REG_DISPLAY_END         EQU 35
VDC_REG_REFRESH             EQU 36
VDC_REG_SYNC_POLARITY       EQU 37

VDC_READY_MASK              EQU $80
VDC_WAIT_COUNT              EQU $FFFF
VDC_REGISTER_TABLE_END      EQU $FF

VDC_TEXT_COLUMNS            EQU 80
VDC_TEXT_ROWS               EQU 25
VDC_TEXT_SIZE               EQU VDC_TEXT_COLUMNS*VDC_TEXT_ROWS
VDC_SCREEN_BASE             EQU $0000
VDC_ATTRIBUTE_BASE          EQU $0800
VDC_FONT_BASE               EQU $2000
VDC_FONT_GLYPHS             EQU 128
VDC_FONT_SOURCE_HEIGHT      EQU 8
VDC_FONT_GLYPH_STRIDE       EQU 16
VDC_DEFAULT_ATTRIBUTE       EQU $0F
VDC_DEFAULT_CURSOR_MODE     EQU $60

VDC_ASCII_SPACE             EQU $20
VDC_ASCII_QUESTION          EQU $3F
VDC_ASCII_DELETE            EQU $7F
VDC_ASCII_LF                EQU $0A
VDC_ASCII_CR                EQU $0D

; -----------------------------------------------------------------
; VDC_WAIT_READY
; Wait until status bit 7 indicates that the selected operation can run.
;
; Output: C clear = ready, C set = timeout
; Clobbers: CC
; -----------------------------------------------------------------
VDC_WAIT_READY:
    pshs x
    ldx #VDC_WAIT_COUNT
VDC_WAIT_READY_LOOP:
    tst VDC_CONTROL
    bmi VDC_WAIT_READY_OK
    leax -1,x
    bne VDC_WAIT_READY_LOOP
    puls x
    orcc #$01
    rts
VDC_WAIT_READY_OK:
    puls x
    andcc #$FE
    rts

; -----------------------------------------------------------------
; VDC_WRITE
; Input: A = internal register, B = value
; Output: C clear = success, C set = timeout
; Clobbers: CC
; -----------------------------------------------------------------
VDC_WRITE:
    sta VDC_CONTROL
    jsr VDC_WAIT_READY
    bcs VDC_WRITE_DONE
    stb VDC_DATA
    andcc #$FE
VDC_WRITE_DONE:
    rts

; -----------------------------------------------------------------
; VDC_READ
; Input: A = internal register
; Output: B = register value, C clear = success, C set = timeout
; Clobbers: B,CC
; -----------------------------------------------------------------
VDC_READ:
    sta VDC_CONTROL
    jsr VDC_WAIT_READY
    bcs VDC_READ_DONE
    ldb VDC_DATA
    andcc #$FE
VDC_READ_DONE:
    rts

; -----------------------------------------------------------------
; Access the currently selected VDC register. These entry points are used
; for sequential accesses through register 31 without repeatedly selecting
; it and resetting the VDC update address.
; -----------------------------------------------------------------
VDC_WRITE_SELECTED:
    jsr VDC_WAIT_READY
    bcs VDC_WRITE_SELECTED_DONE
    stb VDC_DATA
    andcc #$FE
VDC_WRITE_SELECTED_DONE:
    rts

; -----------------------------------------------------------------
; VDC_DETECT
; Perform a reversible two-pattern test on the row-increment register.
;
; Output: C clear = VDC present, C set = absent or failed
; Preserves: A,B,X
; -----------------------------------------------------------------
VDC_DETECT:
    pshs a,b,x
    jsr VDC_WAIT_READY
    bcs VDC_DETECT_FAIL

    lda #VDC_REG_ROW_INCREMENT
    jsr VDC_READ
    bcs VDC_DETECT_FAIL
    stb VDC_PROBE_SAVED_REG

    ldb #$55
    jsr VDC_WRITE
    bcs VDC_DETECT_RESTORE_FAIL
    jsr VDC_READ
    bcs VDC_DETECT_RESTORE_FAIL
    cmpb #$55
    bne VDC_DETECT_RESTORE_FAIL

    ldb #$AA
    jsr VDC_WRITE
    bcs VDC_DETECT_RESTORE_FAIL
    jsr VDC_READ
    bcs VDC_DETECT_RESTORE_FAIL
    cmpb #$AA
    bne VDC_DETECT_RESTORE_FAIL

    ldb VDC_PROBE_SAVED_REG
    jsr VDC_WRITE
    bcs VDC_DETECT_FAIL
    puls a,b,x
    andcc #$FE
    rts

VDC_DETECT_RESTORE_FAIL:
    lda #VDC_REG_ROW_INCREMENT
    ldb VDC_PROBE_SAVED_REG
    jsr VDC_WRITE                 ; Best-effort restore after a failed probe.
VDC_DETECT_FAIL:
    puls a,b,x
    orcc #$01
    rts

; -----------------------------------------------------------------
; VDC_SET_UPDATE_ADDRESS
; Input: X = VDC-local RAM address
; Output: C clear = success, C set = timeout
; Clobbers: A,B,E,F,CC
; -----------------------------------------------------------------
VDC_SET_UPDATE_ADDRESS:
    tfr x,d
    tfr a,e
    tfr b,f
    lda #VDC_REG_UPDATE_HI
    tfr e,b
    jsr VDC_WRITE
    bcs VDC_SET_UPDATE_ADDRESS_DONE
    lda #VDC_REG_UPDATE_LO
    tfr f,b
    jsr VDC_WRITE
VDC_SET_UPDATE_ADDRESS_DONE:
    rts

; -----------------------------------------------------------------
; VDC_WRITE_VRAM_BYTE
; Input: X = VDC-local RAM address, A = byte
; Output: C clear = success, C set = timeout
; Preserves: X
; Clobbers: A,B,E,F,CC
; -----------------------------------------------------------------
VDC_WRITE_VRAM_BYTE:
    pshs a
    jsr VDC_SET_UPDATE_ADDRESS
    bcs VDC_WRITE_VRAM_BYTE_FAIL
    puls b
    lda #VDC_REG_DATA
    jmp VDC_WRITE
VDC_WRITE_VRAM_BYTE_FAIL:
    leas 1,s
    rts

; -----------------------------------------------------------------
; VDC_READ_VRAM_BYTE
; Input: X = VDC-local RAM address
; Output: A = byte, C clear = success, C set = timeout
; Preserves: X
; Clobbers: A,B,E,F,CC
; -----------------------------------------------------------------
VDC_READ_VRAM_BYTE:
    jsr VDC_SET_UPDATE_ADDRESS
    bcs VDC_READ_VRAM_BYTE_DONE
    lda #VDC_REG_DATA
    jsr VDC_READ
    bcs VDC_READ_VRAM_BYTE_DONE
    tfr b,a
VDC_READ_VRAM_BYTE_DONE:
    rts

; -----------------------------------------------------------------
; VDC_FILL_RANGE
; Input: X = start address, Y = byte count, B = fill value
; Output: C clear = success, C set = timeout
; Preserves: X,Y
; Clobbers: A,B,E,F,W,CC
;
; Register 24 remains in block-fill mode throughout this text driver. Writing
; register 31 stores the first byte. Register 30 then starts hardware fills
; for the remaining bytes; a zero word count represents 256 bytes.
; -----------------------------------------------------------------
VDC_FILL_RANGE:
    pshs x,y,b
    jsr VDC_SET_UPDATE_ADDRESS
    bcs VDC_FILL_RANGE_FAIL_STACK
    puls b
    lda #VDC_REG_DATA
    jsr VDC_WRITE
    bcs VDC_FILL_RANGE_FAIL

    leay -1,y                    ; Register 31 wrote the first byte.
    tfr y,w                      ; E = 256-byte blocks, F = final byte count.
    lda #VDC_REG_WORD_COUNT
    tste
    beq VDC_FILL_RANGE_TAIL
    clrb
VDC_FILL_RANGE_PAGES:
    jsr VDC_WRITE                ; B=0 commands a 256-byte hardware fill.
    bcs VDC_FILL_RANGE_FAIL
    dece
    bne VDC_FILL_RANGE_PAGES

VDC_FILL_RANGE_TAIL:
    tstf
    beq VDC_FILL_RANGE_WAIT
    tfr f,b
    jsr VDC_WRITE
    bcs VDC_FILL_RANGE_FAIL

VDC_FILL_RANGE_WAIT:
    jsr VDC_WAIT_READY           ; Do not return while the VDC still owns VRAM.
    puls x,y,pc
VDC_FILL_RANGE_FAIL_STACK:
    leas 1,s
VDC_FILL_RANGE_FAIL:
    puls x,y
    orcc #$01
    rts

; -----------------------------------------------------------------
; VDC_UPLOAD_FONT
; Build an ASCII-indexed VDC font from the normal half of the Swedish
; lowercase/uppercase PETSCII set. Control-code glyphs are blank. Printable
; letters are remapped because PETSCII stores lowercase at slots 1..26 and
; uppercase at 65..90. Each eight-row glyph is padded to the VDC's
; sixteen-byte character stride. PETSCII ROM rows are already MSB-left.
; -----------------------------------------------------------------
VDC_UPLOAD_FONT:
    pshs d,x,y,u
    ldx #VDC_FONT_BASE
    jsr VDC_SET_UPDATE_ADDRESS
    lbcs VDC_UPLOAD_FONT_FAIL
    lda #VDC_REG_DATA
    sta VDC_CONTROL
    clr VDC_FONT_CODE
    ldy #VDC_FONT_GLYPHS
VDC_UPLOAD_FONT_GLYPH:
    lda VDC_FONT_CODE
    cmpa #VDC_ASCII_SPACE
    blo VDC_UPLOAD_FONT_BLANK
    cmpa #$40
    blo VDC_UPLOAD_FONT_SOURCE_READY
    beq VDC_UPLOAD_FONT_AT_SIGN
    cmpa #'Z'+1
    blo VDC_UPLOAD_FONT_SOURCE_READY
    cmpa #$60
    blo VDC_UPLOAD_FONT_SWEDISH
    beq VDC_UPLOAD_FONT_QUESTION
    cmpa #'z'+1
    blo VDC_UPLOAD_FONT_LOWERCASE
    cmpa #VDC_ASCII_DELETE
    blo VDC_UPLOAD_FONT_QUESTION
    bra VDC_UPLOAD_FONT_BLANK

VDC_UPLOAD_FONT_AT_SIGN:
    clra
    bra VDC_UPLOAD_FONT_SOURCE_READY
VDC_UPLOAD_FONT_SWEDISH:
    suba #$40                    ; ASCII [.._ -> Swedish ROM slots 27..31.
    bra VDC_UPLOAD_FONT_SOURCE_READY
VDC_UPLOAD_FONT_LOWERCASE:
    suba #$60                    ; ASCII a..z -> PETSCII slots 1..26.
    bra VDC_UPLOAD_FONT_SOURCE_READY
VDC_UPLOAD_FONT_QUESTION:
    lda #VDC_ASCII_QUESTION

VDC_UPLOAD_FONT_SOURCE_READY:
    tfr a,b
    clra
    lslb
    rola
    lslb
    rola
    lslb
    rola
    ldu #VDC_PETSCII_LOWERCASE_NORMAL
    leau d,u
    ldx #VDC_FONT_SOURCE_HEIGHT
VDC_UPLOAD_FONT_ROWS:
    ldb ,u+
    jsr VDC_WRITE_SELECTED
    bcs VDC_UPLOAD_FONT_FAIL
    leax -1,x
    bne VDC_UPLOAD_FONT_ROWS

    ldx #VDC_FONT_GLYPH_STRIDE-VDC_FONT_SOURCE_HEIGHT
    clrb
VDC_UPLOAD_FONT_PADDING:
    jsr VDC_WRITE_SELECTED
    bcs VDC_UPLOAD_FONT_FAIL
    leax -1,x
    bne VDC_UPLOAD_FONT_PADDING
    bra VDC_UPLOAD_FONT_NEXT

VDC_UPLOAD_FONT_BLANK:
    ldx #VDC_FONT_GLYPH_STRIDE
    clrb
VDC_UPLOAD_FONT_BLANK_LOOP:
    jsr VDC_WRITE_SELECTED
    bcs VDC_UPLOAD_FONT_FAIL
    leax -1,x
    bne VDC_UPLOAD_FONT_BLANK_LOOP

VDC_UPLOAD_FONT_NEXT:
    inc VDC_FONT_CODE
    lda VDC_FONT_CODE
    cmpa #'T'+1
    bne VDC_UPLOAD_FONT_CONTINUE

    ; At this point every glyph used by the bootstrap message is resident.
    ; Show progress, then restore register 31's update address so the
    ; sequential upload can continue with the next ASCII glyph.
    ldx #VDC_FONT_LOADING_MESSAGE
    jsr VDC_PRINT
    bcs VDC_UPLOAD_FONT_FAIL
    ldx #VDC_FONT_BASE+(('T'+1)*VDC_FONT_GLYPH_STRIDE)
    jsr VDC_SET_UPDATE_ADDRESS
    bcs VDC_UPLOAD_FONT_FAIL
    lda #VDC_REG_DATA
    sta VDC_CONTROL

VDC_UPLOAD_FONT_CONTINUE:
    leay -1,y
    lbne VDC_UPLOAD_FONT_GLYPH
    puls d,x,y,u
    andcc #$FE
    rts
VDC_UPLOAD_FONT_FAIL:
    puls d,x,y,u
    orcc #$01
    rts

; -----------------------------------------------------------------
; VDC_GET_CURSOR_ADDRESS
; Output: X = current character address in VDC-local RAM
; Clobbers: D,X,CC
; -----------------------------------------------------------------
VDC_GET_CURSOR_ADDRESS:
    lda VDC_CURSOR_ROW
    ldb #VDC_TEXT_COLUMNS
    mul
    addb VDC_CURSOR_COLUMN
    adca #0
    addd #VDC_SCREEN_BASE
    tfr d,x
    rts

; -----------------------------------------------------------------
; VDC_UPDATE_CURSOR
; Copy the logical cursor position to VDC registers 14 and 15.
; -----------------------------------------------------------------
VDC_UPDATE_CURSOR:
    pshs d,x
    jsr VDC_GET_CURSOR_ADDRESS
    tfr x,d
    pshs b
    tfr a,b
    lda #VDC_REG_CURSOR_HI
    jsr VDC_WRITE
    bcs VDC_UPDATE_CURSOR_FAIL_STACK
    puls b
    lda #VDC_REG_CURSOR_LO
    jsr VDC_WRITE
    bcs VDC_UPDATE_CURSOR_FAIL
    puls d,x
    andcc #$FE
    rts
VDC_UPDATE_CURSOR_FAIL_STACK:
    leas 1,s
VDC_UPDATE_CURSOR_FAIL:
    puls d,x
    orcc #$01
    rts

; -----------------------------------------------------------------
; VDC_SET_CURSOR
; Input: A = row (0..24), B = column (0..79)
; Output: C clear = success, C set = invalid position or timeout
; -----------------------------------------------------------------
VDC_SET_CURSOR:
    cmpa #VDC_TEXT_ROWS
    bhs VDC_SET_CURSOR_INVALID
    cmpb #VDC_TEXT_COLUMNS
    bhs VDC_SET_CURSOR_INVALID
    sta VDC_CURSOR_ROW
    stb VDC_CURSOR_COLUMN
    jmp VDC_UPDATE_CURSOR
VDC_SET_CURSOR_INVALID:
    orcc #$01
    rts

; -----------------------------------------------------------------
; VDC_GET_CURSOR
; Output: A = row, B = column
; -----------------------------------------------------------------
VDC_GET_CURSOR:
    lda VDC_CURSOR_ROW
    ldb VDC_CURSOR_COLUMN
    andcc #$FE
    rts

VDC_HOME:
    clr VDC_CURSOR_ROW
    clr VDC_CURSOR_COLUMN
    jmp VDC_UPDATE_CURSOR

; -----------------------------------------------------------------
; VDC_CLEAR_SCREEN
; Fill the visible character and attribute planes, then home the cursor.
; -----------------------------------------------------------------
VDC_CLEAR_SCREEN:
    pshs d,x,y
    ldx #VDC_SCREEN_BASE
    ldy #VDC_TEXT_SIZE
    ldb #VDC_ASCII_SPACE
    jsr VDC_FILL_RANGE
    bcs VDC_CLEAR_SCREEN_FAIL
    ldx #VDC_ATTRIBUTE_BASE
    ldy #VDC_TEXT_SIZE
    ldb VDC_CURRENT_ATTRIBUTE
    jsr VDC_FILL_RANGE
    bcs VDC_CLEAR_SCREEN_FAIL
    jsr VDC_HOME
    bcs VDC_CLEAR_SCREEN_FAIL
    puls d,x,y
    andcc #$FE
    rts
VDC_CLEAR_SCREEN_FAIL:
    puls d,x,y
    orcc #$01
    rts

; -----------------------------------------------------------------
; VDC_SCROLL_UP
; Move rows 1..24 to rows 0..23 using the conservative byte access path,
; then clear the final row. This is slower than the VDC block-copy engine
; but avoids its documented revision-specific behavior.
; -----------------------------------------------------------------
VDC_SCROLL_UP:
    pshs d,x,y,u
    ldu #VDC_SCREEN_BASE+VDC_TEXT_COLUMNS
    ldy #VDC_SCREEN_BASE
VDC_SCROLL_TEXT_LOOP:
    cmpu #VDC_SCREEN_BASE+VDC_TEXT_SIZE
    beq VDC_SCROLL_ATTRIBUTES
    tfr u,x
    jsr VDC_READ_VRAM_BYTE
    bcs VDC_SCROLL_UP_FAIL
    tfr y,x
    jsr VDC_WRITE_VRAM_BYTE
    bcs VDC_SCROLL_UP_FAIL
    leau 1,u
    leay 1,y
    bra VDC_SCROLL_TEXT_LOOP

VDC_SCROLL_ATTRIBUTES:
    ldu #VDC_ATTRIBUTE_BASE+VDC_TEXT_COLUMNS
    ldy #VDC_ATTRIBUTE_BASE
VDC_SCROLL_ATTRIBUTE_LOOP:
    cmpu #VDC_ATTRIBUTE_BASE+VDC_TEXT_SIZE
    beq VDC_SCROLL_CLEAR_LAST_ROW
    tfr u,x
    jsr VDC_READ_VRAM_BYTE
    bcs VDC_SCROLL_UP_FAIL
    tfr y,x
    jsr VDC_WRITE_VRAM_BYTE
    bcs VDC_SCROLL_UP_FAIL
    leau 1,u
    leay 1,y
    bra VDC_SCROLL_ATTRIBUTE_LOOP

VDC_SCROLL_CLEAR_LAST_ROW:
    ldx #VDC_SCREEN_BASE+VDC_TEXT_SIZE-VDC_TEXT_COLUMNS
    ldy #VDC_TEXT_COLUMNS
    ldb #VDC_ASCII_SPACE
    jsr VDC_FILL_RANGE
    bcs VDC_SCROLL_UP_FAIL
    ldx #VDC_ATTRIBUTE_BASE+VDC_TEXT_SIZE-VDC_TEXT_COLUMNS
    ldy #VDC_TEXT_COLUMNS
    ldb VDC_CURRENT_ATTRIBUTE
    jsr VDC_FILL_RANGE
    bcs VDC_SCROLL_UP_FAIL
    puls d,x,y,u
    andcc #$FE
    rts
VDC_SCROLL_UP_FAIL:
    puls d,x,y,u
    orcc #$01
    rts

; -----------------------------------------------------------------
; VDC_LINE_FEED
; Advance one row while preserving the current column. Scroll at row 24.
; -----------------------------------------------------------------
VDC_LINE_FEED:
    lda VDC_CURSOR_ROW
    cmpa #VDC_TEXT_ROWS-1
    bhs VDC_LINE_FEED_SCROLL
    inca
    sta VDC_CURSOR_ROW
    jmp VDC_UPDATE_CURSOR
VDC_LINE_FEED_SCROLL:
    jsr VDC_SCROLL_UP
    bcs VDC_LINE_FEED_DONE
    lda #VDC_TEXT_ROWS-1
    sta VDC_CURSOR_ROW
    jsr VDC_UPDATE_CURSOR
VDC_LINE_FEED_DONE:
    rts

; -----------------------------------------------------------------
; VDC_PRINT_CHAR
; Input: A = ASCII character
; Handles printable ASCII, CR, LF, wrapping, scrolling, and cursor updates.
; Preserves: X
; -----------------------------------------------------------------
VDC_PRINT_CHAR:
    pshs x
    cmpa #VDC_ASCII_CR
    beq VDC_PRINT_CHAR_CR
    cmpa #VDC_ASCII_LF
    beq VDC_PRINT_CHAR_LF
    cmpa #VDC_ASCII_SPACE
    blo VDC_PRINT_CHAR_IGNORE
    cmpa #VDC_ASCII_DELETE
    blo VDC_PRINT_CHAR_STORE
    lda #VDC_ASCII_QUESTION

VDC_PRINT_CHAR_STORE:
    sta VDC_TEMP_CHAR
    jsr VDC_GET_CURSOR_ADDRESS
    lda VDC_TEMP_CHAR
    jsr VDC_WRITE_VRAM_BYTE
    bcs VDC_PRINT_CHAR_FAIL
    inc VDC_CURSOR_COLUMN
    lda VDC_CURSOR_COLUMN
    cmpa #VDC_TEXT_COLUMNS
    blo VDC_PRINT_CHAR_UPDATE
    clr VDC_CURSOR_COLUMN
    jsr VDC_LINE_FEED
    bra VDC_PRINT_CHAR_RETURN

VDC_PRINT_CHAR_CR:
    clr VDC_CURSOR_COLUMN
    jsr VDC_UPDATE_CURSOR
    bra VDC_PRINT_CHAR_RETURN
VDC_PRINT_CHAR_LF:
    jsr VDC_LINE_FEED
    bra VDC_PRINT_CHAR_RETURN
VDC_PRINT_CHAR_IGNORE:
    andcc #$FE
    bra VDC_PRINT_CHAR_RETURN
VDC_PRINT_CHAR_UPDATE:
    jsr VDC_UPDATE_CURSOR
VDC_PRINT_CHAR_RETURN:
    bcs VDC_PRINT_CHAR_FAIL
    puls x
    andcc #$FE
    rts
VDC_PRINT_CHAR_FAIL:
    puls x
    orcc #$01
    rts

; -----------------------------------------------------------------
; VDC_PRINT
; Input: X = NUL-terminated ASCII string
; Output: C clear = success, C set = timeout
; Clobbers: A,X,CC
; -----------------------------------------------------------------
VDC_PRINT:
    lda ,x+
    beq VDC_PRINT_DONE
    jsr VDC_PRINT_CHAR
    bcc VDC_PRINT
    rts
VDC_PRINT_DONE:
    andcc #$FE
    rts

VDC_PRINT_CRLF:
    lda #VDC_ASCII_CR
    jsr VDC_PRINT_CHAR
    bcs VDC_PRINT_CRLF_DONE
    lda #VDC_ASCII_LF
    jsr VDC_PRINT_CHAR
VDC_PRINT_CRLF_DONE:
    rts

; -----------------------------------------------------------------
; VDC_INIT_TEXT
; Initialize C128-compatible PAL 80x25 RGBI text timing, load the ASCII
; font, and clear the screen. The table can be replaced if the MicroLind
; board uses a different VDC clock or monitor timing.
; -----------------------------------------------------------------
VDC_INIT_TEXT:
    pshs d,x,y,u
    clr VDC_INITIALIZED_FLAG
    ldu #VDC_TEXT_INIT_TABLE
VDC_INIT_TEXT_TABLE_LOOP:
    lda ,u+
    cmpa #VDC_REGISTER_TABLE_END
    beq VDC_INIT_TEXT_TABLE_DONE
    ldb ,u+
    jsr VDC_WRITE
    bcc VDC_INIT_TEXT_TABLE_LOOP
    bra VDC_INIT_TEXT_FAIL

VDC_INIT_TEXT_TABLE_DONE:
    ldb #VDC_DEFAULT_ATTRIBUTE
    stb VDC_CURRENT_ATTRIBUTE
    ; Prepare a clean character/attribute plane before the full font copy so
    ; VDC_UPLOAD_FONT can display its bootstrap progress message.
    jsr VDC_CLEAR_SCREEN
    bcs VDC_INIT_TEXT_FAIL
    jsr VDC_UPLOAD_FONT
    bcs VDC_INIT_TEXT_FAIL
    ; Keep the bootstrap message visible while the remaining BIOS probes run;
    ; subsequent boot diagnostics start on the following row.
    jsr VDC_PRINT_CRLF
    bcs VDC_INIT_TEXT_FAIL
    lda #$01
    sta VDC_INITIALIZED_FLAG
    puls d,x,y,u
    andcc #$FE
    rts
VDC_INIT_TEXT_FAIL:
    clr VDC_INITIALIZED_FLAG
    puls d,x,y,u
    orcc #$01
    rts

; Keep the graphics entry point for callers that explicitly need it, but
; graphics-mode framebuffer support is outside the current text-only scope.
VDC_INIT_GRAPHICS:
    lda #VDC_REG_HORIZONTAL_SCROLL
    jsr VDC_READ
    bcs VDC_INIT_GRAPHICS_DONE
    orb #$80
    jsr VDC_WRITE
VDC_INIT_GRAPHICS_DONE:
    rts

; Standard C128 PAL 80-column timing adapted from Commodore's original
; C128 KERNAL initialization table. Register 25 uses the 8568/R8 value.
VDC_TEXT_INIT_TABLE:
    fcb 0,$7F,1,$50,2,$66,3,$49,4,$26,5,$00,6,$19,7,$20
    fcb 8,$00,9,$07,10,VDC_DEFAULT_CURSOR_MODE,11,$07,12,$00,13,$00,14,$00,15,$00
    fcb 20,$08,21,$00,23,$08,24,$20,25,$47,26,$F0,27,$00,28,$20
    fcb 29,$07,34,$7D,35,$64,36,$05,22,$78
    fcb VDC_REGISTER_TABLE_END
