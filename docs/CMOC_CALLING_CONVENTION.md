# CMOC Stack Frame Format for C Functions on 6809/6309

This note summarizes how CMOC formats stack frames when calling C functions compiled for the Motorola 6809 / Hitachi 6309 family.

CMOC's 6309 target is effectively the same calling convention as 6809. CMOC may allow 6309 instructions in inline assembly, but normal generated C code follows the 6809-style ABI.

---

## 1. Basic Calling Convention

CMOC uses the hardware **S stack** for function calls.

For normal C functions, CMOC uses **U as a frame pointer**.

A typical function prologue is:

```asm
        PSHS    U
        LEAU    ,S
```

A typical epilogue is:

```asm
        LEAS    ,U
        PULS    U,PC
```

After the prologue, `U` points to the saved previous frame pointer.

---

## 2. Normal Stack Frame Layout

For a function such as:

```c
int f(int m, int n)
{
    int local;
    ...
}
```

the stack frame after the prologue looks like this:

```text
higher addresses
────────────────────────
  n                  6,U     second argument
  m                  4,U     first argument
  return address     2,U
  saved old U        0,U     U points here
────────────────────────
  local variables   -1,U
                    -2,U
                    ...
lower addresses
```

The key offsets are:

```text
0,U     saved previous U
2,U     return address
4,U     first C argument
6,U     second C argument
8,U     third C argument
...
```

Local variables are allocated below `U`, using negative offsets.

---

## 3. Argument Order

CMOC pushes function arguments in reverse order, as is common for C calling conventions.

For this call:

```c
f(m, n);
```

the caller conceptually does:

```asm
        ; push n first
        ; push m second
        JSR     f
        ; caller cleans up the arguments afterwards
```

At function entry, before the normal CMOC prologue:

```text
0,S     return address
2,S     m
4,S     n
```

Then the callee does:

```asm
        PSHS    U
        LEAU    ,S
```

After that:

```text
0,U     saved old U
2,U     return address
4,U     m
6,U     n
```

So for a normal framed C function, the first argument is at `4,U`.

---

## 4. Byte Arguments

Byte-sized C arguments are promoted before being passed.

For example:

```c
void f(char c, unsigned char b);
```

Even though `char` and `unsigned char` are byte-sized types, they are passed as 16-bit promoted values.

So the stack layout is:

```text
4,U     c as 16-bit promoted int
6,U     b as 16-bit promoted unsigned int
```

This means that each byte argument still occupies two bytes in the argument area.

CMOC also uses big-endian byte ordering on the stack, matching the 6809/6309 architecture.

---

## 5. Return Values

CMOC return values are generally handled like this:

| C return type | Returned in |
|---|---|
| `char`, `unsigned char` | `B` |
| 16-bit value, pointer, `int`, `unsigned int` | `D` |
| `struct`, `long`, `float`, `double` | Hidden return buffer pointer |

For larger return types, the caller passes a hidden first argument containing the address where the callee should store the result.

For example:

```c
long f(int x);
```

is effectively handled more like:

```c
void f_hidden(long *return_storage, int x);
```

from the calling-convention point of view.

---

## 6. Register Preservation

CMOC-generated functions preserve:

```text
U, Y, S, DP
```

They may freely modify:

```text
A, B, X, CC
```

For hand-written assembly callable from C, a safe rule is:

```text
May modify:      A, B, X, CC
Should preserve: U, Y, S, DP
Return byte in:  B
Return word in:  D
```

Preserving `Y` is especially important under OS-9, where CMOC uses it as the data-section register. It is also a good habit on non-OS-9 targets because the optimizer may use `Y`.

---

## 7. Normal C Function Example

C function:

```c
int add3(int a, int b, int c)
{
    int tmp;
    tmp = a + b;
    return tmp + c;
}
```

Typical CMOC-style frame:

```text
0,U     saved U
2,U     return address
4,U     a
6,U     b
8,U     c

-1,U
-2,U    tmp
```

A hand-written approximation could look like this:

```asm
_add3:
        PSHS    U
        LEAU    ,S
        LEAS    -2,S        ; reserve 2 bytes for tmp

        LDD     4,U         ; a
        ADDD    6,U         ; + b
        STD     -2,U        ; tmp

        LDD     -2,U
        ADDD    8,U         ; + c

        LEAS    ,U
        PULS    U,PC
```

---

## 8. Assembly-Only CMOC Functions

If a function is declared with CMOC's `asm` modifier, CMOC does not generate the normal `U`-based stack frame.

Example:

```c
asm int f(int m, int n)
{
    asm
    {
        ldd     2,s     // load m
        addd    4,s     // add n, leave return value in D
    }
}
```

In this case, the stack frame is:

```text
0,S     return address
2,S     m
4,S     n
```

There is no:

```asm
        PSHS    U
        LEAU    ,S
```

So the first argument is at `2,S`, not `4,U`.

---

