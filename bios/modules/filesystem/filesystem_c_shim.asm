; Linkable CMOC bridge. First stack argument follows the two-byte return PC.
    include "../../include/filesystem.inc"
    section code
    export _fs_mount,_fs_stat,_fs_list,_fs_read,_fs_stats
    export _fs_write,_fs_create,_fs_unlink,_fs_mkdir,_fs_rmdir,_fs_rename

; -------------------------------------------------------
;  Bridge the CMOC partition argument to the register-ABI mount service.
; -------------------------------------------------------
; input:            [S+2]=16-bit partition index; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; indices above 255 return FS_EINVAL
; clobbers:         D, W, CC; X,Y,U,DP preserved
; -------------------------------------------------------
_fs_mount:
    lda 2,s
    bne F_C_BAD_PARTITION
    ldb 3,s
    jmp FS_API_MOUNT

; -------------------------------------------------------
;  Return invalid argument from the CMOC mount wrapper for a nonzero high byte.
; -------------------------------------------------------
; input:            S points to the CMOC return address
; output:           D=FS_EINVAL; C set
; clobbers:         D, CC
; -------------------------------------------------------
F_C_BAD_PARTITION:
    ldd #FS_EINVAL
    orcc #1
    rts

; -------------------------------------------------------
;  Bridge a CMOC pointer argument to the register-ABI stat service.
; -------------------------------------------------------
; input:            [S+2]=FsRequest pointer; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; request.done=128 on success
; clobbers:         D, W, X, CC; Y,U,DP preserved
; -------------------------------------------------------
_fs_stat:
    ldx 2,s
    jmp FS_API_STAT

; -------------------------------------------------------
;  Bridge a CMOC pointer argument to the register-ABI directory enumeration service.
; -------------------------------------------------------
; input:            [S+2]=FsRequest pointer; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; request.done=0/1 and offset=next slot
; clobbers:         D, W, X, CC; Y,U,DP preserved
; -------------------------------------------------------
_fs_list:
    ldx 2,s
    jmp FS_API_LIST

; -------------------------------------------------------
;  Bridge a CMOC pointer argument to the register-ABI file read service.
; -------------------------------------------------------
; input:            [S+2]=FsRequest pointer; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; request.done=actual read count; offset unchanged
; clobbers:         D, W, X, CC; Y,U,DP preserved
; -------------------------------------------------------
_fs_read:
    ldx 2,s
    jmp FS_API_READ

; -------------------------------------------------------
;  Bridge a CMOC pointer argument to the register-ABI allocation statistics service.
; -------------------------------------------------------
; input:            [S+2]=FsStats pointer; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; used/free 32-bit block counts written
; clobbers:         D, W, X, CC; Y,U,DP preserved
; -------------------------------------------------------
_fs_stats:
    ldx 2,s
    jmp FS_API_STATS

; -------------------------------------------------------
;  Bridge a CMOC pointer argument to the register-ABI file write service.
; -------------------------------------------------------
; input:            [S+2]=FsRequest pointer; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; request.done=confirmed write count; offset unchanged
; clobbers:         D, W, X, CC; Y,U,DP preserved
; -------------------------------------------------------
_fs_write:
    ldx 2,s
    jmp FS_API_WRITE

; -------------------------------------------------------
;  Bridge a CMOC pointer argument to the register-ABI file creation service.
; -------------------------------------------------------
; input:            [S+2]=FsRequest pointer; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; offset specifies initial blocks; request.done=0
; clobbers:         D, W, X, CC; Y,U,DP preserved
; -------------------------------------------------------
_fs_create:
    ldx 2,s
    jmp FS_API_CREATE

; -------------------------------------------------------
;  Bridge a CMOC pointer argument to the register-ABI file removal service.
; -------------------------------------------------------
; input:            [S+2]=FsRequest pointer; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; path selects file; request.done=0
; clobbers:         D, W, X, CC; Y,U,DP preserved
; -------------------------------------------------------
_fs_unlink:
    ldx 2,s
    jmp FS_API_UNLINK

; -------------------------------------------------------
;  Bridge a CMOC pointer argument to the register-ABI directory creation service.
; -------------------------------------------------------
; input:            [S+2]=FsRequest pointer; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; offset specifies initial blocks; request.done=0
; clobbers:         D, W, X, CC; Y,U,DP preserved
; -------------------------------------------------------
_fs_mkdir:
    ldx 2,s
    jmp FS_API_MKDIR

; -------------------------------------------------------
;  Bridge a CMOC pointer argument to the register-ABI empty-directory removal service.
; -------------------------------------------------------
; input:            [S+2]=FsRequest pointer; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; path selects directory; request.done=0
; clobbers:         D, W, X, CC; Y,U,DP preserved
; -------------------------------------------------------
_fs_rmdir:
    ldx 2,s
    jmp FS_API_RMDIR

; -------------------------------------------------------
;  Bridge a CMOC pointer argument to the register-ABI rename/move service.
; -------------------------------------------------------
; input:            [S+2]=FsRequest pointer; S points to the CMOC return address
; output:           D=0/C clear on success; D=negative FS_E*/C set on failure; CMOC return value
;                   in D; path=source, buffer=destination; request.done=0
; clobbers:         D, W, X, CC; Y,U,DP preserved
; -------------------------------------------------------
_fs_rename:
    ldx 2,s
    jmp FS_API_RENAME
    endsection
