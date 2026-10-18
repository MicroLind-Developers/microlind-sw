#include "mlos.h"
#include <cmoc.h>
static void logtext(const char *s) {
  u8 p[4];
  mlos_put_u16(p, (u16)s);
  mlos_put_u16(p + 2, strlen(s));
  mlos_call(SYS_LOG, p);
}
int main(void) {
  int pid, r, i;
  u16 tx, rx;
  u8 fs_state[8];
  logtext("MLOS init\r\n");
  pid = kspawn("filesystem.mlx", 0, 0, 0);
  if (pid < 0) {
    logtext("filesystem spawn failed\r\n");
    kwrite("filesystem unavailable; diagnostics only\r\n", 40);
  }
  for (i = 0; i < 5000; i++) {
    r = kconnect("fs", &tx, &rx);
    if (!r) {
      kclose(tx);
      kclose(rx);
      break;
    }
    kword(SYS_FS_STATE, (u16)fs_state);
    if (fs_state[2])
      break;
    ksleep(1);
  }
  if (i == 5000) {
    logtext("filesystem not ready\r\n");
    kwrite("filesystem not ready; diagnostics only\r\n", 38);
  }
  for (i = 0; i < 2; i++) {
    pid = kspawn("shell.mlx", 1, 0, 0);
    if (pid < 0) {
      logtext("shell spawn failed\r\n");
      ksleep(100);
      continue;
    }
    kwait((u16)pid);
    logtext("shell restarted\r\n");
    ksleep(10);
  }
  logtext("shell failed twice; reset\r\n");
  kwrite("shell failed twice; reset\r\n", 27);
  for (;;)
    ksleep(100);
  return 0;
}
