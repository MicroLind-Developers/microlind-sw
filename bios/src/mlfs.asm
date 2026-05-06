; -----------------------------------------------------------------
; MLFS BIOS helper functions
; -----------------------------------------------------------------
; Copyright Eric & Linus Lind 2026
;
; These routines are intended for the BIOS boot path. They implement 
; the small read-only MLFS helpers needed before MLOS is running.
; -----------------------------------------------------------------

; -----------------------------------------------------------------
; MLFS_CKSUM32
; -----------------------------------------------------------------
; Additive 32-bit checksum used by MLFS superblocks.
;
; C reference:
;   uint32_t s = 0;
;   for(size_t i = 0; i < n; i++)
;       s += ((const uint8_t*)p)[i];
;
; input:    X = buffer pointer
;           Y = byte count
; output:   Q = 32-bit additive checksum, big-endian/native order
; clobbers: A, B, W, X, Y, CC
; -----------------------------------------------------------------
MLFS_CKSUM32:
    leas -4,s

    clr 0,s
    clr 1,s
    clr 2,s
    clr 3,s

    cmpy #0
    beq .done

.loop:
    lda ,x+
    adda 3,s
    sta 3,s
    bcc .next

    inc 2,s
    bne .next
    inc 1,s
    bne .next
    inc 0,s

.next:
    leay -1,y
    bne .loop

.done:
    ldq 0,s
    leas 4,s
    rts
