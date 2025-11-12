# 6309 Assembler Translation Guide

This guide explains how to translate libraries to 6309 assembler syntax for use with the Microlind project.

## Overview

The Microlind project uses **LWASM** (from LWTOOLS) with the `-3` flag to assemble 6809/6309 code. The 6309 is an enhanced version of the 6809 with additional registers and instructions.

## Assembler Setup

### Using LWASM

```bash
lwasm -3 -f ihex -o output.ihex source.asm
```

**Flags:**
- `-3` : Enable 6809/6309 mode (required for 6309 instructions)
- `-f ihex` : Output Intel HEX format
- `-I path` : Include directory for `include` directives

## Key Differences: 6809 vs 6309

### 1. Additional Registers

The 6309 adds these registers beyond the 6809:

| Register | Size | Description |
|----------|------|-------------|
| `E`, `F` | 8-bit | Additional accumulators (like A, B) |
| `W` | 16-bit | Additional word register (like D) |
| `V` | 16-bit | Transfer register |
| `Q` | 32-bit | Combined accumulator (D + W) |
| `MD` | 8-bit | Mode register (controls native/emulation mode) |

### 2. Native Mode Initialization

**Always initialize native mode at startup:**

```asm
    ; Enable 6309 native mode
    ldmd #$01
```

This enables all 6309-specific instructions. Without this, the CPU runs in 6809 emulation mode.

## Translation Patterns

### Pattern 1: Register Initialization

**6809:**
```asm
    clra
    clrb
    tfr d,x
    tfr d,y
    tfr d,u
```

**6309 (optimized):**
```asm
    ldq #$00000000    ; Clear Q (D + W)
    tfr a,dp          ; Clear DP from A (already 0)
    tfr d,x           ; Clear X
    tfr d,y           ; Clear Y
    tfr d,u           ; Clear U
    tfr d,v           ; Clear V (6309-specific)
```

### Pattern 2: Using Additional Accumulators

**6809 (using A/B only):**
```asm
    lda value1
    sta temp1
    lda value2
    sta temp2
    lda temp1
    adda temp2
```

**6309 (using E/F):**
```asm
    lde value1        ; Load into E
    ldf value2        ; Load into F
    tfr e,a           ; Move E to A
    adda f            ; Add F to A
```

### Pattern 3: 32-bit Operations

**6809 (manual 32-bit):**
```asm
    ldd value_low
    std result_low
    ldd value_high
    std result_high
```

**6309 (using Q register):**
```asm
    ldq #$12345678    ; Load 32-bit value
    stq result        ; Store 32-bit value
```

### Pattern 4: Temporary Storage

**6809:**
```asm
    pshs a            ; Save A
    lda other_value
    ; ... use A ...
    puls a            ; Restore A
```

**6309:**
```asm
    tfr a,e           ; Save A to E (faster than stack)
    lda other_value
    ; ... use A ...
    tfr e,a           ; Restore A from E
```

## 6309-Specific Instructions

### Load/Store Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `lde #$nn` | Load E immediate | `lde #$42` |
| `ldf #$nn` | Load F immediate | `ldf #$FF` |
| `ldw #$nnnn` | Load W immediate | `ldw #$1234` |
| `ldq #$nnnnnnnn` | Load Q (32-bit) | `ldq #$12345678` |
| `ldmd #$nn` | Load mode register | `ldmd #$01` |
| `ste addr` | Store E | `ste $1000` |
| `stf addr` | Store F | `stf $1001` |
| `stw addr` | Store W | `stw $1002` |
| `stq addr` | Store Q (32-bit) | `stq $1004` |

### Arithmetic Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `adde #$nn` | Add to E | `adde #$10` |
| `addf #$nn` | Add to F | `addf #$20` |
| `addw #$nnnn` | Add to W | `addw #$0100` |
| `adcd #$nnnn` | Add with carry to D | `adcd #$1234` |
| `adcr r` | Add with carry to register | `adcr x` |
| `sube #$nn` | Subtract from E | `sube #$05` |
| `subf #$nn` | Subtract from F | `subf #$0A` |
| `subw #$nnnn` | Subtract from W | `subw #$0100` |
| `sbcd #$nnnn` | Subtract with borrow from D | `sbcd #$1234` |
| `sbcr r` | Subtract with borrow from register | `sbcr y` |

