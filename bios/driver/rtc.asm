; -----------------------------------------------------------------
; RTC Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2024

    IFNDEF IO_INC
        include "../include/io.inc"
    ENDC

RTC_YEAR            EQU  RTC_BASE+0 ; Year
RTC_MONTH           EQU  RTC_BASE+1 ; Bit 0-3 Month, Bit 5-7 Error flags
RTC_DAY             EQU  RTC_BASE+2 ; Bit 0-4 Day, Bit 5-7 Day of week
RTC_HOUR            EQU  RTC_BASE+3 ; Hour
RTC_MINUTE          EQU  RTC_BASE+4 ; Minute
RTC_SECOND          EQU  RTC_BASE+5 ; Second

RTC_FAULT_FLAGS_RTC_ERROR       EQU $01 ; RTC error
RTC_FAULT_FLAGS_MEMORY_ERROR    EQU $02 ; Memory error
RTC_FAULT_FLAGS_CLOCK_ERROR     EQU $03 ; Clock error

; -----------------------------------------------------------------
; RTC INIT
; input:            None
; output:           None
; clobbers:         None
; -----------------------------------------------------------------
RTC_INIT:
    ; TODO: Check if there are any rtc faults

    rts

; -----------------------------------------------------------------
; RTC READ YEAR
; input:            None
; output:           D = Year
; clobbers:         A, D
; -----------------------------------------------------------------
RTC_READ_YEAR:
    ; Load rtc year address in x
    ldx #RTC_YEAR
    ; Load Year base in D
    ldd #$07B2      ; 1970
    ; Add year to base
    addd ,x
    ; Return D
    rts

; -----------------------------------------------------------------
; RTC READ MONTH
; input:            None
; output:           A = Month
; clobbers:         A
; -----------------------------------------------------------------
RTC_READ_MONTH:
    lda RTC_MONTH
    anda #$0F
    rts

; -----------------------------------------------------------------
; RTC READ FAULT_FLAGS
; input:            None
; output:           A = Fault flags
; clobbers:         A
; -----------------------------------------------------------------
RTC_READ_FAULT_FLAGS:
    lda RTC_MONTH
    anda #$E0 ; Mask out flags
    lsra ; Shift right by 5
    lsra
    lsra
    lsra
    lsra
    rts

; -----------------------------------------------------------------
; RTC_DAY
; input:            None
; output:           A = Day
; clobbers:         A
; -----------------------------------------------------------------
RTC_READ_DAY:
    lda RTC_DAY
    anda #$1F
    rts

; -----------------------------------------------------------------
; RTC_DAY_OF_WEEK
; input:            None
; output:           A = Day of Week
; clobbers:         A
; -----------------------------------------------------------------
RTC_READ_DAY_OF_WEEK:
    lda RTC_DAY
    anda #$E0 ; Mask out day of week
    lsra ; Shift right by 5
    lsra
    lsra
    lsra
    lsra
    rts

; -----------------------------------------------------------------
; RTC READ HOUR
; input:            None
; output:           A = Hour
; clobbers:         A
; -----------------------------------------------------------------
RTC_READ_HOUR:
    lda RTC_HOUR
    rts

; -----------------------------------------------------------------
; RTC READ MINUTE
; input:            None
; output:           A = Minute
; clobbers:         A
; -----------------------------------------------------------------
RTC_READ_MINUTE:
    lda RTC_MINUTE
    rts

; -----------------------------------------------------------------
; RTC READ SECOND
; input:            None
; output:           A = Second
; clobbers:         A
; -----------------------------------------------------------------
RTC_READ_SECOND:
    lda RTC_SECOND
    rts

; -----------------------------------------------------------------
; DELAY_MS
; input:            X = Number of milliseconds to delay
; output:           None
; clobbers:         A, X
; There are 2000 cycles per millisecond
; The DELAY_MS function will delay for 11 extra cycles
; -----------------------------------------------------------------
DELAY_MS:
    lda #$7C            ; 2 cycles
DELAY_MS_LOOP:
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    deca                ; 1 cycles
    cmpa #$00           ; 4 cycles
    bne DELAY_MS_LOOP   ; 3 cycles
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    nop                 ; 1 cycle
    leax ,-x            ; 5 cycles
    cmpx #$0000         ; 4 cycles
    bne DELAY_MS        ; 3 cycles
    rts                 ; 4 cycles
