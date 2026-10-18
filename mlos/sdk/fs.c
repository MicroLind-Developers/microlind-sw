/* One synchronous, copied RPC per process. Peer death never reconnects a file
   descriptor silently; callers must explicitly open a new service connection.
 */
#include "fs.h"
#include <cmoc.h>
static u16 tx, rx;
static u8 packet[400], snapshot[512];
static u16 snap_size, snap_pos, snap_generation;
static u8 snap_live;
#define PROC_TOKEN 0xC1
static int proc_token(u16 fd) { return (fd & 0xFF) == PROC_TOKEN; }
static u16 current_proc_token(void) {
  return (snap_generation << 8) | PROC_TOKEN;
}
static char canonical[64], combined[128];
static int virtual_cwd;
static const char *proc_names[3] = {"processes", "memory", "mounts"};
/* Canonicalize before provider selection, retaining stale-cwd rejection even
   for relative paths that climb into a different mount or /proc. */
static int resolve_path(const char *name) {
  u8 a[10], state[8];
  u16 i = 0, j = 1, n = 0, start, volume, generation;
  int r;
  virtual_cwd = 0;
  if (!name[0])
    return SYS_EINVAL;
  if (name[0] != '/') {
    memset(a, 0, 10);
    mlos_put_u16(a + 4, (u16)packet);
    r = mlos_call(SYS_CWD, a);
    if (r)
      return r;
    volume = get16(packet);
    generation = get16(packet + 2);
    virtual_cwd = volume == 65535;
    if (!virtual_cwd && generation) {
      if (volume > 1)
        return SYS_EIO;
      kword(SYS_FS_STATE, (u16)state);
      if (!(state[3] & (1 << volume)) ||
          get16(state + 4 + volume * 2) != generation)
        return SYS_EIO;
    }
    strcpy(combined, (char *)packet + 4);
    n = strlen(combined);
    if (n > 1)
      combined[n++] = '/';
  }
  if (n + strlen(name) >= 128)
    return SYS_ENAMETOOLONG;
  strcpy(combined + n, name);
  canonical[0] = '/';
  while (combined[i]) {
    while (combined[i] == '/')
      i++;
    if (!combined[i])
      break;
    start = i;
    while (combined[i] && combined[i] != '/')
      i++;
    if (i - start == 1 && combined[start] == '.')
      continue;
    if (i - start == 2 && combined[start] == '.' &&
        combined[start + 1] == '.') {
      while (j > 1 && canonical[j - 1] != '/')
        j--;
      if (j > 1)
        j--;
      continue;
    }
    if (i - start >= 48)
      return SYS_ENAMETOOLONG;
    if (j > 1) {
      if (j >= 63)
        return SYS_ENAMETOOLONG;
      canonical[j++] = '/';
    }
    if (j + i - start > 63)
      return SYS_ENAMETOOLONG;
    while (start < i)
      canonical[j++] = combined[start++];
  }
  canonical[j] = 0;
  return 0;
}
static int proc_index(void) {
  u8 i;
  for (i = 0; i < 3; i++)
    if (!strcmp(canonical + 6, proc_names[i]))
      return i;
  return SYS_ENOENT;
}
static int is_proc(void) {
  return !strncmp(canonical, "/proc", 5) &&
         (canonical[5] == 0 || canonical[5] == '/');
}
int fs_call(u8 *p) {
  int r;
  if (!get16(p + 14))
    mlos_put_u16(p + 14, 1);
  if (get16(p + 14) != 1)
    return SYS_ENOSYS;
  if (!tx) {
    r = kconnect("fs", &tx, &rx);
    if (r)
      return r;
  }
  r = ksend(tx, p, 400);
  if (r != 400) {
    return r < 0 ? r : SYS_EIO;
  }
  r = kreceive(rx, p, 400);
  if (r != 400) {
    return r < 0 ? r : SYS_EIO;
  }
  if (get16(p + 14) != 1) {
    return SYS_EIO;
  }
  return (p[1] & 128) ? (int)get16(p + 2) : 0;
}
static void request(u8 op) {
  memset(packet, 0, 400);
  packet[0] = op;
}
static int path_request(u8 op, const char *path) {
  if (strlen(path) > 63)
    return SYS_ENAMETOOLONG;
  request(op);
  strcpy((char *)packet + 16, path);
  return 0;
}
int fs_open(const char *path, u8 flags) {
  int r;
  r = resolve_path(path);
  if (r)
    return r;
  path = canonical;
  if (!strcmp(path, "/proc"))
    return SYS_EISDIR;
  u8 i, a[64];
  char line[64];
  if (!strncmp(path, "/proc/", 6)) {
    if (flags)
      return SYS_EROFS;
    if (snap_live)
      return SYS_ENOMEM;
    if (snap_generation == 255)
      return SYS_ENOMEM;
    snap_size = snap_pos = 0;
    memset(snapshot, 0, 512);
    if (!strcmp(path, "/proc/processes")) {
      r = kword(SYS_PROC_INFO, (u16)a);
      if (r)
        return r;
      for (i = 0; i < 8; i++)
        if (a[i * 8 + 4]) {
          sprintf(line, "pid=%u parent=%u state=%u class=%u\r\n",
                  get16(a + i * 8), get16(a + i * 8 + 2), (u16)a[i * 8 + 4],
                  (u16)a[i * 8 + 5]);
          strcat((char *)snapshot, line);
        }
    } else if (!strcmp(path, "/proc/memory")) {
      r = kword(SYS_MEMORY_INFO, (u16)a);
      if (r)
        return r;
      sprintf((char *)snapshot, "frames=%u reserved=%u free=%u owned=%u\r\n",
              (u16)a[0], (u16)a[1], (u16)a[2], (u16)a[3]);
    } else if (!strcmp(path, "/proc/mounts")) {
      r = kword(SYS_FS_STATE, (u16)a);
      if (r)
        return r;
      sprintf((char *)snapshot,
              "filesystem_pid=%u failed=%u root=%u disk1=%u\r\n", get16(a),
              (u16)a[2], (u16)(a[3] & 1), (u16)((a[3] >> 1) & 1));
    } else
      return SYS_ENOENT;
    snap_size = strlen((char *)snapshot);
    snap_live = 1;
    snap_generation++;
    return current_proc_token();
  }
  r = path_request(F_OPEN, path);
  if (r)
    return r;
  packet[1] = flags;
  r = fs_call(packet);
  return r ? r : (int)get16(packet + 2);
}
int fs_close(u16 fd) {
  if (proc_token(fd)) {
    if (!snap_live || fd != current_proc_token())
      return SYS_ESTALE;
    snap_live = 0;
    return 0;
  }
  request(F_CLOSE);
  mlos_put_u16(packet + 12, fd);
  return fs_call(packet);
}
int fs_read(u16 fd, void *data, u16 count) {
  int r;
  if (proc_token(fd)) {
    if (!snap_live || fd != current_proc_token())
      return SYS_ESTALE;
    if (count > snap_size - snap_pos)
      count = snap_size - snap_pos;
    memcpy(data, snapshot + snap_pos, count);
    snap_pos += count;
    return (int)count;
  }
  if (count > 256)
    count = 256;
  request(F_READ);
  mlos_put_u16(packet + 12, fd);
  mlos_put_u16(packet + 6, count);
  r = fs_call(packet);
  if (r && !get16(packet + 4))
    return r;
  count = get16(packet + 4);
  if (count > 256)
    return SYS_EIO;
  memcpy(data, packet + 144, count);
  return (int)count;
}
int fs_write(u16 fd, const void *data, u16 count) {
  int r;
  if (proc_token(fd))
    return SYS_EROFS;
  if (count > 256)
    count = 256;
  request(F_WRITE);
  mlos_put_u16(packet + 12, fd);
  mlos_put_u16(packet + 6, count);
  memcpy(packet + 144, data, count);
  r = fs_call(packet);
  return r && !get16(packet + 4) ? r : (int)get16(packet + 4);
}
int fs_seek(u16 fd, u32 offset) {
  if (proc_token(fd)) {
    if (!snap_live || fd != current_proc_token())
      return SYS_ESTALE;
    if (offset > snap_size)
      return SYS_EINVAL;
    snap_pos = (u16)offset;
    return 0;
  }
  request(F_SEEK);
  mlos_put_u16(packet + 12, fd);
  put32(packet + 8, offset);
  return fs_call(packet);
}
int fs_chdir(const char *path) {
  u8 a[10];
  int r = resolve_path(path);
  if (r)
    return r;
  if (is_proc()) {
    if (strcmp(canonical, "/proc"))
      return proc_index() >= 0 ? SYS_ENOTDIR : SYS_ENOENT;
    memset(a, 0, 10);
    a[2] = 2;
    return mlos_call(SYS_CWD, a);
  }
  r = path_request(F_CHDIR, canonical);
  return r ? r : fs_call(packet);
}
int fs_getcwd(char *path) {
  u8 a[10], state[8];
  u16 volume, generation;
  int r;
  memset(a, 0, 10);
  mlos_put_u16(a + 4, (u16)packet);
  r = mlos_call(SYS_CWD, a);
  if (r)
    return r;
  volume = get16(packet);
  generation = get16(packet + 2);
  if (volume != 65535) {
    if (volume > 1)
      return SYS_EIO;
    r = kword(SYS_FS_STATE, (u16)state);
    if (r)
      return r;
    if (!get16(state) || state[2] || (generation &&
        (!(state[3] & (1 << volume)) || get16(state + 4 + 2 * volume) != generation)))
      return SYS_EIO;
  }
  strcpy(path, (char *)packet + 4);
  return 0;
}
int fs_list(const char *path, u32 *cursor, u8 *dentry) {
  u32 position;
  int r = resolve_path(path);
  if (r)
    return r;
  if (is_proc()) {
    if (strcmp(canonical, "/proc"))
      return SYS_ENOTDIR;
    if (*cursor >= 3)
      return 0;
    memset(dentry, 0, 128);
    dentry[0] = 1;
    dentry[1] = 2;
    strcpy((char *)dentry + 16, proc_names[(u16)*cursor]);
    (*cursor)++;
    return 1;
  }
  if (!strcmp(canonical, "/") && *cursor < 2) {
    memset(dentry, 0, 128);
    dentry[0] = 1;
    dentry[1] = 1;
    strcpy((char *)dentry + 16, *cursor ? "disk1" : "proc");
    (*cursor)++;
    return 1;
  }
  r = path_request(F_LIST, canonical);
  if (r)
    return r;
  position = *cursor;
  if (!strcmp(canonical, "/")) {
    if (position == 2)
      position = 0;
    else
      position &= 0x7FFFFFFFUL;
  }
  put32(packet + 8, position);
  r = fs_call(packet);
  if (!r) {
    *cursor = get32(packet + 8);
    if (!strcmp(canonical, "/"))
      *cursor |= 0x80000000UL;
    memcpy(dentry, packet + 144, 128);
    return get16(packet + 4) ? 1 : 0;
  }
  return r;
}
int fs_stat(const char *path, u8 *dentry) {
  int r = resolve_path(path);
  if (r)
    return r;
  if (is_proc()) {
    if (strcmp(canonical, "/proc") && proc_index() < 0)
      return SYS_ENOENT;
    memset(dentry, 0, 128);
    dentry[0] = 1;
    dentry[1] = !strcmp(canonical, "/proc") ? 1 : 2;
    strcpy((char *)dentry + 16,
           !strcmp(canonical, "/proc") ? "proc" : (const char *)canonical + 6);
    return 0;
  }
  r = path_request(F_STAT, canonical);
  if (r)
    return r;
  r = fs_call(packet);
  if (!r)
    memcpy(dentry, packet + 144, 128);
  return r;
}
int fs_mutate(u8 op, const char *path, const char *other) {
  char source[64];
  int r = resolve_path(path);
  if (r)
    return r;
  if (is_proc())
    return SYS_EROFS;
  strcpy(source, canonical);
  if (other) {
    r = resolve_path(other);
    if (r)
      return r;
    if (is_proc())
      return SYS_EROFS;
  }
  r = path_request(op, source);
  if (r)
    return r;
  if (other)
    strcpy((char *)packet + 80, canonical);
  return fs_call(packet);
}

