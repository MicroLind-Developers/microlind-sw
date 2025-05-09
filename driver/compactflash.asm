; -----------------------------------------------------------------
; Compact Flash Bios functions for µLind
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2025
;   



; This is an example, not production code. It is not tested and may not work as expected.



; ; Minimal CompactFlash Sector Read Example for 6809/6309
; ; Target: microLind system CF interface

;     org $F000

; ; --- CompactFlash Register Map (example) ---
; CF_DATA         equ $F800   ; Data register (read/write)
; CF_ERROR        equ $F801   ; Error register (read only)
; CF_FEATURES     equ $F801   ; Features register (write only)
; CF_SECTOR_COUNT equ $F802
; CF_LBA0         equ $F803
; CF_LBA1         equ $F804
; CF_LBA2         equ $F805
; CF_DRIVE_HEAD   equ $F806
; CF_STATUS       equ $F807   ; Status register (read)
; CF_COMMAND      equ $F807   ; Command register (write)

; ; --- RAM Buffer for 1 Sector (512 bytes) ---
;     org $0100
; CF_SECTOR_BUFFER rmb 512

; ; --- Constants ---
; CF_STATUS_DRQ   equ $08      ; Data Request bit
; CF_STATUS_BUSY  equ $80      ; Busy bit

; ; --- Code Starts ---

; read_sector_0:
;     ; Setup LBA to 0
;     lda #$00
;     sta CF_LBA0
;     sta CF_LBA1
;     sta CF_LBA2

;     ; Drive/Head register: LBA mode (bit 6 = 1), drive 0 (bit 4 = 0)
;     lda #$E0        ; 1110 0000b = LBA mode, drive 0
;     sta CF_DRIVE_HEAD

;     ; Request to read 1 sector
;     lda #$01
;     sta CF_SECTOR_COUNT

;     ; Issue READ SECTOR command
;     lda #$20
;     sta CF_COMMAND

; .wait_not_busy:
;     lda CF_STATUS
;     bita #CF_STATUS_BUSY
;     bne .wait_not_busy   ; Wait while Busy

; .wait_drq:
;     lda CF_STATUS
;     bita #CF_STATUS_DRQ
;     beq .wait_drq        ; Wait until DRQ is set

;     ; Now ready to read 512 bytes
;     ldx #CF_SECTOR_BUFFER
;     ldb #$00             ; 512 byte counter (high byte)
;     ldy #512             ; Number of bytes to read

; .read_loop:
;     lda CF_DATA          ; Read one byte from CF
;     sta ,x+
;     leay -1,y
;     bne .read_loop

;     rts

; ; --- End of File ---