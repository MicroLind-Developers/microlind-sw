# C to 6309 Assembler Translation Guide

This guide explains how to translate the MLFS C library to 6309 assembler for the Microlind project.

## Overview

Translating C code to 6309 assembler requires understanding:
1. **Calling conventions** - How parameters are passed
2. **Stack management** - Local variables and function frames
3. **Memory management** - Replacing malloc/free with static buffers
4. **Data structures** - Accessing struct fields
5. **Control flow** - Converting if/while/for loops

## Calling Conventions

### Parameter Passing

For 6309, we'll use a **stack-based calling convention**:

```asm
; Function call example:
; int mlfs_read_block(const mlfs_t* fs, uint32_t rel_block, void* buf)
;
; Parameters pushed right-to-left:
    ldd buf_ptr          ; Push buf (void*)
    pshs d
    ldd rel_block        ; Push rel_block (uint32_t)
    pshs d
    ldd fs_ptr           ; Push fs (mlfs_t*)
    pshs d
    jsr MLFS_READ_BLOCK
    leas 6,s              ; Clean up stack (3 words = 6 bytes)
    ; Return value in D register
```

### Return Values

- **8-bit values**: Return in A register
- **16-bit values**: Return in D register  
- **32-bit values**: Return in D (low) and X (high), or use Q register
- **Pointers**: Return in X register
- **Error codes**: Typically return in D (0 = success, negative = error)

### Register Usage Convention

| Register | Purpose | Saved by caller/callee? |
|----------|---------|------------------------|
| A, B, D  | Parameters, return values | Caller saves |
| X, Y     | Index/pointer registers | Caller saves |
| U        | Stack frame pointer (optional) | Callee saves |
| S        | Stack pointer | Callee saves |
| E, F     | Temporary values | Caller saves |
| W, V     | Temporary values | Caller saves |
| Q        | 32-bit temporary | Caller saves |
| DP       | Direct page | Callee saves |
| CC       | Condition codes | Modified by operations |

## Stack Frame Layout

```asm
; Example function with local variables:
MLFS_READ_BLOCK:
    pshs u               ; Save frame pointer
    tfr s,u              ; Set frame pointer
    leas -LOCAL_SIZE,s   ; Allocate local variables
    
    ; Stack layout:
    ; [U+LOCAL_SIZE+6] = Return address (from JSR)
    ; [U+LOCAL_SIZE+4] = Saved U
    ; [U+LOCAL_SIZE+2] = Parameter 1 (fs)
    ; [U+LOCAL_SIZE+0] = Parameter 2 (rel_block)
    ; [U-2] = Local variable 1
    ; [U-4] = Local variable 2
    ; ... (U points to top of locals)
    
    ; Function body...
    
    tfr u,s              ; Restore stack
    puls u,pc            ; Restore U and return
```

## Data Structure Access

### Struct Field Offsets

For the `mlfs_t` structure:
```c
typedef struct {
    mlfs_io_t         io;           // offset 0
    mlpt_entry_t      part;         // offset varies
    mlfs_superblock_t sb;           // offset varies
    uint32_t          bytes_per_block; // offset varies
} mlfs_t;
```

In assembler:
```asm
MLFS_T_IO              equ 0
MLFS_T_PART            equ MLFS_T_IO + sizeof(mlfs_io_t)
MLFS_T_SB              equ MLFS_T_PART + sizeof(mlpt_entry_t)
MLFS_T_BYTES_PER_BLOCK equ MLFS_T_SB + sizeof(mlfs_superblock_t)

; Access field:
    ldx fs_ptr           ; Load fs pointer
    ldd MLFS_T_BYTES_PER_BLOCK,x  ; Load bytes_per_block
```

### Packed Structures

The MLFS uses `__attribute__((packed))` structures. Calculate exact offsets:

```asm
; mlfs_extent_t (8 bytes)
MLFS_EXTENT_START      equ 0
MLFS_EXTENT_LENGTH     equ 4

; mlfs_dentry_t (128 bytes)
MLFS_DENTRY_IN_USE     equ 0
MLFS_DENTRY_FLAGS      equ 1
MLFS_DENTRY_SIZE_BYTES equ 2
MLFS_DENTRY_MTIME      equ 6
MLFS_DENTRY_CTIME      equ 10
MLFS_DENTRY_EXTENTS_USED equ 14
MLFS_DENTRY_NAME       equ 16
MLFS_DENTRY_EXTENTS    equ 64
```