/* Launch metadata uses an untypeable control prefix on operator argv entries.
   Validate syntax first, acquire shared input before exclusive output, then
   create/truncate in the child before application main. Never transfer a
   writable descriptor from the shell. Both ordinary kwrite/kread honor it. */
int kstdio_start(int argc, char **argv) {
  int i, j, r;
  char *input = 0, *output = 0;
  for (i = 1; i < argc; i++)
    if (argv[i][0] == 1) {
      if (!argv[i][1] || argv[i][2] || i + 1 >= argc || argv[i + 1][0] == 1)
        return SYS_EINVAL;
      if (argv[i][1] == '<') {
        if (input)
          return SYS_EINVAL;
        input = argv[++i];
      } else if (argv[i][1] == '>') {
        if (output)
          return SYS_EINVAL;
        output = argv[++i];
      } else
        return SYS_EINVAL;
    }
  if (input) {
    r = fs_open(input, 0);
    if (kerror(r))
      return r;
    std_infd = (u16)r;
    std_infile = 1;
  }
  if (output) {
    r = fs_open(output, F_WRITE_FLAG | F_CREATE_FLAG | F_TRUNCATE_FLAG);
    if (kerror(r)) {
      kstdio_close();
      return r;
    }
    std_outfd = (u16)r;
    std_outfile = 1;
  }
  for (i = 1; i < argc; i++)
    if (argv[i][0] == 1) {
      for (j = i; j + 2 < argc; j++)
        argv[j] = argv[j + 2];
      argc -= 2;
      i--;
    }
  argv[argc] = 0;
  return argc;
}
void kstdio_close(void) {
  if (std_infile) {
    fs_close(std_infd);
    std_infile = 0;
  }
  if (std_outfile) {
    fs_close(std_outfd);
    std_outfile = 0;
  }
}
