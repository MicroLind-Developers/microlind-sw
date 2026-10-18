; Syscall defaults: called by ROM with U=current common entry record; kernel
; window0 active, common stack, IRQ/FIRQ masked. Native mode/DP=0. Internal
; scratch: D,X,Y,U,W,V; ROM restores every application register except D/C.
; Never sleeps in S02. All parameter/payload pointers are copied/validated.

; Function: syscall_dispatch — numbered ABI v1. Inputs: U=entry record.
; Outputs: saved D and C only; other stacked CC bits preserved. Clobbers: all.
; Stack: bounded common stack; no application-pointer dereferences here.
syscall_dispatch:
    pshs u
    lda N_A,u
    cmpa #SYS_ENTRY_TEST
    ifdef MLOS_RUNTIME
    bhi sc_extended
    else
    bhi sc_unknown
    endc
    ldx N_X,u
    ldb #0
    cmpa #SYS_WRITE
    beq sc_param4
    cmpa #SYS_BANK_MAP
    beq sc_param3
    cmpa #SYS_BANK_FREE
    beq sc_param2
    cmpa #SYS_BANK_UNMAP
    beq sc_param1
    cmpa #SYS_MEMORY_INFO
    beq sc_param2
    cmpa #SYS_COPY
    beq sc_param6
    bra sc_ready
sc_param1:
    ldb #SYS_BANK_UNMAP_PARAMS_SIZE
    bra sc_read_params
sc_param2:
    ldb #SYS_BANK_FREE_PARAMS_SIZE
    bra sc_read_params
sc_param3:
    ldb #SYS_BANK_MAP_PARAMS_SIZE
    bra sc_read_params
sc_param4:
    ldb #SYS_WRITE_PARAMS_SIZE
    bra sc_read_params
sc_param6:
    ldb #SYS_COPY_PARAMS_SIZE
sc_read_params:
    clra
    ldy #PARAM_BUFFER
    jsr copy_in
    bcs sc_finish
sc_ready:
    ldu ,s
    ldb N_A,u
    ldx #sc_table
    lslb
    ifdef MLOS_RUNTIME
    cmpb #SYS_WRITE*2
    bne sc_runtime_ordinary
    ldd PARAM_BUFFER+2
    std TTY_LAST
    jsr tty_write
    bra sc_finish
sc_runtime_ordinary:
    endc
    jsr [b,x]
sc_finish:
    std SC_RESULT
    tfr cc,a
    puls u
    bita #1
    bne sc_error
    lda N_CC,u
    anda #$FE
    sta N_CC,u
    bra sc_save
sc_error:
    lda N_CC,u
    ora #1
    sta N_CC,u
sc_save:
    ; A was used to edit CC: result D is retained independently below.
    ldd SC_RESULT
    std N_A,u
    rts
    ifdef MLOS_RUNTIME
sc_extended:
    jsr runtime_dispatch
    bra sc_finish
    endc
sc_unknown:
    ldd #SYS_ENOSYS
    orcc #1
    std SC_RESULT
    bra sc_finish
sc_table:
    fdb sc_probe,sc_write,sc_alloc,sc_free,sc_map,sc_unmap,sc_info,sc_copy,sc_entry

; Function: sc_probe — ABI discovery. Inputs: none. Outputs: D=ABI version/C0.
; Clobbers: D,CC. Stack: 2; syscall defaults.
sc_probe:
    ldd #ABI_VERSION
    bra sc_ok

; Function: sc_alloc / sc_free / sc_map / sc_unmap — bank API adapters.
; Inputs: copied PARAM_BUFFER as specified in ABI. Outputs: D/C.
; Clobbers: D,X,Y,U. Stack: callee+4. See memory-module contracts/defaults.
sc_alloc:
    jsr bank_alloc
    bra sc_result
sc_free:
    ldd PARAM_BUFFER
    jsr bank_free
    bra sc_result
sc_map:
    ldd PARAM_BUFFER
    jsr bank_map
    bra sc_result
sc_unmap:
    jsr bank_unmap
    bra sc_result

