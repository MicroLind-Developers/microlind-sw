    include "syscalls.inc"
    include "runtime/state.inc"
    org $4000
; Function: delay_bind. Inputs U=device,Y=private state. Outputs0/C0 for delay
; 1..32767; EINVAL/C1 otherwise. Clobbers D,CC. Constant bounded trusted callback.
delay_bind:
    ldd D_DELAY,u
    beq delay_bad
    bita #$80
    bne delay_bad
    std ,y
    clr 2,y
    clr 3,y
    ldd #0
    andcc #$FE
    rts
delay_bad:
    ldd #SYS_EINVAL
    orcc #1
    rts
; Function: delay_poll. Inputs D=now16,X=request,Y=private state. Outputs pending
; EAGAIN/C1 or0/C0 at request deadline. Counts completions per instance. Clobbers D.
delay_poll:
    subd R_DEADLINE+2,x
    bita #$80
    bne delay_pending
    ldd 2,y
    addd #1
    std 2,y
    ldd #0
    andcc #$FE
    rts
delay_pending:
    ldd #SYS_EAGAIN
    orcc #1
    rts
; Function: delay_stop. Inputs instance/request. Outputs0/C0; no external work.
; Clobbers D,CC. PIO-less mock has no callback after completion or stop.
delay_stop:
    ldd #0
    andcc #$FE
    rts