### Logical Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `ande #$nn` | AND E | `ande #$F0` |
| `andf #$nn` | AND F | `andf #$0F` |
| `andd #$nnnn` | AND D | `andd #$FF00` |
| `andr r` | AND register | `andr x` |
| `ore #$nn` | OR E | `ore #$80` |
| `orf #$nn` | OR F | `orf #$40` |
| `ord #$nnnn` | OR D | `ord #$00FF` |
| `orr r` | OR register | `orr y` |
| `eore #$nn` | XOR E | `eore #$FF` |
| `eorf #$nn` | XOR F | `eorf #$AA` |
| `eord #$nnnn` | XOR D | `eord #$FFFF` |
| `eorr r` | XOR register | `eorr u` |

### Comparison Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `cmpe #$nn` | Compare E | `cmpe #$42` |
| `cmpf #$nn` | Compare F | `cmpf #$FF` |
| `cmpw #$nnnn` | Compare W | `cmpw #$1234` |
| `cmpd #$nnnn` | Compare D | `cmpd #$5678` |
| `cmpr r` | Compare register | `cmpr x` |

### Shift/Rotate Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `lsle` | Logical shift left E | `lsle` |
| `lsre` | Logical shift right E | `lsre` |
| `role` | Rotate left E | `role` |
| `rore` | Rotate right E | `rore` |
| `asre` | Arithmetic shift right E | `asre` |
| `asle` | Arithmetic shift left E | `asle` |
| `lsld` | Logical shift left D | `lsld` |
| `lsrd` | Logical shift right D | `lsrd` |
| `rold` | Rotate left D | `rold` |
| `rord` | Rotate right D | `rord` |
| `asrd` | Arithmetic shift right D | `asrd` |
| `lsrw` | Logical shift right W | `lsrw` |
| `rolw` | Rotate left W | `rolw` |
| `rorw` | Rotate right W | `rorw` |

### Increment/Decrement Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `ince` | Increment E | `ince` |
| `incf` | Increment F | `incf` |
| `incw` | Increment W | `incw` |
| `incd` | Increment D | `incd` |
| `dece` | Decrement E | `dece` |
| `decf` | Decrement F | `decf` |
| `decw` | Decrement W | `decw` |
| `decd` | Decrement D | `decd` |

### Clear Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `clre` | Clear E | `clre` |
| `clrf` | Clear F | `clrf` |
| `clrw` | Clear W | `clrw` |
| `clrd` | Clear D | `clrd` |

### Complement/Negate Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `come` | Complement E | `come` |
| `comf` | Complement F | `comf` |
| `comd` | Complement D | `comd` |
| `comw` | Complement W | `comw` |
| `nege` | Negate E | `nege` |
| `negf` | Negate F | `negf` |
| `negd` | Negate D | `negd` |

### Test Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `tste` | Test E | `tste` |
| `tstf` | Test F | `tstf` |
| `tstw` | Test W | `tstw` |
| `tstd` | Test D | `tstd` |
| `bitd #$nnnn` | Bit test D | `bitd #$8000` |
| `bitmd #$nn` | Bit test MD | `bitmd #$01` |

### Transfer Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `tfr e,a` | Transfer E to A | `tfr e,a` |
| `tfr a,e` | Transfer A to E | `tfr a,e` |
| `tfr f,b` | Transfer F to B | `tfr f,b` |
| `tfr w,d` | Transfer W to D | `tfr w,d` |
| `tfr d,v` | Transfer D to V | `tfr d,v` |
| `tfr q,d` | Transfer Q low to D | `tfr q,d` |
| `tfr d,q` | Transfer D to Q low | `tfr d,q` |

### Special Instructions

| Instruction | Description | Example |
|-------------|-------------|---------|
| `sexw` | Sign extend W to D | `sexw` |
| `divd` | Divide D by W | `divd` |
| `divq` | Divide Q by W | `divq` |
| `muld` | Multiply D by W | `muld` |
| `ldbt #$nn` | Load bit test mask | `ldbt #$80` |
| `stbt addr` | Store bit test result | `stbt $1000` |
| `oim #$nn,addr` | OR immediate to memory | `oim #$80,$1000` |
| `aim #$nn,addr` | AND immediate to memory | `aim #$7F,$1000` |
| `eim #$nn,addr` | XOR immediate to memory | `eim #$FF,$1000` |
| `tim #$nn,addr` | Test immediate to memory | `tim #$80,$1000` |

## Common Translation Examples

### Example 1: Clearing Multiple Registers

