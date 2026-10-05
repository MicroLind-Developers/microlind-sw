    include "../../include/module.inc"
    include "../../include/filesystem.inc"
    include "../../include/io.inc"
    include "../../include/memory.inc"
    section code
    export _tg_platform_init,_tg_platform_done,_tg_tick,_tg_joy,_tg_serial,_tg_putc
    export _tg_vram,_tg_vram_read,_tg_cell,_tg_reg,_tg_reg_read,_tg_clear
    export _tg_sound,_tg_effect,_tg_ticks

; -------------------------------------------------------
;  Validate module APIs and claim the idle VIA timers for the game.
; -------------------------------------------------------
; input:            BIOS/FS descriptors saved at $04F0/$04F2; initialized VDC
; output:           D=1 on success, 0 on unsupported ABI/display or busy timers
; clobbers:         D, X, CC; U, Y, DP preserved; IRQ enabled on success
; -------------------------------------------------------
_tg_platform_init:
    ldx $04F0
    cmpx #BIOS_MODULE_API_BASE
    lbne TG_INIT_FAIL
    ldd ,x
    cmpd #$4D42
    lbne TG_INIT_FAIL
    ldd 2,x
    cmpd #$5231
    lbne TG_INIT_FAIL
    ldd 4,x
    cmpd #BIOS_MODULE_API_VERSION
    lbne TG_INIT_FAIL
    ldd 6,x
    cmpd #18
    lblo TG_INIT_FAIL
    ldx $04F2
    cmpx #FS_API_BASE
    lbne TG_INIT_FAIL
    ldd ,x
    cmpd #$4653
    lbne TG_INIT_FAIL
    ldd 2,x
    cmpd #$5231
    lbne TG_INIT_FAIL
    ldd 4,x
    cmpd #FS_API_VERSION
    lbne TG_INIT_FAIL
    ldd 6,x
    cmpd #FS_API_COUNT
    lblo TG_INIT_FAIL
    tst VDC_INITIALIZED_FLAG
    lbeq TG_INIT_FAIL
    lda PARALLEL_BASE+14
    bita #$60
    lbne TG_INIT_FAIL
    lda PARALLEL_BASE+11
    bita #$C0                       ; Do not take over an existing T1/PB7 tone.
    lbne TG_INIT_FAIL
    tfr cc,a
    sta TG_OLD_CC
    orcc #$50
    lda IRQ_BASE
    anda #$F0
    sta TG_OLD_FILTER
    lda PARALLEL_BASE+11
    sta TG_OLD_ACR
    lda PARALLEL_BASE
    sta TG_OLD_ORB
    lda PARALLEL_BASE+2
    sta TG_OLD_DDRB
    lda PARALLEL_BASE+14
    anda #$7F
    sta TG_OLD_IER
    lda PARALLEL_BASE+6
    sta TG_OLD_T1
    lda PARALLEL_BASE+7
    sta TG_OLD_T1+1
    ldd VDC_CURSOR_ROW
    std TG_OLD_CURSOR
    ldx #TG_HANDLER
    jsr BIOS_MODULE_IRQ_INSTALL
    stx TG_OLD_HANDLER
    lda #$7F
    sta PARALLEL_BASE+14
    lda TG_OLD_ACR
    anda #$1F                       ; Timed T2; disable PB7 until sound is enabled.
    sta PARALLEL_BASE+11
    lda TG_OLD_DDRB
    ora #$80
    sta PARALLEL_BASE+2
    lda TG_OLD_ORB
    anda #$7F
    sta PARALLEL_BASE
    clr _tg_ticks
    clr _tg_ticks+1
    clr TG_NOTE_LEFT
    clr TG_NOTE_INDEX
    clr TG_FX_LEFT
    clr TG_FX_PENDING
    clr TG_SOUND_ON
    lda #$60
    sta PARALLEL_BASE+13
    clr IRQ_BASE
    lda #$A0
    sta PARALLEL_BASE+14
    ldd #19998                      ; Nominal 10 ms with the board's 2 MHz VIA.
    stb PARALLEL_BASE+8
    sta PARALLEL_BASE+9
    inc TG_OWNED
    andcc #$EF
    ldd #1
    rts

; -------------------------------------------------------
;  Return an unsupported-platform result without changing peripheral state.
; -------------------------------------------------------
; input:            None
; output:           D=0
; clobbers:         D, CC
; -------------------------------------------------------
TG_INIT_FAIL:
    clrd
    rts

