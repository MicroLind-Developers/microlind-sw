#ifndef MICROLIND_INTEGER_H
#define MICROLIND_INTEGER_H

/* Fixed-width integer types */
typedef signed char        int8_t;
typedef unsigned char      uint8_t;

typedef signed int         int16_t;
typedef unsigned int       uint16_t;

typedef signed long        int32_t;
typedef unsigned long      uint32_t;

/* Pointer-sized integer types (16-bit pointers on this target) */
typedef int16_t            intptr_t;
typedef uint16_t           uintptr_t;

/* Common C standard aliases */
typedef unsigned int       size_t;
typedef int                ptrdiff_t;

/* Limits for the fixed-width types */
#define INT8_MIN           (-128)
#define INT8_MAX           127
#define UINT8_MAX          255u

#define INT16_MIN          (-32768)
#define INT16_MAX          32767
#define UINT16_MAX         65535u

#define INT32_MIN          (-2147483647L - 1L)
#define INT32_MAX          2147483647L
#define UINT32_MAX         4294967295UL

#endif /* MICROLIND_INTEGER_H */