## Memory Management Strategy

### Problem: No malloc/free

The C code uses `malloc()` and `free()` extensively. We need to replace this with:

1. **Static buffers** - Pre-allocated buffers for temporary operations
2. **Stack allocation** - Small buffers on the stack
3. **Fixed-size pools** - For frequently allocated structures

### Example Translation

**C code:**
```c
uint8_t* blk = (uint8_t*)malloc(fs->bytes_per_block);
if(!blk)
    return -1;
// ... use blk ...
free(blk);
```

**6309 assembler:**
```asm
; Option 1: Stack allocation (if small enough)
MLFS_READ_BLOCK:
    pshs u
    tfr s,u
    ldx fs_ptr
    ldd MLFS_T_BYTES_PER_BLOCK,x
    pshs d              ; Save block size
    leas -512,s         ; Allocate buffer on stack (max 512 bytes)
    ; Use buffer at ,s
    ; ...
    leas 512,s          ; Free buffer
    puls d,u,pc

; Option 2: Static buffer pool
MLFS_BLOCK_BUF_1       rmb 512    ; Static buffer 1
MLFS_BLOCK_BUF_2       rmb 512    ; Static buffer 2
MLFS_BLOCK_BUF_IN_USE  fcb 0      ; Which buffer is in use

MLFS_READ_BLOCK:
    ; Check if buffer available
    lda MLFS_BLOCK_BUF_IN_USE
    bne ERROR_NO_BUFFER
    inc MLFS_BLOCK_BUF_IN_USE
    ldx #MLFS_BLOCK_BUF_1
    ; Use buffer...
    clr MLFS_BLOCK_BUF_IN_USE
    rts
```

## Function Translation Examples

### Example 1: Simple Function

**C code:**
```c
static uint32_t mlfs_bitmap_bits_per_block(const mlfs_t* fs)
{
    return (fs->bytes_per_block * 8u);
}
```

**6309 assembler:**
```asm
; input:  X = fs pointer
; output: D = bits per block
; clobbers: none
MLFS_BITMAP_BITS_PER_BLOCK:
    ldd MLFS_T_BYTES_PER_BLOCK,x  ; Load bytes_per_block
    lsld                           ; * 2
    lsld                           ; * 4
    lsld                           ; * 8
    rts
```

### Example 2: Function with Parameters

**C code:**
```c
static int mlfs_read_block(const mlfs_t* fs, uint32_t rel_block, void* buf)
{
    uint32_t spb = fs->bytes_per_block / fs->io.sector_size;
    uint64_t lba = (uint64_t)fs->part.start_lba + (uint64_t)rel_block * spb;
    return fs->io.read(fs->io.ctx, lba, spb, buf);
}
```

**6309 assembler:**
```asm
; input:  [S+4] = fs pointer
;         [S+2] = rel_block (uint32_t, low word)
;         [S+0] = buf pointer
; output: D = return code (0 = success)
; clobbers: A, B, D, X, Y, E, F
MLFS_READ_BLOCK:
    pshs u
    tfr s,u
    leas -8,s              ; Local vars: spb (2), lba_low (2), lba_high (2), temp (2)
    
    ; Load fs pointer
    ldx 10,u                ; fs pointer (accounting for locals)
    
    ; Calculate spb = bytes_per_block / sector_size
    ldd MLFS_T_BYTES_PER_BLOCK,x
    ldy MLFS_T_IO + MLFS_IO_SECTOR_SIZE,x
    jsr DIV16               ; D = D / Y, result in D
    std -8,u                ; Save spb
    
    ; Calculate lba = start_lba + rel_block * spb
    ldd 8,u                 ; rel_block (low word)
    ldy -8,u                ; spb
    jsr MUL16               ; D = D * Y (result in D)
    
    ; Load start_lba (32-bit)
    ldy MLFS_T_PART + MLPT_ENTRY_START_LBA,x
    addd MLFS_T_PART + MLPT_ENTRY_START_LBA + 2,x  ; Add low word
    std -6,u                ; Save lba_low
    
    ; Handle carry for high word
    tfr y,d                 ; start_lba high
    adcb #0                 ; Add carry
    std -4,u                ; Save lba_high
    
    ; Call io.read(ctx, lba, spb, buf)
    ; Function pointer at MLFS_T_IO + MLFS_IO_READ
    ldx 10,u                ; fs pointer
    ldy MLFS_T_IO + MLFS_IO_CTX,x  ; ctx
    pshs y                  ; Push ctx
    ldd -4,u                ; lba_high
    pshs d
    ldd -6,u                ; lba_low
    pshs d
    ldd -8,u                ; spb
    pshs d
    ldd 0,u                 ; buf
    pshs d
    
    ; Call function pointer
    ldx MLFS_T_IO + MLFS_IO_READ,x
    jsr ,x                  ; Call read function
    leas 10,s               ; Clean up parameters
    
    ; Return value already in D
    tfr u,s
    puls u,pc
```