**6809:**
```asm
CLEAR_REGS:
    clra
    clrb
    tfr d,x
    tfr d,y
    tfr d,u
    rts
```

**6309:**
```asm
CLEAR_REGS:
    ldq #$00000000    ; Clear Q (D + W)
    tfr a,dp          ; Clear DP
    tfr d,x           ; Clear X
    tfr d,y           ; Clear Y
    tfr d,u           ; Clear U
    tfr d,v           ; Clear V
    clre              ; Clear E
    clrf              ; Clear F
    rts
```

### Example 2: Temporary Value Storage

**6809:**
```asm
    pshs a            ; Save A
    lda #$42
    sta $1000
    puls a            ; Restore A
```

**6309:**
```asm
    tfr a,e           ; Save A to E (faster, no stack)
    lda #$42
    sta $1000
    tfr e,a           ; Restore A from E
```

### Example 3: 32-bit Counter

**6809:**
```asm
    ldd counter_low
    addd #1
    std counter_low
    bcc done
    ldd counter_high
    addd #1
    std counter_high
done:
```

**6309:**
```asm
    ldq counter       ; Load 32-bit counter
    addw #1           ; Add 1 to W (low word)
    bcc done
    incd               ; Increment D (high word)
done:
    stq counter       ; Store 32-bit counter
```

### Example 4: Bit Manipulation

**6809:**
```asm
    lda $1000
    ora #$80
    sta $1000
```

**6309:**
```asm
    oim #$80,$1000    ; OR immediate to memory (single instruction)
```

## Assembly Syntax (LWASM)

### Directives

```asm
    org $E000          ; Set origin
    include "file.inc" ; Include file
    export SYMBOL      ; Export symbol
    fcc "string"       ; Form constant character
    fcb $01,$02        ; Form constant byte
    fdb $1234          ; Form double byte (word)
    equ $1000          ; Equate symbol
```

### Conditional Assembly

```asm
    IFNDEF SYMBOL
        ; code if SYMBOL not defined
    ENDC
    
    IFDEF SYMBOL
        ; code if SYMBOL defined
    ENDC
```

## Best Practices

1. **Always initialize native mode** at startup with `ldmd #$01`

2. **Use E/F for temporary values** instead of stack operations when possible

3. **Use Q for 32-bit operations** instead of manual 16-bit handling

4. **Use V register** for intermediate calculations

5. **Use immediate memory operations** (`oim`, `aim`, `eim`, `tim`) when possible

6. **Document register usage** in comments:
   ```asm
   ; input:  A = value
   ; output: D = result
   ; clobbers: E, F
   ```

7. **Test in emulation mode first** if porting from 6809, then optimize with 6309 features

## Building with CMake

The project includes CMake support. Example:

```cmake
# Custom command to build with lwasm
add_custom_command(
    OUTPUT ${BUILD_DIR}/output.ihex
    COMMAND lwasm -3 -f ihex -I ${INCLUDE_DIR} -o ${BUILD_DIR}/output.ihex ${SOURCE_FILES}
    DEPENDS ${SOURCE_FILES}
    COMMENT "Building with lwasm"
)
```

## References

- [LWTOOLS Documentation](http://lwtools.projects.l-w.ca/)
- [6309 Instruction Set](https://en.wikipedia.org/wiki/Motorola_6809#6309)
- Microlind BIOS code examples in `microlind-sw/bios/`

## Example: Complete Function Translation

**6809 version:**
```asm
MULTIPLY_BY_10:
    pshs d
    ldd 4,s           ; Get argument from stack
    lslb               ; Multiply by 2
    rola
    std temp
    lslb               ; Multiply by 4
    rola
    addd temp          ; Add (x*2) + (x*4) = x*6
    lslb               ; Multiply by 8
    rola
    addd temp          ; Add (x*8) + (x*2) = x*10
    std 4,s            ; Store result
    puls d,pc
```

**6309 version:**
```asm
MULTIPLY_BY_10:
    tfr d,w           ; Save D to W
    ldd 4,s            ; Get argument
    lsld               ; x*2
    tfr d,v            ; Save to V
    lsld               ; x*4
    addd v             ; x*6
    tfr v,w            ; x*2 to W
    lsld               ; x*8
    addd w             ; x*10
    std 4,s            ; Store result
    tfr w,d            ; Restore D
    rts
```

This guide should help you translate libraries to 6309 assembler effectively!

