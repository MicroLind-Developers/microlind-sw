; -----------------------------------------------------------------
; CompactFlash BIOS functions for MicroLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2026
;
; CF access is currently byte-wide PIO, LBA28 only. The routines use
; carry clear for success and carry set for failure.

        IFNDEF IO_INC
            include "../include/io.inc"
        ENDC
        IFNDEF MEMORY_INC
            include "../include/memory.inc"
        ENDC

; -----------------------------------------------------------------
; CompactFlash register map
; -----------------------------------------------------------------

CF_DATA                 EQU     CF_BASE+$00
CF_ERROR                EQU     CF_BASE+$01
CF_FEATURES             EQU     CF_BASE+$01
CF_SECTOR_COUNT         EQU     CF_BASE+$02
CF_LBA0                 EQU     CF_BASE+$03
CF_LBA1                 EQU     CF_BASE+$04
CF_LBA2                 EQU     CF_BASE+$05
CF_DRIVE_HEAD           EQU     CF_BASE+$06
CF_STATUS               EQU     CF_BASE+$07
CF_COMMAND              EQU     CF_BASE+$07

; -----------------------------------------------------------------
; Status bits and commands
; -----------------------------------------------------------------

CF_STATUS_ERR           EQU     $01
CF_STATUS_DRQ           EQU     $08
CF_STATUS_DF            EQU     $20
CF_STATUS_RDY           EQU     $40
CF_STATUS_BUSY          EQU     $80

CF_CMD_READ_SECTOR      EQU     $20

CF_LBA_MASTER           EQU     $E0
CF_WAIT_TIMEOUT         EQU     $FFFF

; -----------------------------------------------------------------
; Return codes in A
; -----------------------------------------------------------------

CF_OK                   EQU     $00
CF_ERR_TIMEOUT          EQU     $01
CF_ERR_DEVICE           EQU     $02

; -----------------------------------------------------------------
; CF_INIT
; Select the primary CF device and wait until it is ready.
;
; Out:
;   C clear, A=CF_OK on success
;   C set,   A=error code on failure
; Clobbers:
;   A,U,CC
; -----------------------------------------------------------------

CF_INIT:
        lda     CF_STATUS
        cmpa    #$FF
        bne     _CF_INIT_DEVICE_PRESENT
        lda     #CF_ERR_TIMEOUT
        orcc    #$01
        rts

_CF_INIT_DEVICE_PRESENT:
        lda     #CF_LBA_MASTER
        sta     CF_DRIVE_HEAD
        jsr     CF_WAIT_READY
        rts

; -----------------------------------------------------------------
; CF_READ_SECTOR_BUFFER
; Read one 512-byte sector into STORAGE_BUFFER_START.
;
; In:
;   Q = 28-bit LBA, bits 31..28 must be zero
; Out:
;   C clear, A=CF_OK on success
;   C set,   A=error code on failure
; Clobbers:
;   A,X,Y,U,CC
; -----------------------------------------------------------------

CF_READ_SECTOR_BUFFER:
        ldx     #STORAGE_BUFFER_START
        bra     CF_READ_SECTOR

; -----------------------------------------------------------------
; CF_READ_SECTOR
; Read one 512-byte sector into caller-provided memory.
;
; In:
;   Q = 28-bit LBA, bits 31..28 must be zero
;   X = destination buffer, at least 512 bytes
; Out:
;   C clear, A=CF_OK on success
;   C set,   A=error code on failure
; Clobbers:
;   A,X,Y,U,CC
; -----------------------------------------------------------------

CF_READ_SECTOR:
        pshs    y,u
        leas    -4,s
        stq     0,s

        jsr     CF_WAIT_READY
        bcs     _CF_READ_DONE

        lda     0,s
        anda    #$F0
        beq     _CF_READ_LBA_OK
        lda     #CF_ERR_DEVICE
        orcc    #$01
        bra     _CF_READ_DONE

_CF_READ_LBA_OK:
        lda     #$01
        sta     CF_SECTOR_COUNT
        lda     3,s
        sta     CF_LBA0
        lda     2,s
        sta     CF_LBA1
        lda     1,s
        sta     CF_LBA2
        lda     0,s
        anda    #$0F
        ora     #CF_LBA_MASTER
        sta     CF_DRIVE_HEAD

        lda     #CF_CMD_READ_SECTOR
        sta     CF_COMMAND

        jsr     CF_WAIT_DRQ
        bcs     _CF_READ_DONE

        ldy     #STORAGE_BUFFER_SIZE
_CF_READ_LOOP:
        lda     CF_DATA
        sta     ,x+
        leay    -1,y
        bne     _CF_READ_LOOP

        clra
        andcc   #$FE

_CF_READ_DONE:
        leas    4,s
        puls    y,u,pc

; -----------------------------------------------------------------
; CF_WAIT_NOT_BUSY
; Wait until BSY clears.
;
; Out:
;   C clear, A=CF_OK on success
;   C set,   A=CF_ERR_TIMEOUT on timeout
; Clobbers:
;   A,U,CC
; -----------------------------------------------------------------

CF_WAIT_NOT_BUSY:
        ldu     #CF_WAIT_TIMEOUT
_CF_WNB_LOOP:
        lda     CF_STATUS
        bita    #CF_STATUS_BUSY
        beq     _CF_WAIT_OK
        leau    -1,u
        bne     _CF_WNB_LOOP
        lda     #CF_ERR_TIMEOUT
        orcc    #$01
        rts

; -----------------------------------------------------------------
; CF_WAIT_READY
; Wait until BSY clears and RDY is set.
;
; Out:
;   C clear, A=CF_OK on success
;   C set,   A=CF_ERR_TIMEOUT on timeout
; Clobbers:
;   A,U,CC
; -----------------------------------------------------------------

CF_WAIT_READY:
        ldu     #CF_WAIT_TIMEOUT
_CF_WRDY_LOOP:
        lda     CF_STATUS
        bita    #CF_STATUS_BUSY
        bne     _CF_WRDY_NEXT
        bita    #CF_STATUS_RDY
        bne     _CF_WAIT_OK
_CF_WRDY_NEXT:
        leau    -1,u
        bne     _CF_WRDY_LOOP
        lda     #CF_ERR_TIMEOUT
        orcc    #$01
        rts

; -----------------------------------------------------------------
; CF_WAIT_DRQ
; Wait until a read command has data ready.
;
; Out:
;   C clear, A=CF_OK on success
;   C set,   A=error code on failure
; Clobbers:
;   A,U,CC
; -----------------------------------------------------------------

CF_WAIT_DRQ:
        ldu     #CF_WAIT_TIMEOUT
_CF_WDRQ_LOOP:
        lda     CF_STATUS
        bita    #CF_STATUS_BUSY
        bne     _CF_WDRQ_NEXT
        bita    #CF_STATUS_ERR|CF_STATUS_DF
        bne     _CF_WDRQ_DEVICE_ERROR
        bita    #CF_STATUS_DRQ
        bne     _CF_WAIT_OK
_CF_WDRQ_NEXT:
        leau    -1,u
        bne     _CF_WDRQ_LOOP
        lda     #CF_ERR_TIMEOUT
        orcc    #$01
        rts

_CF_WDRQ_DEVICE_ERROR:
        lda     #CF_ERR_DEVICE
        orcc    #$01
        rts

_CF_WAIT_OK:
        clra
        andcc   #$FE
        rts

; --- End of File ---
