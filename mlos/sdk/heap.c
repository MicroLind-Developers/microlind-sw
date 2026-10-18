#include "mlos.h"
#include <cmoc.h>
/* A private two-byte requested-size prefix permits ordinary realloc without
   relocating live allocations. Kernel records retain the admitted whole span.
 */
void *malloc(u16 size) {
  int r;
  u16 pointer;
  if (!size || size > 65533)
    return 0;
  r = kword(SYS_HEAP_ALLOC, size + 2);
  if (r >= SYS_ENODEV && r < 0)
    return 0;
  pointer = (u16)r;
  mlos_put_u16((u8 *)pointer, size);
  return (void *)(pointer + 2);
}
void free(void *pointer) {
  if (pointer)
    kword(SYS_HEAP_FREE, (u16)pointer - 2);
}
void *calloc(u16 count, u16 size) {
  void *p;
  u32 total = (u32)count * size;
  if (total > 65533UL)
    return 0;
  p = malloc((u16)total);
  if (p)
    memset(p, 0, (u16)total);
  return p;
}
void *realloc(void *pointer, u16 size) {
  void *p;
  u16 old;
  if (!pointer)
    return malloc(size);
  if (!size) {
    free(pointer);
    return 0;
  }
  p = malloc(size);
  if (!p)
    return 0;
  old = get16((u8 *)pointer - 2);
  memcpy(p, pointer, old < size ? old : size);
  free(pointer);
  return p;
}