### Example 3: String Operations

**C code:**
```c
strncpy(buf[i].name, name, MLFS_MAX_NAME - 1);
buf[i].name[MLFS_MAX_NAME - 1] = '\0';
```

**6309 assembler:**
```asm
; Copy string
; X = pointer to buf[i].name
; Y = pointer to name
; B = count (MLFS_MAX_NAME - 1)
MLFS_STRNCPY:
    ldb #MLFS_MAX_NAME-1
MLFS_STRNCPY_LOOP:
    lda ,y+                ; Load from source
    sta ,x+                ; Store to dest
    decb
    bne MLFS_STRNCPY_LOOP
    clr ,x                 ; Null terminate
    rts
```

### Example 4: Bit Manipulation

**C code:**
```c
uint8_t v = blk[within >> 3];
int set = (v >> (within & 7)) & 1;
```

**6309 assembler:**
```asm
; Calculate bit position
; D = within
; X = blk pointer
; Output: A = bit value (0 or 1)
    tfr d,w                ; Save within
    lsrd                   ; >> 1
    lsrd                   ; >> 2
    lsrd                   ; >> 3 (now D = within >> 3)
    tfr d,y                ; Save index
    lda b,x                ; Load byte (B = low byte of index)
    tfr w,d                ; Restore within
    andb #7                ; within & 7
    tfr b,a                ; Shift count
    lsra                   ; Shift right by (within & 7)
    anda #1                ; Mask bit 0
    ; A now contains bit value
```

## Control Flow Translation

### If Statements

**C code:**
```c
if(!fs || !name)
    return -1;
```

**6309 assembler:**
```asm
    ldx fs_ptr
    beq ERROR              ; if(!fs)
    ldx name_ptr
    beq ERROR              ; if(!name)
    ; Continue...
ERROR:
    ldd #-1
    rts
```

### Loops

**C code:**
```c
for(uint32_t i = 0; i < len; i++) {
    // ...
}
```

**6309 assembler:**
```asm
    clrd                   ; i = 0
LOOP:
    cmpd len               ; Compare i < len
    bhs LOOP_END           ; if i >= len, exit
    ; Loop body...
    addd #1                ; i++
    bra LOOP
LOOP_END:
```

### While Loops

**C code:**
```c
while(written < count) {
    // ...
}
```

**6309 assembler:**
```asm
WHILE_LOOP:
    ldd written
    cmpd count
    bhs WHILE_END          ; if written >= count, exit
    ; Loop body...
    bra WHILE_LOOP
WHILE_END:
```

## Function Pointer Handling

The MLFS uses function pointers for I/O operations. In assembler:

```asm
; Structure with function pointer:
MLFS_IO_CTX      equ 0
MLFS_IO_READ     equ 2    ; Function pointer (2 bytes)
MLFS_IO_WRITE    equ 4    ; Function pointer (2 bytes)
MLFS_IO_SECTOR_SIZE equ 6

; Call function pointer:
    ldx fs_ptr
    ldy MLFS_IO_READ,x     ; Load function pointer
    ; Setup parameters...
    jsr ,y                 ; Call function
```

## Error Handling

**C code:**
```c
if(mlfs_read_block(fs, bno, blk) != 0) {
    free(blk);
    return -1;
}
```

**6309 assembler:**
```asm
    ; Setup parameters...
    jsr MLFS_READ_BLOCK
    tstd                   ; Test return value
    beq SUCCESS            ; if 0, success
    ; Error handling
    jsr FREE_BUFFER        ; Free buffer
    ldd #-1
    rts
SUCCESS:
    ; Continue...
```

## 32-bit Arithmetic