; -------------------------------------------------------
;  Stop the game tick/audio and restore the previous BIOS hardware context.
; -------------------------------------------------------
; input:            TG_OWNED and saved VIA/IRQ/cursor configuration
; output:           Prior handler, masks, port configuration and cursor restored
; clobbers:         D, X, CC; U, Y, DP preserved
; -------------------------------------------------------
_tg_platform_done:
    tst TG_OWNED
    beq TG_DONE_RETURN
    orcc #$50
    clr TG_OWNED
    clr TG_SOUND_ON
    lda #$7F
    sta PARALLEL_BASE+14
    lda #$60
    sta PARALLEL_BASE+13
    lda TG_OLD_ACR
    sta PARALLEL_BASE+11
    lda TG_OLD_ORB
    sta PARALLEL_BASE
    lda TG_OLD_DDRB
    sta PARALLEL_BASE+2
    lda TG_OLD_T1
    sta PARALLEL_BASE+6
    lda TG_OLD_T1+1
    sta PARALLEL_BASE+7
    ldx TG_OLD_HANDLER
    jsr BIOS_MODULE_IRQ_INSTALL
    lda TG_OLD_IER
    ora #$80
    sta PARALLEL_BASE+14
    lda TG_OLD_FILTER
    sta IRQ_BASE
    ldd TG_OLD_CURSOR
    jsr BIOS_MODULE_VDC_CURSOR
    lda TG_OLD_CC
    tfr a,cc
TG_DONE_RETURN:
    rts

; -------------------------------------------------------
;  Read the wrapping 16-bit tick counter with IRQ masked during the read.
; -------------------------------------------------------
; input:            None
; output:           D=ticks; original IRQ mask and CC restored
; clobbers:         D
; -------------------------------------------------------
_tg_tick:
    pshs cc
    orcc #$10
    ldd _tg_ticks
    puls cc,pc

; -------------------------------------------------------
;  Read joystick 1 as a C integer containing pressed bits.
; -------------------------------------------------------
; input:            None
; output:           D=up/down/left/right/button mask in bits 0..4
; clobbers:         D, CC
; -------------------------------------------------------
_tg_joy:
    jsr BIOS_MODULE_JOY1
    tfr a,b
    clra
    rts

; -------------------------------------------------------
;  Poll serial input without waiting or echoing.
; -------------------------------------------------------
; input:            None
; output:           D=byte, or -1 when no input is available
; clobbers:         D, CC
; -------------------------------------------------------
_tg_serial:
    jsr BIOS_MODULE_SERIAL_GETC
    bcs TG_VALUE_ERROR
    tfr a,b
    clra
    rts

; -------------------------------------------------------
;  Emit the low byte of one CMOC integer to serial.
; -------------------------------------------------------
; input:            [S+2]=character
; output:           Character sent
; clobbers:         A, CC
; -------------------------------------------------------
_tg_putc:
    lda 3,s
    jmp BIOS_MODULE_SERIAL_PUTC

; -------------------------------------------------------
;  Write one VDC-local byte using the register ABI.
; -------------------------------------------------------
; input:            [S+2]=VRAM address; [S+4]=byte value
; output:           D=0 or -1 on VDC timeout
; clobbers:         D, X, CC
; -------------------------------------------------------
_tg_vram:
    ldx 2,s
    lda 5,s
    jsr BIOS_MODULE_VDC_BYTE
    bra TG_DISPLAY_RESULT

; -------------------------------------------------------
;  Read one VDC-local byte for glyph preservation.
; -------------------------------------------------------
; input:            [S+2]=VRAM address
; output:           D=byte or -1 on VDC timeout
; clobbers:         D, X, CC
; -------------------------------------------------------
_tg_vram_read:
    ldx 2,s
    jsr BIOS_MODULE_VDC_ADDRESS
    bcs TG_VALUE_ERROR
    lda #31
    jsr BIOS_MODULE_VDC_READ
    bcs TG_VALUE_ERROR
    clra
    rts

