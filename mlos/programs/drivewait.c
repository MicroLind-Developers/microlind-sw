#include "fs.h"
int main(void) {
  u8 entry[128];
  int i;
  if (mlos_call(SYS_GETC, 0) != SYS_EOWNER)
    return 66;
  if (mlos_call(SYS_TTY_WAIT, 0) != SYS_EOWNER)
    return 67;
  for (i = 0; i < 10; i++)
    if (fs_stat("/disk1/seed", entry))
      return 65;
  return 0;
}
