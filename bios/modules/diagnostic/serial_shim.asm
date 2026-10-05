    section code
    export _diag_putc
_diag_putc:
    lda 3,s
    jmp [$041C]
    endsection
