; Copy-module defaults: privileged serialized core, IRQ/FIRQ masked; no sleep.
; Only logical $0000-$BFFF with live owned maps is application memory.
; Zero length succeeds without dereferencing the pointer. Kernel buffers must
; be trusted common/core memory, disjoint from application mappings.

; Function: user_range — validate the ENTIRE range before any device/map access.
; Inputs: X=user pointer, D=byte count. Outputs: C0 or D=EFAULT/C1.
; Clobbers: CC,D on error. Preserves: X,Y,U,V,W; Stack: <=12 including frame_address and return.
; Checks: wrap, common/ROM/I/O, vacant roles, frame bounds/reservation/owner.
user_range:
    pshs x,y,u,d
    tstd
    beq ur_good
    ; PSHS layout D=0,X=2,Y=4,U=6. Check inclusive end without wrap.
    ldd ,s
    addd 2,s
    bcs ur_bad
    subd #1
    cmpd #$C000
    bhs ur_bad
    std COPY_END
    tfr x,d
    lsra
    lsra
    lsra
    lsra
    lsra
    lsra
    tfr a,b
    clra
    tfr d,u                       ; first logical window index
ur_window:
    ldx #PROCESS_ROLE
    tfr u,d
    tst b,x
    beq ur_bad
    ldx #PROCESS_MAP
    lda b,x
    cmpa #3
    blo ur_bad
    cmpa #FRAME_COUNT
    bhs ur_bad
    jsr frame_address
    ldd F_OWNER,x
    cmpd CURRENT_PID
    bne ur_bad
    ldd COPY_END
    lsra
    lsra
    lsra
    lsra
    lsra
    lsra
    tfr a,b
    clra
    pshs d
    cmpu ,s++
    beq ur_good
    leau 1,u
    bra ur_window
ur_good:
    puls d,x,y,u
    andcc #$FE
    rts
ur_bad:
    puls d,x,y,u
    ldd #SYS_EFAULT
    orcc #1
    rts

; Function: copy_in / copy_out — bounded bank-translated synchronous copies.
; Inputs: X=user address, Y=kernel buffer, D=0..256 bytes.
; Outputs: C0/D=0, or EINVAL/EFAULT/C1 with destination unchanged.
; Clobbers: D,X,Y,U. Preserves: V,W; MMU2 restored on all paths.
; Stack: 16 including validation/callee returns. O(bytes*constant + 3 windows).
; Ownership: copies bytes; retains no pointer. See module defaults.
copy_in:
    clr COPY_DIRECTION
    bra copy_start
copy_out:
    std COPY_LENGTH
    lda #1
    sta COPY_DIRECTION
    ldd COPY_LENGTH
copy_start:
    cmpd #SYS_COPY_LIMIT
    lbhi mem_invalid
    std COPY_LENGTH
    jsr user_range
    bcs copy_return
    tfr d,u
    cmpu #0
    beq copy_done
    pshsw
    stx COPY_ADDRESS
    lda MMU2
    sta COPY_SAVED_MAP
copy_chunk:
    ; Copy at most256 bytes, splitting once at a logical-window boundary.
    ldd COPY_ADDRESS
    anda #$3F
    pshs d
    ldd #$4000
    subd ,s++
    pshs u
    cmpd ,s++
    bls copy_chunk_size
    tfr u,d
copy_chunk_size:
    std COPY_LENGTH
    tfr d,w
    ldd COPY_ADDRESS
    lsra
    lsra
    lsra
    lsra
    lsra
    lsra
    ldx #PROCESS_MAP
    lda a,x
    sta MMU2
    ldd COPY_ADDRESS
    anda #$3F
    ora #$80
    tfr d,x
    tst COPY_DIRECTION
    bne copy_tfm_out
    tfm x+,y+
    bra copy_chunk_next
copy_tfm_out:
    tfm y+,x+
copy_chunk_next:
    ldd COPY_ADDRESS
    addd COPY_LENGTH
    std COPY_ADDRESS
    tfr u,d
    subd COPY_LENGTH
    tfr d,u
    bne copy_chunk
    lda COPY_SAVED_MAP
    sta MMU2
    pulsw
copy_done:
    ldd #0
    andcc #$FE
copy_return:
    rts