The 6309 has excellent 32-bit support:

**C code:**
```c
uint64_t lba = (uint64_t)fs->part.start_lba + (uint64_t)rel_block * spb;
```

**6309 assembler:**
```asm
    ; Load start_lba (32-bit) into Q
    ldx fs_ptr
    ldq MLFS_T_PART + MLPT_ENTRY_START_LBA,x
    
    ; Calculate rel_block * spb (32-bit)
    ldd rel_block
    tfr d,w                ; W = rel_block
    clrd                    ; D = 0 (high word)
    tfr q,d                 ; D = rel_block (for multiplication)
    ldy spb
    muld                    ; D = rel_block * spb (16-bit result)
    tfr d,w                 ; W = result
    clrd                    ; D = 0 (high word)
    tfr w,d                 ; D = low word
    tfr q,w                 ; W = high word (if needed)
    
    ; Add to start_lba
    addd MLFS_T_PART + MLPT_ENTRY_START_LBA + 2,x  ; Add low words
    std lba_low
    ; Handle carry...
```

## Practical Translation Strategy

### Step 1: Identify Dependencies

1. **Standard library functions**:
   - `malloc/free` → Static buffers or stack allocation
   - `memcpy` → Custom copy routine
   - `memset` → Custom clear routine
   - `strlen/strcmp` → Custom string routines
   - `time()` → System clock call or fixed value

2. **Function pointers**:
   - I/O functions → Call through function pointer
   - Need to preserve calling convention

### Step 2: Create Helper Routines

```asm
; Memory operations
MLFS_MEMCPY:              ; Copy memory block
MLFS_MEMSET:              ; Set memory block
MLFS_MEMCMP:              ; Compare memory blocks

; String operations  
MLFS_STRLEN:              ; String length
MLFS_STRCMP:              ; String compare
MLFS_STRNCPY:             ; String copy with length

; Arithmetic
MLFS_MUL32:               ; 32-bit multiply
MLFS_DIV32:               ; 32-bit divide
MLFS_ADD32:               ; 32-bit add
MLFS_SUB32:               ; 32-bit subtract
```

### Step 3: Translate Functions Bottom-Up

Start with simple utility functions, then work up to complex operations:

1. **Utilities** (`mlfs_cksum32`, `mlfs_bitmap_bits_per_block`)
2. **Low-level I/O** (`mlfs_read_block`, `mlfs_write_block`)
3. **Bitmap operations** (`mlfs_bitmap_get`, `mlfs_bitmap_set`)
4. **Directory operations** (`mlfs_dir_lookup_in_dir`)
5. **File operations** (`mlfs_create_empty_file`, `mlfs_pread_file`)

### Step 4: Memory Layout

Define static buffers for temporary operations:

```asm
    section .bss
MLFS_BLOCK_BUF_1      rmb 512    ; Block buffer 1
MLFS_BLOCK_BUF_2      rmb 512    ; Block buffer 2
MLFS_BLOCK_BUF_IN_USE fcb 0     ; Buffer allocation flag

MLFS_DIR_BUF          rmb 512    ; Directory buffer
MLFS_PATH_COMPONENTS  rmb 16*48  ; Path component storage (16 * 48 bytes)
```

## Complete Example: Simple Function

Here's a complete translation of `mlfs_bitmap_bits_per_block`:

```asm
; -----------------------------------------------------------------
; mlfs_bitmap_bits_per_block
; Calculate bits per block for bitmap
; input:  X = pointer to mlfs_t structure
; output: D = bits per block (bytes_per_block * 8)
; clobbers: D
; -----------------------------------------------------------------
    export MLFS_BITMAP_BITS_PER_BLOCK
MLFS_BITMAP_BITS_PER_BLOCK:
    ldd MLFS_T_BYTES_PER_BLOCK,x  ; Load bytes_per_block
    lsld                           ; * 2
    lsld                           ; * 4  
    lsld                           ; * 8
    rts
```

## Next Steps

1. **Create include file** with structure offsets and constants
2. **Implement helper routines** (memcpy, memset, etc.)
3. **Translate utility functions** first
4. **Build up to complex functions** incrementally
5. **Test each function** individually before integrating

## References

- See `6309_TRANSLATION_GUIDE.md` for 6309 instruction reference
- See existing BIOS code in `microlind-sw/bios/` for examples
- LWASM documentation for assembler directives

