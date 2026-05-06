; -----------------------------------------------------------------
; BIOS configuration detection for MicroLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2026
;
; Boot-time hardware probing routines. The RAM chip probe assumes
; 512 KiB RAM chips installed contiguously from chip 0.

        IFNDEF IO_INC
            include "../include/io.inc"
        ENDC
        IFNDEF MEMORY_INC
            include "../include/memory.inc"
        ENDC

; -----------------------------------------------------------------
; Configuration RAM layout
; -----------------------------------------------------------------

CONFIG_RAM_CHIP_COUNT       EQU CONFIG_DATA_START+$00
CONFIG_RAM_PROBE_INDEX      EQU CONFIG_DATA_START+$01
CONFIG_RAM_PROBE_SAVE       EQU CONFIG_DATA_START+$02 ; 8 bytes
CONFIG_RAM_ORIG_MMU_1       EQU CONFIG_DATA_START+$0A
CONFIG_RAM_CAND_SAVE        EQU CONFIG_DATA_START+$0B
CONFIG_CF_PRESENT_FLAG      EQU CONFIG_DATA_START+$0C

CONFIG_MAX_RAM_CHIPS        EQU 8
CONFIG_PROBE_ADDR           EQU $4000    ; MMU register 1 window
CONFIG_PROBE_MARKER_BASE    EQU $A0

; -----------------------------------------------------------------
; CONFIG_DETECT_RAM_CHIPS
; Detect how many 512 KiB RAM chips are installed.
;
; Output:
;   A = number of detected 512 KiB RAM chips, 0..8
;   CONFIG_RAM_CHIP_COUNT = same value
;
; Clobbers:
;   A,B,X,CC
;
; Notes:
;   The probe maps each chip start into the $4000-$7FFF window using
;   MMU register 1. It writes one byte per detected chip, detects
;   address aliasing, restores the original bytes, and restores MMU1.
; -----------------------------------------------------------------

CONFIG_DETECT_RAM_CHIPS:
        lda     MMU_BASE+1
        sta     CONFIG_RAM_ORIG_MMU_1

        clr     CONFIG_RAM_CHIP_COUNT
        clr     CONFIG_RAM_PROBE_INDEX

_CONFIG_PROBE_NEXT:
        lda     CONFIG_RAM_PROBE_INDEX
        cmpa    #CONFIG_MAX_RAM_CHIPS
        bhs     _CONFIG_PROBE_DONE

        jsr     _CONFIG_MARK_DETECTED_CHIPS

        lda     CONFIG_RAM_PROBE_INDEX
        jsr     _CONFIG_MAP_RAM_CHIP
        lda     CONFIG_PROBE_ADDR
        sta     CONFIG_RAM_CAND_SAVE

        lda     CONFIG_RAM_PROBE_INDEX
        adda    #CONFIG_PROBE_MARKER_BASE
        sta     CONFIG_PROBE_ADDR

        jsr     _CONFIG_VERIFY_DETECTED_CHIPS
        bcs     _CONFIG_PROBE_DONE

        lda     CONFIG_RAM_PROBE_INDEX
        jsr     _CONFIG_MAP_RAM_CHIP
        ldb     CONFIG_RAM_PROBE_INDEX
        tfr     b,a
        adda    #CONFIG_PROBE_MARKER_BASE
        cmpa    CONFIG_PROBE_ADDR
        bne     _CONFIG_PROBE_DONE

        lda     CONFIG_RAM_CAND_SAVE
        ldb     CONFIG_RAM_PROBE_INDEX
        ldx     #CONFIG_RAM_PROBE_SAVE
        abx
        sta     ,x

        inc     CONFIG_RAM_CHIP_COUNT
        inc     CONFIG_RAM_PROBE_INDEX
        bra     _CONFIG_PROBE_NEXT

_CONFIG_PROBE_DONE:
        jsr     _CONFIG_RESTORE_DETECTED_CHIPS
        lda     CONFIG_RAM_ORIG_MMU_1
        sta     MMU_BASE+1
        lda     CONFIG_RAM_CHIP_COUNT
        rts

; -----------------------------------------------------------------
; CONFIG_GET_MEMORY_SIZE
; Return the detected RAM size in 512 KiB units.
;
; Output:
;   A = detected 512 KiB RAM chip count
; -----------------------------------------------------------------

CONFIG_GET_MEMORY_SIZE:
        lda     CONFIG_RAM_CHIP_COUNT
        rts

; -----------------------------------------------------------------
; _CONFIG_MARK_DETECTED_CHIPS
; Write unique marker bytes to all chips currently counted as present.
; -----------------------------------------------------------------

_CONFIG_MARK_DETECTED_CHIPS:
        clrb
_CONFIG_MARK_LOOP:
        cmpb    CONFIG_RAM_CHIP_COUNT
        bhs     _CONFIG_MARK_DONE

        tfr     b,a
        jsr     _CONFIG_MAP_RAM_CHIP
        tfr     b,a
        adda    #CONFIG_PROBE_MARKER_BASE
        sta     CONFIG_PROBE_ADDR

        incb
        bra     _CONFIG_MARK_LOOP

_CONFIG_MARK_DONE:
        rts

; -----------------------------------------------------------------
; _CONFIG_VERIFY_DETECTED_CHIPS
; Verify that the candidate write did not alias any known chip.
; -----------------------------------------------------------------

_CONFIG_VERIFY_DETECTED_CHIPS:
        clrb
_CONFIG_VERIFY_LOOP:
        cmpb    CONFIG_RAM_CHIP_COUNT
        bhs     _CONFIG_VERIFY_OK

        tfr     b,a
        jsr     _CONFIG_MAP_RAM_CHIP
        tfr     b,a
        adda    #CONFIG_PROBE_MARKER_BASE
        cmpa    CONFIG_PROBE_ADDR
        bne     _CONFIG_VERIFY_ALIAS

        incb
        bra     _CONFIG_VERIFY_LOOP

_CONFIG_VERIFY_OK:
        andcc   #$FE
        rts

_CONFIG_VERIFY_ALIAS:
        orcc    #$01
        rts

; -----------------------------------------------------------------
; _CONFIG_RESTORE_DETECTED_CHIPS
; Restore original probe bytes for detected chips.
; -----------------------------------------------------------------

_CONFIG_RESTORE_DETECTED_CHIPS:
        clrb
_CONFIG_RESTORE_LOOP:
        cmpb    CONFIG_RAM_CHIP_COUNT
        bhs     _CONFIG_RESTORE_DONE

        tfr     b,a
        jsr     _CONFIG_MAP_RAM_CHIP
        ldx     #CONFIG_RAM_PROBE_SAVE
        abx
        lda     ,x
        sta     CONFIG_PROBE_ADDR

        incb
        bra     _CONFIG_RESTORE_LOOP

_CONFIG_RESTORE_DONE:
        rts

; -----------------------------------------------------------------
; _CONFIG_MAP_RAM_CHIP
; Map the start of a 512 KiB chip into $4000-$7FFF.
;
; Input:
;   A = chip index, 0..7
; Output:
;   MMU register 1 = chip index * 32
; Clobbers:
;   A,CC
; -----------------------------------------------------------------

_CONFIG_MAP_RAM_CHIP:
        asla
        asla
        asla
        asla
        asla
        sta     MMU_BASE+1
        rts
