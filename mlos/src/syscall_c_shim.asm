    include "syscalls.inc"
    section code
    export _mlos_call
; Function: _mlos_call — CMOC stack arguments to native SWI v1.
; Inputs: [S+2..3]=promoted u16 call number, [S+4..5]=parameter pointer.
; Outputs: D=raw result/error; C as syscall. Clobbers: D,CC. Preserves: X,Y,U,
; E,F,V,DP,MD. Stack: 4 wrapper +14 hardware + core common stack.
; Context: native application, recorded maps. Copies/ownership/blocking follow
; the chosen syscall. No compiler-dependent binary structures cross the ABI.
_mlos_call:
    pshs x
    lda 4,s
    bne mlos_c_invalid
    lda 5,s
    ldx 6,s
    swi
    puls x,pc
mlos_c_invalid:
    ldd #SYS_EINVAL
    orcc #1
    puls x,pc
    endsection

    section code
    export _mlos_argc,_mlos_argv
; Function: _mlos_argc / _mlos_argv. Inputs initialized SDK startup words.
; Outputs D=argc/argv; clobbers D,CC; preserves all other registers; stack2.
_mlos_argc:
    ldd $0300
    rts
_mlos_argv:
    ldd $0302
    rts
    endsection

    section code
    export _mlos_put_u16
; Function: _mlos_put_u16. Inputs C stack promoted pointer/value words. Outputs
; stores a big-endian word. Clobbers D,CC; preserves X,Y,U,W,V,DP; stack<=4.
_mlos_put_u16:
    pshs x
    ldx 4,s
    ldd 6,s
    std ,x
    puls x,pc
    endsection
