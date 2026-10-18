/* Add deterministic inputs to a disposable copy, never to the installed CF. */
#define main formatter_main
#include "mkimage.c"
#undef main
#include <string.h>
int main(int argc, char **argv) {
  if (argc != 2 && argc != 3)
    return 1;
  FILE *f = fopen(argv[1], argc == 3 ? "rb" : "r+b");
  if (!f)
    return 2;
  mlfs_io_t io = {f, rd, wr, 512};
  mlfs_t fs;
  if (mlfs_mount(&io, 0, &fs))
    return 3;
  unsigned char data[4096];
  for (unsigned i = 0; i < sizeof(data); ++i)
    data[i] = 'A' + i % 26;
  data[126] = data[4094] = '\r';
  data[127] = data[4095] = '\n';
  if (argc == 3) {
    unsigned char actual[4097];
    const int copy = strcmp(argv[2], "verify-copy") == 0;
    if (!copy && strcmp(argv[2], "verify-redirect"))
      return 5;
    const size_t size = copy ? sizeof(data) : 6;
    const char *name = copy ? "perf-copy" : "perf-out";
    if (mlfs_pread_file(&fs, name, actual, sizeof(actual), 0) !=
            (ssize_t)size ||
        memcmp(actual, copy ? (const void *)data : (const void *)"ping\r\n",
               size))
      return 6;
    return fclose(f) != 0;
  }
  if (mlfs_create_empty_file(&fs, "perf-small", 1) ||
      mlfs_pwrite_file(&fs, "perf-small", data, 128, 0) != 128 ||
      mlfs_create_empty_file(&fs, "perf-large", 8) ||
      mlfs_pwrite_file(&fs, "perf-large", data, sizeof(data), 0) !=
          sizeof(data))
    return 4;
  return fclose(f) != 0;
}
