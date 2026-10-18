/* Common small command image; argv[0] selects the installed command. */
#include "fs.h"
#include "terminal.h"
#include <cmoc.h>
static u8 buffer[256], record[128], procs[64];
static int output(const void *p, u16 n) {
  int r;
  while (n) {
    r = kwrite(p, n);
    if (r < 0)
      return r;
    if (!r)
      return SYS_EIO;
    p = (const u8 *)p + r;
    n -= r;
  }
  return 0;
}
static void text(const char *s) { output(s, strlen(s)); }
static void number(int n) {
  char b[24];
  sprintf(b, "%d", n);
  text(b);
}
int main(void) {
  int argc = mlos_argc(), r = 0, i, in = -1;
  char **argv = mlos_argv();
  char *input = 0;
  u32 cursor;
  char cwd[64];
  if (!argc)
    return 126;
  if (mlos_call(SYS_STANDARD, 0))
    return 126;
  if (0) { }
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_ECHO)
  else if (!strcmp(argv[0], "echo")) {
    for (i = 1; i < argc; i++) {
      if (i > 1)
        text(" ");
      text(argv[i]);
    }
    text("\r\n");
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_PWD)
  else if (!strcmp(argv[0], "pwd")) {
    r = fs_getcwd(cwd);
    if (!r) {
      text(cwd);
      text("\r\n");
    }
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_LS)
  else if (!strcmp(argv[0], "ls")) {
    cursor = 0;
    while ((r = fs_list(argc > 1 ? (const char *)argv[1] : ".", &cursor,
                        record)) > 0) {
      record[63] = 0;
      text((char *)record + 16);
      text((record[1] & 1) ? "/\r\n" : "\r\n");
    }
    if (r > 0)
      r = 0;
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_CAT)
  else if (!strcmp(argv[0], "cat")) {
    if (!input && argc > 1)
      input = argv[1];
    if (!input && std_infile) {
      while ((r = kread(0, buffer, 256)) > 0) {
        r = output(buffer, (u16)r);
        if (r)
          break;
      }
    } else if (!input)
      r = SYS_EINVAL;
    else {
      in = fs_open(input, 0);
      if (kerror(in))
        r = in;
      else
        while ((r = fs_read((u16)in, buffer, 256)) > 0) {
          r = output(buffer, (u16)r);
          if (r)
            break;
        }
      if (!kerror(in))
        fs_close((u16)in);
    }
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_CP)
  else if (!strcmp(argv[0], "cp")) {
    if (argc != 3)
      r = SYS_EINVAL;
    else {
      in = fs_open(argv[1], 0);
      if (kerror(in))
        r = in;
      else {
        int dest =
            fs_open(argv[2], F_WRITE_FLAG | F_CREATE_FLAG | F_TRUNCATE_FLAG);
        if (kerror(dest))
          r = dest;
        else {
          while ((r = fs_read((u16)in, buffer, 256)) > 0) {
            int n = fs_write((u16)dest, buffer, (u16)r);
            if (n != r) {
              r = n < 0 ? n : SYS_EIO;
              break;
            }
          }
          fs_close((u16)dest);
        }
        fs_close((u16)in);
      }
    }
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_MKDIR)
  else if (!strcmp(argv[0], "mkdir") || !strcmp(argv[0], "rm") ||
             !strcmp(argv[0], "rmdir") || !strcmp(argv[0], "mv")) {
    u8 op = !strcmp(argv[0], "mkdir")   ? F_MKDIR
            : !strcmp(argv[0], "rm")    ? F_UNLINK
            : !strcmp(argv[0], "rmdir") ? F_RMDIR
                                        : F_RENAME;
    if (argc != (op == F_RENAME ? 3 : 2))
      r = SYS_EINVAL;
    else
      r = fs_mutate(op, argv[1],
                    op == F_RENAME ? (const char *)argv[2] : (const char *)0);
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_PS)
  else if (!strcmp(argv[0], "ps")) {
    r = kword(SYS_PROC_INFO, (u16)procs);
    if (!r)
      for (i = 0; i < 8; i++)
        if (procs[i * 8 + 4]) {
          number((int)get16(procs + i * 8));
          text(" state=");
          number(procs[i * 8 + 4]);
          text("\r\n");
        }
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_YIELD)
  else if (!strcmp(argv[0], "yield")) {
    for (i = 0; i < 100; i++)
      kyield();
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_SLEEP)
  else if (!strcmp(argv[0], "sleep")) {
    ksleep(argc > 1 ? (u32)atoi(argv[1]) : 100UL);
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_MEM)
  else if (!strcmp(argv[0], "mem")) {
    u8 a[6], p[2];
    mlos_put_u16(p, (u16)a);
    r = mlos_call(SYS_MEMORY_INFO, p);
    if (!r) {
      text("frames free=");
      number(a[2]);
      text("\r\n");
    }
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_MOUNTS)
  else if (!strcmp(argv[0], "mounts")) {
    u8 p[400];
    memset(p, 0, 400);
    p[0] = F_MOUNTS;
    r = fs_call(p);
    if (!r) {
      text(p[144] ? "/ online\r\n" : "/ offline\r\n");
      text(p[145] ? "/disk1 online\r\n" : "/disk1 offline\r\n");
    }
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_RECOVER)
  else if (!strcmp(argv[0], "recover") || !strcmp(argv[0], "unmount")) {
    if (argc != 2)
      r = SYS_EINVAL;
    else
      r = fs_mutate(!strcmp(argv[0], "recover") ? F_RECOVER : F_UNMOUNT,
                    argv[1], 0);
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_FSTEST)
  else if (!strcmp(argv[0], "fstest")) {
    int a, b, c;
    u16 n;
    u32 off;
    fs_mutate(F_UNLINK, "/grow", 0);
    fs_mutate(F_UNLINK, "/blocker", 0);
    a = fs_open("/grow", 7);
    if (kerror(a))
      return 10;
    b = fs_open("/blocker", 7);
    if (kerror(b))
      return 11;
    fs_close((u16)b);
    for (i = 0; i < 8; i++) {
      for (n = 0; n < 256; n++)
        buffer[n] = (u8)(n + i);
      if (fs_write((u16)a, buffer, 256) != 256)
        return 12;
    }
    if (fs_open("/grow", 0) != SYS_EBUSY)
      return 13;
    if (fs_mutate(F_RENAME, "/grow", "/moved") != SYS_EBUSY)
      return 14;
    fs_close((u16)a);
    a = fs_open("/grow", 0);
    b = fs_open("/grow", 0);
    if (kerror(a) || kerror(b))
      return 15;
    if (fs_open("/grow", 1) != SYS_EBUSY)
      return 16;
    for (i = 0; i < 8; i++) {
      if (fs_read((u16)a, buffer, 256) != 256)
        return 17;
      for (n = 0; n < 256; n++)
        if (buffer[n] != (u8)(n + i))
          return 18;
    }
    if (fs_read((u16)a, buffer, 256) != 0)
      return 19;
    fs_close((u16)a);
    fs_close((u16)b);
    fs_mutate(F_MKDIR, "/locked", 0);
    if (fs_chdir("/locked"))
      return 20;
    if (fs_mutate(F_RMDIR, "/locked", 0) != SYS_EBUSY)
      return 21;
    if (fs_chdir("/"))
      return 22;
    if (fs_mutate(F_RMDIR, "/locked", 0))
      return 23;
    a = fs_open("/grow", 1);
    if (kerror(a))
      return 24;
    off = 511;
    if (fs_seek((u16)a, off))
      return 25;
    buffer[0] = 0x91;
    buffer[1] = 0x92;
    c = fs_write((u16)a, buffer, 2);
    fs_close((u16)a);
    if (c != 2)
      return 26;
    a = fs_open("/grow", 0);
    fs_seek((u16)a, off);
    c = fs_read((u16)a, buffer, 2);
    fs_close((u16)a);
    if (c != 2 || buffer[0] != 0x91 || buffer[1] != 0x92)
      return 27;
    text("MLFS growth/locks/cwd PASS\r\n");
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_KEY)
  else if (!strcmp(argv[0], "key")) {
    int mode = term_mode(1);
    text("key ready\r\n");
    r = term_key();
    text("key=");
    number(r);
    text("\r\n");
    term_mode((u8)mode);
    r = 0;
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_DUALTEST)
  else if (!strcmp(argv[0], "dualtest")) {
    int pid, state = 0;
    u8 processes[64];
    do {
      pid = kspawn("drivewait.mlx", 2, 0, 0);
      if (pid == SYS_EAGAIN)
        ksleep(1);
    } while (pid == SYS_EAGAIN);
    if (pid < 0)
      return 61;
    while (!state) {
      kword(SYS_PROC_INFO, (u16)processes);
      for (i = 0; i < 8; i++)
        if (get16(processes + i * 8) == (u16)pid && processes[i * 8 + 4] == 4)
          state = 1;
      ksleep(1);
    }
    ksleep(5);
    if (fs_stat("/note", record))
      return 62;
    text("healthy root during pending drive\r\n");
    if (kwait((u16)pid))
      return 63;
    text("dual drive progress PASS\r\n");
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_STALETEST)
  else if (!strcmp(argv[0], "staletest")) {
    int fd, fresh;
    u8 line[4];
    r = fs_mutate(F_RECOVER, "/disk1", 0);
    if (r)
      return 51;
    fd = fs_open("/disk1/seed", 0);
    if (kerror(fd))
      return 52;
    text("stale test ready\r\n");
    kread(0, line, 1);
    if (fs_read((u16)fd, buffer, 1) != SYS_EIO)
      return 53;
    if (fs_stat("/note", record))
      return 54;
    text("healthy root after drive failure\r\n");
    kread(0, line, 1);
    if (fs_mutate(F_RECOVER, "/disk1", 0))
      return 55;
    if (fs_read((u16)fd, buffer, 1) != SYS_ESTALE)
      return 56;
    if (fs_close((u16)fd))
      return 57;
    fresh = fs_open("/disk1/seed", 0);
    if (kerror(fresh))
      return 58;
    if (fs_read((u16)fresh, buffer, 1) != 1 || buffer[0] != 's')
      return 59;
    fs_close((u16)fresh);
    text("volume recovery/stale PASS\r\n");
  }
#endif
#if !defined(MLOS_SINGLE_COMMAND) || defined(MLOS_ONLY_HELP)
  else if (!strcmp(argv[0], "help"))
    text("echo pwd cd ls cat cp mkdir rm rmdir mv ps mem sleep yield mounts "
         "exit\r\n");
#endif
  else
    r = SYS_ENOSYS;
  if (r < 0) {
    text("error ");
    number(r);
    text("\r\n");
    return 1;
  }
  return 0;
}
