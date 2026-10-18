#include "mlos.h"
#include <cmoc.h>
static u8 zero[32];
int main(int argc, char **argv) {
  u16 i;
  u8 *p;
  if (argc != 3 || strcmp(argv[1], "alpha") || strcmp(argv[2], "beta gamma") ||
      argv[3])
    return 41;
  for (i = 0; i < 32; i++)
    if (zero[i])
      return 42;
  p = (u8 *)malloc(20000);
  if (!p)
    return 43;
  for (i = 0; i < 20000; i++)
    p[i] = (u8)(i ^ 0xA5);
  ksleep(12);
  for (i = 0; i < 20000; i++)
    if (p[i] != (u8)(i ^ 0xA5))
      return 44;
  free(p);
  kwrite("CMOC argv/BSS/heap PASS\r\n", 25);
  return 0;
}