; -------------------------------------------------------
;  Write the two character/attribute columns of one colored board cell.
; -------------------------------------------------------
; input:            [S+2]=text address; [S+4]=glyph; [S+6]=attribute
; output:           D=0 or -1 on VDC timeout
; clobbers:         D, X, CC
; -------------------------------------------------------
_tg_cell:
    ldx 2,s
    jsr BIOS_MODULE_VDC_ADDRESS
    bcs TG_VALUE_ERROR
    lda #31
    ldb 5,s
    jsr BIOS_MODULE_VDC_WRITE
    bcs TG_VALUE_ERROR
    ldb 5,s
    jsr BIOS_MODULE_VDC_SELECTED
    bcs TG_VALUE_ERROR
    leax $0800,x
    jsr BIOS_MODULE_VDC_ADDRESS
    bcs TG_VALUE_ERROR
    lda #31
    ldb 7,s
    jsr BIOS_MODULE_VDC_WRITE
    bcs TG_VALUE_ERROR
    ldb 7,s
    jsr BIOS_MODULE_VDC_SELECTED
    bra TG_DISPLAY_RESULT

; -------------------------------------------------------
;  Write one VDC configuration register from CMOC arguments.
; -------------------------------------------------------
; input:            [S+2]=register index; [S+4]=value
; output:           D=0 or -1 on VDC timeout
; clobbers:         D, CC
; -------------------------------------------------------
_tg_reg:
    lda 3,s
    ldb 5,s
    jsr BIOS_MODULE_VDC_WRITE
    bra TG_DISPLAY_RESULT

; -------------------------------------------------------
;  Read one VDC register without modifying its contents.
; -------------------------------------------------------
; input:            [S+2]=register index
; output:           D=byte or -1 on VDC timeout
; clobbers:         D, CC
; -------------------------------------------------------
_tg_reg_read:
    lda 3,s
    jsr BIOS_MODULE_VDC_READ
    bcs TG_VALUE_ERROR
    clra
    rts

; -------------------------------------------------------
;  Clear the BIOS text and attribute planes.
; -------------------------------------------------------
; input:            Initialized VDC and BIOS text state
; output:           D=0 or -1 on VDC timeout
; clobbers:         D, CC; X, Y preserved
; -------------------------------------------------------
_tg_clear:
    jsr BIOS_MODULE_VDC_CLEAR
TG_DISPLAY_RESULT:
    bcs TG_VALUE_ERROR
    clrd
    rts

; -------------------------------------------------------
;  Return a signed C failure from a peripheral wrapper.
; -------------------------------------------------------
; input:            None
; output:           D=-1
; clobbers:         D, CC
; -------------------------------------------------------
TG_VALUE_ERROR:
    ldd #-1
    rts

; -------------------------------------------------------
;  Enable or silence the nonblocking melody and clear pending effects.
; -------------------------------------------------------
; input:            [S+2]=0 for silence, nonzero for sound
; output:           Audio state changed atomically with respect to the tick IRQ
; clobbers:         D; caller CC restored
; -------------------------------------------------------
_tg_sound:
    pshs cc
    orcc #$10
    lda 4,s
    sta TG_SOUND_ON
    clr TG_NOTE_LEFT
    clr TG_FX_LEFT
    clr TG_FX_PENDING
    jsr TG_SILENCE
    puls cc,pc

; -------------------------------------------------------
;  Queue a short rotation/lock/clear/game-over tone for the next tick.
; -------------------------------------------------------
; input:            [S+2]=effect ID 1..4; out-of-range values ignored
; output:           Pending effect updated if valid
; clobbers:         A; caller CC restored
; -------------------------------------------------------
_tg_effect:
    pshs cc
    orcc #$10
    lda 4,s
    beq TG_EFFECT_RETURN
    cmpa #4
    bhi TG_EFFECT_RETURN
    sta TG_FX_PENDING
TG_EFFECT_RETURN:
    puls cc,pc

; -------------------------------------------------------
;  Rearm Timer 2, increment ticks, and advance the single-voice audio state.
; -------------------------------------------------------
; input:            VIA IRQ; saved full CPU interrupt frame on S
; output:           Tick/audio updated, or previous handler used for another IRQ
; clobbers:         D, X internally; interrupted registers restored by RTI
; -------------------------------------------------------
TG_HANDLER:
    lda PARALLEL_BASE+13
    bita #$20
    beq TG_CHAIN_IRQ
    lda PARALLEL_BASE+8
    ldd #19998
    stb PARALLEL_BASE+8
    sta PARALLEL_BASE+9
    ldd _tg_ticks
    addd #1
    std _tg_ticks
    tst TG_SOUND_ON
    beq TG_IRQ_SILENT
    lda TG_FX_PENDING
    beq TG_FX_PLAYING
    clr TG_FX_PENDING
    deca
    ldb #3
    mul
    ldx #TG_EFFECTS
    leax d,x
    lda ,x
    sta TG_FX_LEFT
    ldd 1,x
    jsr TG_TONE
    rti
