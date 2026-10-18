#define _POSIX_C_SOURCE 200809L
#include "mlfs.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
time_t fixture_time(time_t *out) {
  time_t t = 1792195200;
  if (out)
    *out = t;
  return t;
}
clock_t fixture_clock(void) { return 0; }
int fixture_rand(void) {
  static unsigned long s = 1;
  s = (s * 1103515245 + 12345) & 0x7fffffff;
  return s >> 16;
}
static int rd(void *c, uint64_t l, uint32_t n, void *b) {
  return fseeko(c, l * 512, SEEK_SET) || fread(b, 512, n, c) != n ? -1 : 0;
}
static int wr(void *c, uint64_t l, uint32_t n, const void *b) {
  return fseeko(c, l * 512, SEEK_SET) || fwrite(b, 512, n, c) != n ? -1 : 0;
}
int main(int argc, char **argv) {
  if (argc < 4 || (argc % 2) != 0)
    return 1;
  FILE *f = fopen(argv[1], "w+b");
  if (!f || ftruncate(fileno(f), 4096 * 512))
    return 2;
  mlfs_io_t io = {f, rd, wr, 512};
  mlfs_t fs;
  if (mlfs_make_single_partition(&io, 1, 4095, 9) ||
      mlfs_mkfs_with_root(&io, 0, 16, &fs))
    return 3;
  for (int i = 2; i < argc; i += 2) {
    FILE *p = fopen(argv[i + 1], "rb");
    if (!p || fseeko(p, 0, SEEK_END))
      return 4;
    long size = ftello(p);
    if (size <= 0 || size > 65535 || fseeko(p, 0, SEEK_SET))
      return 5;
    void *b = malloc(size);
    if (!b || fread(b, 1, size, p) != (size_t)size)
      return 6;
    fclose(p);
    if (mlfs_create_empty_file(&fs, argv[i], (size + 511) / 512) ||
        mlfs_pwrite_file(&fs, argv[i], b, size, 0) != size)
      return 7;
    free(b);
  }
  return fclose(f) != 0;
}
