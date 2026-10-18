; Versioned expansion-controller adaptation. Only this layer owns global
; pending/mask addresses. All bindings default unassigned: no guessed I/O.
; Card modules receive their device resources, never these global registers.
BACKPLANE_TABLE equ $DE00
BACKPLANE_COUNT equ 2
BACKPLANE_SIZE equ 8
BP_VERSION equ 0
BP_ENABLED equ 1
BP_PENDING equ 2
BP_MASK equ 4
BP_ROUTE equ 6

; Binding record v1: version, software enable shadow, pending address word,
; mask address word, upstream route byte, reserved0. Pending is non-clearing,
; active high slots1..6; hardware mask is active high/reset-disabled. Exact
; addresses/route are unassigned until hardware qualification, not auto-probed.
backplane_bindings:
    fcb 1,0
    fdb 0,0
    fcb 0,0
    fcb 1,0
    fdb 0,0
    fcb 0,0

; Function: backplane_init. Inputs none. Outputs masked configured controllers.
; Clobbers D,X,Y,U,W; stack<=2. Called once with privileged maps, IRQ masked.
backplane_init:
    ldx #backplane_bindings
    ldy #BACKPLANE_TABLE
    ldw #BACKPLANE_COUNT*BACKPLANE_SIZE
    tfm x+,y+
    ldy #BACKPLANE_TABLE
bp_init_next:
    clr BP_ENABLED,y
    lda BP_VERSION,y
    cmpa #1
    bne bp_init_skip
    ldd BP_PENDING,y
    beq bp_init_skip
    ldu BP_MASK,y
    beq bp_init_skip
    clr ,u                       ; reset-disabled; never acknowledge pending
bp_init_skip:
    leay BACKPLANE_SIZE,y
    cmpy #BACKPLANE_TABLE+BACKPLANE_COUNT*BACKPLANE_SIZE
    blo bp_init_next
    rts

; Function: backplane_lookup. Inputs B=controller0..1. Outputs Y=record/C0;
; invalid/unbound/version mismatch ENODEV/C1. Clobbers D,Y, stack<=2.
backplane_lookup:
    cmpb #BACKPLANE_COUNT
    bhs bp_unbound
    lda #BACKPLANE_SIZE
    mul
    ldy #BACKPLANE_TABLE
    leay d,y
    lda BP_VERSION,y
    cmpa #1
    bne bp_unbound
    ldd BP_PENDING,y
    beq bp_unbound
    ldd BP_MASK,y
    beq bp_unbound
    andcc #$FE
    rts
bp_unbound:
    ldd #SYS_ENODEV
    orcc #1
    rts

; Function: backplane_pending. Inputs B=controller. Outputs D=enabled pending
; slots0..5/C0 or error/C1. Clobbers X,Y. Non-clearing snapshot; no card ACK.
; Core dispatch must defer bounded card work and recheck after enable/ACK.
backplane_pending:
    jsr backplane_lookup
    bcs bp_pending_done
    ldx BP_PENDING,y
    ldb ,x
    andb #$3F
    andb BP_ENABLED,y
    clra
    andcc #$FE
bp_pending_done:
    rts

; Function: backplane_set_mask. Inputs A=requested enables, B=controller.
; Outputs D0/C0 or ENODEV/C1; clobbers X,Y. IRQ-masked core call only.
; Mask reserved bits, commit hardware before shadow. Device causes remain
; latched; caller rechecks pending before leaving the deferred-service path.
backplane_set_mask:
    pshs a
    jsr backplane_lookup
    bcs bp_mask_error
    puls a
    anda #$3F
    ldx BP_MASK,y
    sta ,x
    sta BP_ENABLED,y
    ldd #0
    andcc #$FE
    rts
bp_mask_error:
    leas 1,s
    rts