TG_FX_PLAYING:
    tst TG_FX_LEFT
    beq TG_MUSIC
    dec TG_FX_LEFT
    bne TG_IRQ_RETURN
    ldd TG_NOTE_PERIOD
    jsr TG_TONE
    rti
TG_MUSIC:
    tst TG_NOTE_LEFT
    beq TG_NEXT_NOTE
    dec TG_NOTE_LEFT
    bne TG_IRQ_RETURN
TG_NEXT_NOTE:
    lda TG_NOTE_INDEX
    ldb #3
    mul
    ldx #TG_MELODY
    leax d,x
    lda ,x
    sta TG_NOTE_LEFT
    ldd 1,x
    std TG_NOTE_PERIOD
    jsr TG_TONE
    inc TG_NOTE_INDEX
    lda TG_NOTE_INDEX
    cmpa #16
    blo TG_IRQ_RETURN
    clr TG_NOTE_INDEX
TG_IRQ_RETURN:
    rti
TG_IRQ_SILENT:
    jsr TG_SILENCE
    rti
TG_CHAIN_IRQ:
    jmp [TG_OLD_HANDLER]

; -------------------------------------------------------
;  Start a Timer 1 PB7 half-period, or silence a zero period.
; -------------------------------------------------------
; input:            D=timer reload; called only with IRQ masked or from IRQ
; output:           Timer 1 PB7 tone configured
; clobbers:         D, CC
; -------------------------------------------------------
TG_TONE:
    tstd
    beq TG_SILENCE
    stb PARALLEL_BASE+4
    sta PARALLEL_BASE+5
    lda PARALLEL_BASE+11
    ora #$C0
    sta PARALLEL_BASE+11
    rts

; -------------------------------------------------------
;  Disable PB7 timer output and hold the speaker pin low.
; -------------------------------------------------------
; input:            Game owns the VIA; IRQ masked or in IRQ
; output:           Speaker silent; Timer 2 mode retained
; clobbers:         A, CC
; -------------------------------------------------------
TG_SILENCE:
    lda PARALLEL_BASE+11
    anda #$3F
    sta PARALLEL_BASE+11
    lda PARALLEL_BASE
    anda #$7F
    sta PARALLEL_BASE
    rts

; Original short melody; each entry is duration in 10 ms ticks and T1 reload.
TG_MELODY:
    fcb 20
    fdb 1000000/294-2
    fcb 20
    fdb 1000000/440-2
    fcb 40
    fdb 1000000/349-2
    fcb 20
    fdb 1000000/392-2
    fcb 20
    fdb 1000000/587-2
    fcb 40
    fdb 1000000/494-2
    fcb 20
    fdb 1000000/392-2
    fcb 20
    fdb 1000000/440-2
    fcb 40
    fdb 1000000/330-2
    fcb 20
    fdb 1000000/523-2
    fcb 20
    fdb 1000000/440-2
    fcb 40
    fdb 1000000/392-2
    fcb 20
    fdb 1000000/349-2
    fcb 20
    fdb 1000000/330-2
    fcb 40
    fdb 1000000/294-2
    fcb 20
    fdb 0
TG_EFFECTS:
    fcb 6
    fdb 1000000/659-2
    fcb 10
    fdb 1000000/220-2
    fcb 24
    fdb 1000000/784-2
    fcb 36
    fdb 1000000/147-2
    endsection

    section bss
_tg_ticks: rmb 2
TG_OLD_HANDLER: rmb 2
TG_OLD_CURSOR: rmb 2
TG_OLD_CC: rmb 1
TG_OLD_FILTER: rmb 1
TG_OLD_ACR: rmb 1
TG_OLD_ORB: rmb 1
TG_OLD_DDRB: rmb 1
TG_OLD_IER: rmb 1
TG_OLD_T1: rmb 2
TG_OWNED: rmb 1
TG_SOUND_ON: rmb 1
TG_NOTE_LEFT: rmb 1
TG_NOTE_INDEX: rmb 1
TG_NOTE_PERIOD: rmb 2
TG_FX_PENDING: rmb 1
TG_FX_LEFT: rmb 1
    endsection
