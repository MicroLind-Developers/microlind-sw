MEMORY_BITMAP EQU $FE00
MEMORY_SIZE  EQU $0200

; -----------------------------------------------------------------
; Memory Management
; -----------------------------------------------------------------
; The memory manager is responsible for allocating and freeing memory.
; The memory is allocated in blocks of 256 bytes and represented by a bit in the bitmap.
; When the system requests memory, the mapper will check the bitmap for a free block.
; If the maximum number of pages it to be represented by the bitmap, the bitmap 
; will need to be up to 2048 bytes. (4MB / 256 bytes pages => 4 * 1024 * 1024 / 256 = 16384 and 8 bits per byte => 16384 / 8 = 2048 bytes)
; Eg. 256 bytes bitmap per memory chip in the system (512kB memory chips)
;
; So after "auto detection" the memory manager will be initialized and bitmap allocated, depending on available memory.
; -----------------------------------------------------------------

; -----------------------------------------------------------------
; MEM_MANAGER_INIT
; -----------------------------------------------------------------






; -----------------------------------------------------------------
; MEM_MANAGER_ALLOCATE
; input:            A = Number of pages to allocate
; output:           X = address of the allocated block
; clobbers:         X
; Allocate one page (256 bytes at $FE00)
; -----------------------------------------------------------------
MEM_MANAGER_ALLOCATE:
        LDA #MEMORY_BITMAP
        

; -----------------------------------------------------------------