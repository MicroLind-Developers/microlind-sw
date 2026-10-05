; Serial console. Two-argument commands use a space separator.
; -------------------------------------------------------
;  Run the bounded serial command loop until the quit command.
; -------------------------------------------------------
; input:            Initialized BIOS serial service pointers; mount may be invalid
; output:           D=0/C clear on quit; console requests, mount state, and selected file
;                   contents may change
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
FS_CONSOLE:
    ldx #F_CON_BANNER
    jsr [F_PUTS]
F_CON_PROMPT:
    ldx #F_CON_PROMPT_TEXT
    jsr [F_PUTS]
    ldy #FS_LINE
F_CON_INPUT:
    jsr [F_GETC]
    bcs F_CON_INPUT
    cmpa #13
    beq F_CON_LINE_READY
    cmpa #10
    beq F_CON_LINE_READY
    cmpa #8
    beq F_CON_BACKSPACE
    cmpa #127
    beq F_CON_BACKSPACE
    cmpa #32
    blo F_CON_INPUT
    cmpy #FS_LINE_LIMIT-1
    bhs F_CON_INPUT
    sta ,y+
    jsr [F_PUTC]
    bra F_CON_INPUT
F_CON_BACKSPACE:
    cmpy #FS_LINE
    beq F_CON_INPUT
    leay -1,y
    ldx #F_CON_ERASE
    jsr [F_PUTS]
    bra F_CON_INPUT
F_CON_LINE_READY:
    clr ,y
    jsr F_CON_NEWLINE
    ldx #FS_LINE+1
F_CON_ARGUMENT:
    lda ,x
    cmpa #' '
    bne F_CON_DISPATCH
    leax 1,x
    bra F_CON_ARGUMENT
F_CON_DISPATCH:
    stx FS_CON_REQUEST+FS_REQ_PATH
    ldd #SERIAL_BUFFER_START
    std FS_CON_REQUEST+FS_REQ_BUFFER
    ldd #SERIAL_BUFFER_SIZE
    std FS_CON_REQUEST+FS_REQ_COUNT
    ldq #0
    stq FS_CON_REQUEST+FS_REQ_OFFSET
    lda FS_LINE
    cmpa #'q'
    lbeq F_CON_EXIT
    cmpa #'m'
    lbeq F_CON_MOUNT
    cmpa #'l'
    beq F_CON_LIST
    cmpa #'s'
    lbeq F_CON_STAT
    cmpa #'c'
    lbeq F_CON_CAT
    cmpa #'i'
    lbeq F_CON_STATS
    cmpa #'n'
    lbeq F_CON_CREATE
    cmpa #'d'
    lbeq F_CON_MKDIR
    cmpa #'u'
    lbeq F_CON_UNLINK
    cmpa #'r'
    lbeq F_CON_RMDIR
    cmpa #'v'
    lbeq F_CON_RENAME
    cmpa #'w'
    lbeq F_CON_WRITE
    cmpa #'a'
    lbeq F_CON_APPEND
    cmpa #'t'
    lbeq F_CON_DIAGNOSTIC
    tsta
    lbeq F_CON_PROMPT
    ldx #F_CON_HELP
    jsr [F_PUTS]
    lbra F_CON_PROMPT

; -------------------------------------------------------
;  List a directory through serial output, defaulting an empty path to root.
; -------------------------------------------------------
; input:            FS_CON_REQUEST.path=directory; buffer/count=serial buffer; offset=0
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_LIST:
    ldx FS_CON_REQUEST+FS_REQ_PATH
    tst ,x
    bne F_CON_LIST_NEXT
    ldx #F_ROOT_PATH
    stx FS_CON_REQUEST+FS_REQ_PATH
F_CON_LIST_NEXT:
    ldx #FS_CON_REQUEST
    jsr FS_LIST
    lbcs F_CON_ERROR
    ldd FS_CON_REQUEST+FS_REQ_DONE
    lbeq F_CON_PROMPT
    jsr F_CON_PRINT_ENTRY
    bra F_CON_LIST_NEXT

; -------------------------------------------------------
;  Print one path entry and its hexadecimal size.
; -------------------------------------------------------
; input:            FS_CON_REQUEST=stat request using the serial buffer
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_STAT:
    ldx #FS_CON_REQUEST
    jsr FS_STAT
    lbcs F_CON_ERROR
    jsr F_CON_PRINT_ENTRY
    lbra F_CON_PROMPT

; -------------------------------------------------------
;  Stream a file to serial, advancing the private request offset between reads.
; -------------------------------------------------------
; input:            FS_CON_REQUEST=read request using the serial buffer
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_CAT:
    ldx #FS_CON_REQUEST
    jsr FS_READ
    lbcs F_CON_ERROR
    ldy FS_CON_REQUEST+FS_REQ_DONE
    beq F_CON_CAT_END
    ldu #SERIAL_BUFFER_START
