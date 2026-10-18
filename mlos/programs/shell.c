#include "fs.h"
#include <cmoc.h>
static char line[110], tokens[128], image[48], cwd[64];
static char *args[8];
static u8 ctl[4];
static void text(const char *s) { kwrite(s, strlen(s)); }
static void error(int r) {
  char b[20];
  sprintf(b, "error %d\r\n", r);
  text(b);
}
/* Quotes preserve literal spaces; backslash quotes one byte. Operators are
   separate argv entries for command startup. No pipelines or expansion. */
static int parse(char *s) {
  u8 argc = 0;
  char *in = s, *out = tokens;
  char quote;
  while (*in) {
    while (*in == ' ' || *in == '\t')
      in++;
    if (!*in)
      break;
    if (argc == 8)
      return SYS_EINVAL;
    args[argc++] = out;
    if (*in == '<' || *in == '>') {
      *out++ = 1;
      *out++ = *in++;
      *out++ = 0;
      continue;
    }
    quote = 0;
    while (*in) {
      char c = *in;
      if (!quote && (c == ' ' || c == '\t' || c == '<' || c == '>'))
        break;
      in++;
      if (c == '\\') {
        if (!*in)
          return SYS_EINVAL;
        *out++ = *in++;
        continue;
      }
      if (c == '\'' || c == '"') {
        if (!quote) {
          quote = c;
          continue;
        }
        if (quote == c) {
          quote = 0;
          continue;
        }
      }
      *out++ = c;
    }
    if (quote)
      return SYS_EINVAL;
    *out++ = 0;
  }
  return argc;
}
int main(void) {
  int n, c, argc, pid;
  u8 spawn[8];
  if (mlos_call(SYS_STANDARD, 0))
    kexit(126);
  memset(ctl, 0, 4);
  if (mlos_call(SYS_TTY_CONTROL, ctl))
    kexit(126);
  text("MLOS console\r\n");
  for (;;) {
    if (fs_getcwd(cwd))
      strcpy(cwd, "?");
    text(cwd);
    text(" > ");
    n = 0;
    for (;;) {
      c = mlos_call(SYS_GETC, 0);
      if (c == SYS_EAGAIN) {
        mlos_call(SYS_TTY_WAIT, 0);
        continue;
      }
      if (c == SYS_ECANCELLED) {
        text("^C\r\n");
        n = 0;
        break;
      }
      if (c == SYS_EOF)
        kexit(0);
      if (c < 0) {
        error(c);
        ksleep(1);
        continue;
      }
      if (c == '\r' || c == '\n')
        break;
      if (c >= 32 && n < 109) {
        line[n++] = (char)c;
      }
    }
    line[n] = 0;
    argc = parse(line);
    if (argc < 0) {
      error(argc);
      continue;
    }
    if (!argc)
      continue;
    if (!strcmp(args[0], "cd")) {
      if (argc != 2)
        error(SYS_EINVAL);
      else {
        c = fs_chdir(args[1]);
        if (c)
          error(c);
      }
      continue;
    }
    if (!strcmp(args[0], "loadmod")) {
      if (argc != 2)
        error(SYS_EINVAL);
      else {
        c = kword(SYS_MODULE_LOAD, (u16)args[1]);
        if (c < 0)
          error(c);
        else
          text("module loaded\r\n");
      }
      continue;
    }
    if (!strcmp(args[0], "bindmod")) {
      u8 p[6];
      if (argc != 4)
        error(SYS_EINVAL);
      else {
        mlos_put_u16(p, (u16)atoi(args[1]));
        p[2] = (u8)atoi(args[2]);
        p[3] = 0;
        mlos_put_u16(p + 4, (u16)atoi(args[3]));
        c = mlos_call(SYS_MODULE_BIND, p);
        if (c)
          error(c);
      }
      continue;
    }
    if (!strcmp(args[0], "exit")) {
      kexit(0);
    }
    if (strlen(args[0]) + 4 >= sizeof(image)) {
      error(SYS_ENAMETOOLONG);
      continue;
    }
    strcpy(image, args[0]);
    strcat(image, ".mlx");
    mlos_put_u16(spawn, (u16)image);
    spawn[2] = 1;
    spawn[3] = (u8)argc;
    mlos_put_u16(spawn + 4, (u16)args);
    mlos_put_u16(spawn + 6, 1);
    do {
      pid = mlos_call(SYS_SPAWN, spawn);
      if (pid == SYS_EAGAIN)
        ksleep(1);
    } while (pid == SYS_EAGAIN);
    if (pid < 0) {
      if (pid == SYS_ECANCELLED)
        text("^C\r\n");
      else
        error(pid);
      continue;
    }
    ctl[0] = 1;
    ctl[1] = 0;
    mlos_put_u16(ctl + 2, (u16)pid);
    c = mlos_call(SYS_TTY_CONTROL, ctl);
    if (c) {
      error(c);
      kword(SYS_KILL, (u16)pid);
    }
    c = kwait((u16)pid);
    ctl[0] = 3;
    mlos_call(SYS_TTY_CONTROL, ctl);
    if (c)
      error(c);
  }
  return 0;
}