## 9. Normal C Function vs. Assembly-Only Function

| Function kind | First argument |
|---|---:|
| Normal C function with `U` frame | `4,U` |
| `asm`-only function without frame | `2,S` |

This is one of the most important distinctions when mixing CMOC C and hand-written assembly.

---

## 10. Practical Template for Hand-Written Assembly

For a normal assembly function callable from CMOC C:

```asm
_myfunc:
        PSHS    U
        LEAU    ,S

        ; arg1 = 4,U
        ; arg2 = 6,U
        ; arg3 = 8,U

        ; return value:
        ;   byte in B
        ;   word in D

        LEAS    ,U
        PULS    U,PC
```

For a pure `asm` CMOC function without a generated frame:

```asm
        ; arg1 = 2,S
        ; arg2 = 4,S
        ; arg3 = 6,S

        ; return byte in B
        ; return word in D
```

The framed version is easier when local variables or stable argument offsets are useful.

The assembly-only version is smaller and faster, but you must manually follow CMOC's calling convention.

---

## 11. Example

For:
```C
float getFloat(char* data, char size);
```
CMOC treats it internally almost like:
```C
void getFloat(float* hidden_return_address, char* data, int size);
```
because float is not returned in D. CMOC says struct, long, float, and double return values are written to a caller-provided address passed as the function’s first hidden parameter. It also promotes char arguments to 16-bit int, and normal functions use U as frame pointer after PSHS U / LEAU ,S.

### After entering getFloat

Assuming a normal CMOC-generated function, after this prologue:
```asm
_getFloat:
        PSHS    U
        LEAU    ,S
```
the stack frame is:
```
higher addresses
────────────────────────────────────────────
  size, promoted char -> int       8,U   2 bytes
  data pointer                     6,U   2 bytes
  hidden float return pointer      4,U   2 bytes
  return address                   2,U   2 bytes
  saved old U                      0,U   2 bytes   ← U points here
────────────────────────────────────────────
  local variables                 -1,U
                                  -2,U
                                  ...
lower addresses
```

So the important offsets are:
```asm
4,U     pointer to where the float result must be stored
6,U     data
8,U     size, promoted from char to int
```
### Before the prologue

At the instant the function is entered by JSR, but before PSHS U, the stack is:
```
0,S     return address
2,S     hidden float return pointer
4,S     data pointer
6,S     size promoted to 16-bit int
```
Then PSHS U moves S down by 2 bytes and saves the old U. After LEAU ,S, U becomes the stable frame pointer.

### Example caller-side idea

A call like:
```C
float result;
result = getFloat(ptr, 4);
```
is conceptually something like:
```asm
        ; reserve/use storage for the returned float somewhere
        ; push arguments in reverse order

        LDD     #4              ; size, char promoted to int
        PSHS    D

        LDD     #ptr            ; data pointer
        PSHS    D

        LDD     #result         ; hidden return pointer
        PSHS    D

        JSR     _getFloat

        LEAS    6,S             ; caller removes 3 words of arguments
```
The callee then writes the float bytes to the address found at 4,U.

### Very important float size note

The hidden return pointer must point to enough storage for CMOC’s float. With CoCo/Dragon Basic floating point, CMOC uses the Basic-style 40-bit float format; with --mc6839, it uses a 32-bit float format. CMOC’s manual also notes that floating-point support is limited to supported targets/environments, including CoCo Extended Color Basic, Dragon Basic, and --mc6839.

So the hidden pointer at 4,U points to:
```
5 bytes  if using CoCo/Dragon Basic float format
4 bytes  if using --mc6839 float format
```

### Callee-side assembly sketch

Something like this:
```asm
_getFloat:
        PSHS    U
        LEAU    ,S

        ; 4,U = hidden pointer to return float storage
        ; 6,U = char* data
        ; 8,U = promoted char size as 16-bit int

        LDX     4,U     ; X = destination for returned float
        LDY     6,U     ; Y = data pointer
        LDD     8,U     ; D = size as promoted int

        ; Convert bytes at Y to a CMOC float somehow.
        ; Store resulting float to address in X.

        LEAS    ,U
        PULS    U,PC
```
One small design note: because char size is signed in CMOC, values above 127 can become negative when promoted. For a byte count, this is usually safer:
```C
float getFloat(char* data, unsigned char size);
```
Then size is still passed as a 16-bit word, but promoted to unsigned int instead of signed int.

## 12. Quick Reference

### Normal framed function

```text
0,U     saved U
2,U     return address
4,U     arg1
6,U     arg2
8,U     arg3
...
-1,U    local storage
-2,U    local storage
...
```

### Assembly-only function

```text
0,S     return address
2,S     arg1
4,S     arg2
6,S     arg3
...
```

### Return registers

```text
B       8-bit return value
D       16-bit return value or pointer
```

### Preserve

```text
U, Y, S, DP
```

### May clobber

```text
A, B, X, CC
```