F_CON_CAT_BYTE:
    lda ,u+
    jsr [F_PUTC]
    leay -1,y
    bne F_CON_CAT_BYTE
    ldq FS_CON_REQUEST+FS_REQ_OFFSET
    addw FS_CON_REQUEST+FS_REQ_DONE
    adcb #0
    adca #0
    stq FS_CON_REQUEST+FS_REQ_OFFSET
    bra F_CON_CAT
F_CON_CAT_END:
    jsr F_CON_NEWLINE
    lbra F_CON_PROMPT

; -------------------------------------------------------
;  Parse an optional decimal partition index and mount it.
; -------------------------------------------------------
; input:            FS_CON_REQUEST.path=argument text (empty means 0)
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_MOUNT:
    ldx FS_CON_REQUEST+FS_REQ_PATH
    clrb
    lda ,x+
    beq F_CON_MOUNT_CALL
    suba #'0'
    cmpa #9
    bhi F_CON_INVALID
    tfr a,b
    lda ,x+
    beq F_CON_MOUNT_CALL
    suba #'0'
    cmpa #9
    bhi F_CON_INVALID
    pshs a
    lda #10
    mul
    addb ,s+
    tst ,x
    bne F_CON_INVALID
F_CON_MOUNT_CALL:
    jsr FS_MOUNT
    bcs F_CON_ERROR
    ldx #F_CON_MOUNTED
    jsr [F_PUTS]
    lbra F_CON_PROMPT

; -------------------------------------------------------
;  Print hexadecimal used/free allocation counts.
; -------------------------------------------------------
; input:            Mounted partition; FS_CON_REQUEST is scratch storage
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_STATS:
    ldx #FS_CON_REQUEST
    jsr FS_STATS
    bcs F_CON_ERROR
    ldx #F_CON_USED
    jsr [F_PUTS]
    ldx #FS_CON_REQUEST
    jsr F_CON_PRINT_LONG
    ldx #F_CON_FREE
    jsr [F_PUTS]
    ldx #FS_CON_REQUEST+4
    jsr F_CON_PRINT_LONG
    jsr F_CON_NEWLINE
    lbra F_CON_PROMPT

; -------------------------------------------------------
;  Report invalid console command arguments and resume input.
; -------------------------------------------------------
; input:            None
; output:           Serial FS_EINVAL message; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_INVALID:
    ldd #FS_EINVAL

; -------------------------------------------------------
;  Print a hexadecimal filesystem error and resume console input.
; -------------------------------------------------------
; input:            D=error status
; output:           Serial error message; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_ERROR:
    pshs d
    ldx #F_CON_ERROR_TEXT
    jsr [F_PUTS]
    puls d
    jsr F_CON_PRINT_WORD
    jsr F_CON_NEWLINE
    lbra F_CON_PROMPT

; -------------------------------------------------------
;  Create an empty file from the console request.
; -------------------------------------------------------
; input:            FS_CON_REQUEST=creation request
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_CREATE:
    ldx #FS_CON_REQUEST
    jsr FS_CREATE
    lbra F_CON_MUTATION_RESULT

; -------------------------------------------------------
;  Run the CF-loaded diagnostic and restore the previously selected partition.
; -------------------------------------------------------
; input:            F_BIOS_API=descriptor with module-launch service; F_PART_INDEX=current
;                   partition
; output:           Diagnostic output or error; application RAM overwritten by loading; continues
;                   at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_DIAGNOSTIC:
    ldu F_BIOS_API
    ldd 6,u
    cmpd #BIOS_MODULE_API_COUNT
    bhs F_CON_DIAGNOSTIC_READY
    ldd #FS_EABI
    lbra F_CON_ERROR
F_CON_DIAGNOSTIC_READY:
    ldb F_PART_INDEX
    pshs b
    leau BIOS_MODULE_RUN-BIOS_MODULE_API_BASE,u
    ldx #F_DIAGNOSTIC_PATH
    ldb #MLP_KIND_APPLICATION
    ldy #FS_API_BASE
    jsr ,u
    bcs F_CON_DIAGNOSTIC_ERROR
    puls b
    jsr FS_MOUNT
    lbcs F_CON_ERROR
    lbra F_CON_PROMPT
F_CON_DIAGNOSTIC_ERROR:
    puls b
    ldd #FS_EIO
    lbra F_CON_ERROR

