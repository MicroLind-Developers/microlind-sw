#define MLOS_SDK_IMPLEMENTATION
#include "mlos.h"
#include "fs.h"
#include <cmoc.h>
u8 std_infile, std_outfile;
u16 std_infd, std_outfd;
int mlos_program_main(int argc, char **argv);
int main(void) {
  int argc = mlos_argc(), r;
  char error[32];
  char **argv = mlos_argv();
  if (argc) {
    r = mlos_call(SYS_STANDARD, 0);
    if (r)
      kexit(126);
    r = kstdio_start(argc, argv);
    if (r < 0) {
      sprintf(error, "launch error %d\r\n", r);
      kwrite(error, strlen(error));
      kexit(126);
    }
    argc = r;
    mlos_put_u16((u8 *)0x300, (u16)argc);
  }
  r = mlos_program_main(argc, argv);
  kstdio_close();
  return r;
}
int kerror(int r) { return r < 0 && r >= SYS_ENODEV; }
u16 get16(const u8 *p) { return ((u16)p[0] << 8) | p[1]; }
void put32(u8 *p, u32 v) {
  p[0] = (u8)(v >> 24);
  p[1] = (u8)(v >> 16);
  p[2] = (u8)(v >> 8);
  p[3] = (u8)v;
}
u32 get32(const u8 *p) {
  return ((u32)p[0] << 24) | ((u32)p[1] << 16) | ((u32)p[2] << 8) | p[3];
}
int kword(u16 call, u16 value) {
  u8 p[2];
  mlos_put_u16(p, value);
  return mlos_call(call, p);
}
void kyield(void) { mlos_call(SYS_YIELD, 0); }
void ksleep(u32 ticks) {
  u8 p[4];
  put32(p, ticks);
  mlos_call(SYS_SLEEP, p);
}
void kexit(int status) {
  kword(SYS_EXIT, (u16)status);
  for (;;)
    kyield();
}
int kwrite(const void *data, u16 count) {
  u8 p[4];
  u16 done = 0, n;
  int r;
  if (std_outfile) {
    while (done < count) {
      r = fs_write(std_outfd, (const u8 *)data + done, count - done);
      if (r <= 0)
        return done ? (int)done : (r ? r : SYS_EIO);
      done += (u16)r;
    }
    return (int)done;
  }
  while (done < count) {
    n = count - done;
    if (n > 256)
      n = 256;
    mlos_put_u16(p, (u16)((const u8 *)data + done));
    mlos_put_u16(p + 2, n);
    r = mlos_call(SYS_WRITE, p);
    if (r == SYS_EAGAIN) {
      ksleep(1);
      continue;
    }
    if (r <= 0)
      return done ? (int)done : (r ? r : SYS_EIO);
    done += (u16)r;
  }
  return (int)done;
}
int kspawn(const char *name, u8 priority, u8 argc, const char **argv) {
  u8 p[8];
  mlos_put_u16(p, (u16)name);
  p[2] = priority;
  p[3] = argc;
  mlos_put_u16(p + 4, (u16)argv);
  mlos_put_u16(p + 6, 0);
  return mlos_call(SYS_SPAWN, p);
}
int kwait(u16 pid) {
  int status = kword(SYS_WAIT, pid), r;
  do {
    r = kword(SYS_TTY_DRAIN, pid);
    if (r == SYS_EAGAIN)
      ksleep(1);
  } while (r == SYS_EAGAIN);
  return status;
}
int kwait_one(u16 handle) {
  u8 p[8], h[2];
  mlos_put_u16(h, handle);
  mlos_put_u16(p, (u16)h);
  p[2] = 1;
  p[3] = 0;
  put32(p + 4, 0);
  return mlos_call(SYS_WAIT_ANY, p);
}
int ksend(u16 handle, const void *data, u16 count) {
  u8 p[10];
  int r;
  mlos_put_u16(p, handle);
  mlos_put_u16(p + 2, (u16)data);
  mlos_put_u16(p + 4, count);
  mlos_put_u16(p + 6, 0);
  mlos_put_u16(p + 8, 0);
  for (;;) {
    r = mlos_call(SYS_SEND, p);
    if (r != SYS_EAGAIN)
      return r;
    r = kwait_one(handle);
    if (kerror(r))
      return r;
    r = mlos_call(SYS_SEND, p);
    if (r != SYS_EAGAIN)
      return r;
    /* TX readiness means some space. An atomic message can still need more;
       sleep before retrying so partial space cannot cause a syscall spin. */
    ksleep(1);
  }
}
int kreceive(u16 handle, void *data, u16 capacity) {
  u8 p[10];
  int r;
  mlos_put_u16(p, handle);
  mlos_put_u16(p + 2, (u16)data);
  mlos_put_u16(p + 4, capacity);
  mlos_put_u16(p + 6, 0);
  mlos_put_u16(p + 8, 0);
  for (;;) {
    r = mlos_call(SYS_RECEIVE, p);
    if (r != SYS_EAGAIN)
      return r;
    kwait_one(handle);
  }
}
int klisten(const char *name) { return kword(SYS_LISTEN, (u16)name); }
int kconnect(const char *name, u16 *tx, u16 *rx) {
  u8 p[8], out[4];
  int r;
  mlos_put_u16(p, (u16)name);
  mlos_put_u16(p + 2, (u16)out);
  mlos_put_u16(p + 4, 512);
  mlos_put_u16(p + 6, 0);
  r = mlos_call(SYS_CONNECT, p);
  if (r)
    return r;
  *tx = get16(out);
  *rx = get16(out + 2);
  return 0;
}
int kaccept(u16 listener, u16 *tx, u16 *rx) {
  u8 p[4], out[4];
  int r;
  mlos_put_u16(p, listener);
  mlos_put_u16(p + 2, (u16)out);
  for (;;) {
    r = mlos_call(SYS_ACCEPT, p);
    if (r != SYS_EAGAIN)
      break;
    kwait_one(listener);
  }
  if (r)
    return r;
  *tx = get16(out);
  *rx = get16(out + 2);
  return 0;
}
int kclose(u16 handle) { return kword(SYS_CLOSE, handle); }

/* Standard descriptors0/1/2: edited or raw input, process stdout, output-only
   log records. EOF after a partial read returns the accepted byte count. */
int kread(u8 descriptor, void *data, u16 count) {
  u16 done = 0;
  int c;
  if (descriptor != 0)
    return SYS_EHANDLE;
  if (std_infile)
    return fs_read(std_infd, data, count);
  while (done < count) {
    c = mlos_call(SYS_GETC, 0);
    if (c == SYS_EAGAIN) {
      if (done)
        return (int)done;
      mlos_call(SYS_TTY_WAIT, 0);
      continue;
    }
    if (c == SYS_EOF)
      return (int)done;
    if (c < 0)
      return done ? (int)done : c;
    ((u8 *)data)[done++] = (u8)c;
    if (c == 10)
      return (int)done;
  }
  return (int)done;
}
int klog(const void *data, u16 count) {
  u8 p[4];
  u16 n, done = 0;
  int r;
  while (done < count) {
    n = count - done;
    if (n > 31)
      n = 31;
    mlos_put_u16(p, (u16)((const u8 *)data + done));
    mlos_put_u16(p + 2, n);
    r = mlos_call(SYS_LOG, p);
    if (r < 0)
      return r;
    done += n;
  }
  return (int)done;
}
