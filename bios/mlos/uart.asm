; Backend defaults: privileged execution, IRQ/FIRQ masked, common data fixed.
; This MLOS backend owns both ACR and IMR shadows; legacy BIOS driver is not
; linked into the harness. All mask changes preserve unrelated source bits.

; Function: rom_uart_init — initialize channel A and shared register shadows.
; Inputs: none. Outputs: UART A 115200 8N1; timer disabled, shadows synchronized.
; Clobbers: A,CC. Preserves: B,X,Y,U,V,W,DP. Stack: 2; bounded writes only.
rom_uart_init:
    lda #$BA
    sta UART_CRA
    lda #$20
    sta UART_CRA
    lda #$30
    sta UART_CRA
    lda #$40
    sta UART_CRA
    lda #1
    sta UART_MRA
    lda #$13
    sta UART_MRA
    lda #7
    sta UART_MRA
    lda #$CC
    sta UART+1
    ifdef MLOS_RUNTIME
    lda #$10
    sta UART+10
    lda #$20
    sta UART+10
    lda #$30
    sta UART+10
    lda #$40
    sta UART+10
    lda #1
    sta UART+8
    lda #$13
    sta UART+8
    lda #7
    sta UART+8
    lda #$CC
    sta UART+9
    lda #4
    sta UART+10
    endc
    lda #$80
    sta UART_ACR_SHADOW
    sta UART_ACR
    clr UART_IMR_SHADOW
    clr UART_IMR
    lda UART_STOP                  ; clear pending timer and stop non-timer mode.
    lda #5
    sta UART_CRA
    rts

; Function: rom_putc — bounded diagnostic byte output.
; Inputs: A=byte. Outputs: C0 sent/C1 timeout. Clobbers: CC. Preserves: D,X,Y,U,V,W.
; Stack: 5 including return. <=1024 status polls; no sleeping or retained data.
rom_putc:
    pshs a,x
    ldx #UART_POLL_LIMIT
rp_wait:
    lda UART_SRA
    bita #4
    bne rp_send
    leax -1,x
    bne rp_wait
    puls a,x
    orcc #1
    rts
rp_send:
    puls a,x
    sta UART_TXA
    andcc #$FE
    rts

; Function: rom_timer_enable — audited combined ACR/IMR ownership demonstration.
; Inputs: none. Outputs: mode7/preload115; nominal 1001.739 Hz; preserves other bits.
; Clobbers: A,CC. Preserves: B,X,Y,U,V,W. Stack: 2; target rate still unmeasured.
rom_timer_enable:
    lda UART_ACR_SHADOW
    anda #$8F
    ora #$70
    sta UART_ACR_SHADOW
    sta UART_ACR
    ifdef MLOS_RUNTIME
    lda #MLOS_TIMER_PRELOAD/256
    sta UART_CTPU
    lda #MLOS_TIMER_PRELOAD%256
    else
    clr UART_CTPU
    lda #115
    endc
    sta UART_CTPL
    lda UART_IMR_SHADOW
    ora #8
    sta UART_IMR_SHADOW
    sta UART_IMR
    lda #0
    sta IRQ_CONTROL
    lda UART_START
    rts