; -------------------------------------------------------
;  Create an empty directory from the console request.
; -------------------------------------------------------
; input:            FS_CON_REQUEST=directory creation request
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_MKDIR:
    ldx #FS_CON_REQUEST
    jsr FS_MKDIR
    lbra F_CON_MUTATION_RESULT

; -------------------------------------------------------
;  Remove a file named by the console request.
; -------------------------------------------------------
; input:            FS_CON_REQUEST.path=file
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_UNLINK:
    ldx #FS_CON_REQUEST
    jsr FS_UNLINK
    lbra F_CON_MUTATION_RESULT

; -------------------------------------------------------
;  Remove an empty directory named by the console request.
; -------------------------------------------------------
; input:            FS_CON_REQUEST.path=directory
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_RMDIR:
    ldx #FS_CON_REQUEST
    jsr FS_RMDIR
    lbra F_CON_MUTATION_RESULT

; -------------------------------------------------------
;  Split source/destination arguments and rename or move an entry.
; -------------------------------------------------------
; input:            FS_CON_REQUEST.path=source and destination argument text
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_RENAME:
    jsr F_CON_SPLIT
    lbcs F_CON_ERROR
    ldx #FS_CON_REQUEST
    jsr FS_RENAME
    lbra F_CON_MUTATION_RESULT

; -------------------------------------------------------
;  Split file/text arguments, find EOF, and append the text.
; -------------------------------------------------------
; input:            FS_CON_REQUEST.path=file and text argument string
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_APPEND:
    jsr F_CON_SPLIT
    lbcs F_CON_ERROR
    pshs x
    ldd #SERIAL_BUFFER_START
    std FS_CON_REQUEST+FS_REQ_BUFFER
    ldd #128
    std FS_CON_REQUEST+FS_REQ_COUNT
    ldx #FS_CON_REQUEST
    jsr FS_STAT
    puls x
    lbcs F_CON_ERROR
    ldq SERIAL_BUFFER_START+MLFS_DENTRY_SIZE_BYTES
    stq FS_CON_REQUEST+FS_REQ_OFFSET
    bra F_CON_WRITE_TEXT

; -------------------------------------------------------
;  Split file/text arguments and write text at the requested byte offset.
; -------------------------------------------------------
; input:            FS_CON_REQUEST.path=file and text argument string; offset=0 from dispatch
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_WRITE:
    jsr F_CON_SPLIT
    lbcs F_CON_ERROR

; -------------------------------------------------------
;  Copy parsed console text into the serial buffer and write it to the selected file.
; -------------------------------------------------------
; input:            X=NUL-terminated text; FS_CON_REQUEST.path=file; offset=write position
; output:           Serial result or error; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_WRITE_TEXT:
    ldy #SERIAL_BUFFER_START
    sty FS_CON_REQUEST+FS_REQ_BUFFER
    clrb
F_CON_TEXT_COPY:
    lda ,x+
    beq F_CON_TEXT_READY
    sta ,y+
    incb
    bra F_CON_TEXT_COPY
F_CON_TEXT_READY:
    clra
    std FS_CON_REQUEST+FS_REQ_COUNT
    ldx #FS_CON_REQUEST
    jsr FS_WRITE

; -------------------------------------------------------
;  Print mutation success or its error and resume console input.
; -------------------------------------------------------
; input:            D/CC=mutation status
; output:           Serial OK or error message; continues at F_CON_PROMPT
; clobbers:         D, W, X, Y, U, CC; DP is preserved
; -------------------------------------------------------
F_CON_MUTATION_RESULT:
    lbcs F_CON_ERROR
    ldx #F_CON_OK
    jsr [F_PUTS]
    lbra F_CON_PROMPT
; Split path/text or source/destination at the first space. X=second argument.
; -------------------------------------------------------
;  Split two console arguments at the first space and skip remaining separator spaces.
; -------------------------------------------------------
; input:            FS_CON_REQUEST.path=bounded NUL-terminated argument text in FS_LINE
; output:           D=0/C clear; X and request.buffer=second argument; first argument
;                   NUL-terminated; D=FS_EINVAL/C set on failure
; clobbers:         D, X, CC
; -------------------------------------------------------
F_CON_SPLIT:
    ldx FS_CON_REQUEST+FS_REQ_PATH
F_CON_SPLIT_NEXT:
    lda ,x+
    lbeq F_REQUEST_INVALID
    cmpa #' '
    bne F_CON_SPLIT_NEXT
    clr -1,x
F_CON_SPLIT_SPACE:
    lda ,x
    cmpa #' '
    bne F_CON_SPLIT_DONE
    leax 1,x
    bra F_CON_SPLIT_SPACE
