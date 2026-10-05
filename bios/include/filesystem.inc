; FSR1 register ABI. All memory structures are big-endian; calls are not C ABI.
    ifndef FILESYSTEM_INC
FILESYSTEM_INC equ 1
FS_API_BASE       equ $4010
FS_API_VERSION    equ 1
FS_API_COUNT      equ 11
FS_API_MOUNT      equ FS_API_BASE+8+0*3 ; B=partition index 0..15
FS_API_STAT       equ FS_API_BASE+8+1*3 ; X=request, buffer >=128 bytes
FS_API_LIST       equ FS_API_BASE+8+2*3 ; X=request, offset=directory slot cursor
FS_API_READ       equ FS_API_BASE+8+3*3 ; X=request, offset=file byte position
FS_API_STATS      equ FS_API_BASE+8+4*3 ; X=8-byte used/free block result
FS_API_WRITE      equ FS_API_BASE+8+5*3 ; X=request, buffer=source, offset=byte position
FS_API_CREATE     equ FS_API_BASE+8+6*3 ; X=request, offset=initial blocks (0 means 1)
FS_API_UNLINK     equ FS_API_BASE+8+7*3 ; X=request, file only
FS_API_MKDIR      equ FS_API_BASE+8+8*3 ; X=request, offset=initial blocks (0 means 1)
FS_API_RMDIR      equ FS_API_BASE+8+9*3 ; X=request, empty directory only
FS_API_RENAME     equ FS_API_BASE+8+10*3 ; X=request, buffer=destination path

FS_REQ_PATH       equ 0               ; NUL-terminated root-relative path pointer
FS_REQ_BUFFER     equ 2               ; Destination pointer
FS_REQ_COUNT      equ 4               ; Buffer capacity / requested bytes
FS_REQ_OFFSET     equ 6               ; 32-bit byte offset or list cursor
FS_REQ_DONE       equ 10              ; Actual bytes / list entries (0 or 1)
FS_REQ_SIZE       equ 12

; Public services preserve X,Y,U,DP; clobber D,W,CC. D=0/C clear on success;
; D=negative FS_E*/C set on failure. Read errors retain the partial byte count.
FS_EIO           equ -1
FS_EINVAL        equ -2
FS_ENOMOUNT      equ -3
FS_ECORRUPT      equ -4
FS_ENOENT        equ -5
FS_ENOTDIR       equ -6
FS_EISDIR        equ -7
FS_EUNSUPPORTED  equ -8
FS_EABI          equ -9
FS_ENAMETOOLONG  equ -10
FS_ERANGE        equ -11
FS_EEXIST        equ -12
FS_ENOSPC        equ -13
FS_ENOTEMPTY     equ -14
    endc