; Function: sc_info — copy bounded physical accounting into application memory.
; Inputs: params u16 destination; Outputs: [total,reserved,free,owned] u8 each.
; Clobbers: D,X,Y,U. Errors: copy errors/no destination mutation. Stack: 20.
sc_info:
    lda #FRAME_COUNT
    sta COPY_BUFFER
    lda #3
    sta COPY_BUFFER+MLOS_INFO_RESERVED
    lda FREE_COUNT
    sta COPY_BUFFER+MLOS_INFO_FREE
    ifdef MLOS_RUNTIME
    clr COPY_BUFFER+MLOS_INFO_OWNED
    ldx #FRAME_TABLE+3*FRAME_RECORD_SIZE
sc_info_owner:
    ldd CURRENT_PID
    cmpd F_OWNER,x
    bne sc_info_next
    inc COPY_BUFFER+MLOS_INFO_OWNED
sc_info_next:
    leax FRAME_RECORD_SIZE,x
    cmpx #FRAME_TABLE+FRAME_COUNT*FRAME_RECORD_SIZE
    blo sc_info_owner
    else
    lda #FRAME_COUNT-3
    suba FREE_COUNT
    sta COPY_BUFFER+MLOS_INFO_OWNED
    endc
    ldx PARAM_BUFFER
    ldy #COPY_BUFFER
    ldd #MLOS_INFO_SIZE
    jsr copy_out
    bra sc_result

; Function: sc_write — diagnostic UART A output, counted and bounded.
; Inputs: params u16 source,u16 length<=256. Outputs: D=count/C0 or error/C1.
; Clobbers: D,X,Y,U. Errors: copy errors before output; EIO on bounded timeout.
; Side effects: already transmitted bytes persist on EIO. Stack: <=24.
sc_write:
    ldx PARAM_BUFFER
    ldd PARAM_BUFFER+MLOS_WRITE_COUNT
    ldy #COPY_BUFFER
    jsr copy_in
    bcs sc_result
    ldx #COPY_BUFFER
    ldy PARAM_BUFFER+MLOS_WRITE_COUNT
    cmpy #0
    beq sw_done
sw_loop:
    lda ,x+
    jsr ROM_PUTC
    bcs sw_failed
    leay -1,y
    bne sw_loop
sw_done:
    ldd PARAM_BUFFER+MLOS_WRITE_COUNT
    bra sc_ok
sw_failed:
    ldd #SYS_EIO
    orcc #1
    bra sc_result

; Function: sc_copy — snapshot/memmove within the owning application map.
; Inputs: params u16 source,destination,count<=256. Outputs: D=count/C0 or error.
; Clobbers: D,X,Y,U. Both ranges validate before mutation, including overlap.
; Stack: <=26. Retains no pointers; syscall defaults.
sc_copy:
    ldx PARAM_BUFFER
    ldd PARAM_BUFFER+MLOS_COPY_COUNT
    cmpd #SYS_COPY_LIMIT
    bhi sc_invalid
    jsr user_range
    bcs sc_result
    ldx PARAM_BUFFER+MLOS_COPY_DEST
    ldd PARAM_BUFFER+MLOS_COPY_COUNT
    jsr user_range
    bcs sc_result
    ldx PARAM_BUFFER
    ldd PARAM_BUFFER+MLOS_COPY_COUNT
    ldy #COPY_BUFFER
    jsr copy_in
    bcs sc_result
    ldx PARAM_BUFFER+MLOS_COPY_DEST
    ldd PARAM_BUFFER+MLOS_COPY_COUNT
    ldy #COPY_BUFFER
    jsr copy_out
    bcs sc_result
    ldd PARAM_BUFFER+MLOS_COPY_COUNT
    bra sc_ok
sc_invalid:
    ldd #SYS_EINVAL
    orcc #1
    bra sc_result

; Function: sc_entry — invoke a privileged nested SWI and test map ownership.
; Inputs: none. Outputs: D=$6309/C0. Clobbers: D. Stack: ROM bridge+native frame.
; The nested return must retain privilege for the mapping write after the SWI.
sc_entry:
    jsr ROM_NESTED_TEST
    ldd #$6309
sc_ok:
    andcc #$FE
sc_result:
    std SC_RESULT
    rts