F_CON_SPLIT_DONE:
    tst ,x
    lbeq F_REQUEST_INVALID
    stx FS_CON_REQUEST+FS_REQ_BUFFER
    clrd
    andcc #$FE
    rts

; -------------------------------------------------------
;  Print an entry type, name, hexadecimal size, and newline.
; -------------------------------------------------------
; input:            SERIAL_BUFFER_START=raw directory entry; initialized serial service pointers
; output:           Entry summary emitted to serial
; clobbers:         D, X, CC
; -------------------------------------------------------
F_CON_PRINT_ENTRY:
    lda #'f'
    ldb SERIAL_BUFFER_START+MLFS_DENTRY_FLAGS
    bitb #MLFS_DENTRY_FLAG_DIR
    beq F_CON_ENTRY_FLAG
    lda #'d'
F_CON_ENTRY_FLAG:
    jsr [F_PUTC]
    lda #' '
    jsr [F_PUTC]
    ldx #SERIAL_BUFFER_START+MLFS_DENTRY_NAME
    jsr [F_PUTS]
    lda #' '
    jsr [F_PUTC]
    ldx #SERIAL_BUFFER_START+MLFS_DENTRY_SIZE_BYTES
    jsr F_CON_PRINT_LONG

; -------------------------------------------------------
;  Emit a serial carriage return and line feed.
; -------------------------------------------------------
; input:            F_PUTS=BIOS serial string service
; output:           CR/LF emitted; X advanced past the newline string
; clobbers:         X, CC
; -------------------------------------------------------
F_CON_NEWLINE:
    ldx #F_CON_CRLF
    jmp [F_PUTS]

; -------------------------------------------------------
;  Print a big-endian 32-bit value as eight hexadecimal digits.
; -------------------------------------------------------
; input:            X=address of four-byte value; F_PUTC=BIOS serial byte service
; output:           Eight digits emitted; X preserved
; clobbers:         D, CC
; -------------------------------------------------------
F_CON_PRINT_LONG:
    ldd ,x
    pshs x
    jsr F_CON_PRINT_WORD
    puls x
    ldd 2,x

; -------------------------------------------------------
;  Print a 16-bit value as four hexadecimal digits.
; -------------------------------------------------------
; input:            D=value; F_PUTC=BIOS serial byte service
; output:           Four digits emitted; B preserved
; clobbers:         A, CC
; -------------------------------------------------------
F_CON_PRINT_WORD:
    pshs b
    jsr F_CON_PRINT_BYTE
    puls a

; -------------------------------------------------------
;  Print one byte as two hexadecimal digits.
; -------------------------------------------------------
; input:            A=value; F_PUTC=BIOS serial byte service
; output:           Two digits emitted; A=last ASCII digit
; clobbers:         A, CC
; -------------------------------------------------------
F_CON_PRINT_BYTE:
    pshs a
    lsra
    lsra
    lsra
    lsra
    jsr F_CON_HEX_NIBBLE
    puls a
    anda #15

; -------------------------------------------------------
;  Print one hexadecimal nibble using uppercase letters.
; -------------------------------------------------------
; input:            A=nibble 0..15; F_PUTC=BIOS serial byte service
; output:           One digit emitted; A=ASCII digit
; clobbers:         A, CC
; -------------------------------------------------------
F_CON_HEX_NIBBLE:
    cmpa #9
    bls F_CON_HEX_DIGIT
    adda #7
F_CON_HEX_DIGIT:
    adda #'0'
    jmp [F_PUTC]

; -------------------------------------------------------
;  Return from the serial console after the quit command.
; -------------------------------------------------------
; input:            None
; output:           D=0; C clear
; clobbers:         D, CC
; -------------------------------------------------------
F_CON_EXIT:
    clrd
    andcc #$FE
    rts
F_ROOT_PATH: fcn "/"
F_CON_CRLF: fcb 13,10,0
F_CON_ERASE: fcb 8,32,8,0
F_CON_BANNER:
    fcc "MLFS console (hex sizes/status)"
    fcb 13,10,0
F_CON_HELP:
    fcc "m [0..15], l [path], s path, c path, i, n file, d dir, u file, r dir"
    fcb 13,10
    fcc "v source destination, w file text, a file text, t diagnostic, q"
    fcb 13,10,0
F_CON_PROMPT_TEXT: fcn "mlfs> "
F_CON_MOUNTED: fcc "Mounted."
    fcb 13,10,0
F_CON_USED: fcn "Used blocks: "
F_CON_FREE: fcn " Free blocks: "
F_CON_ERROR_TEXT: fcn "Error: "
F_CON_OK: fcc "OK."
    fcb 13,10,0
F_DIAGNOSTIC_PATH: fcn "/fsdiag.mlp"
