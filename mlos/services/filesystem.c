/* Namespace/descriptor frontend. The maintained assembly MLFS engine executes
   in a private worker per drive, so a waiting controller cannot block another.
   All buffers and in-flight requests are bounded and owned by this service. */
#include "fs.h"
#include <cmoc.h>
#define CLIENTS 3
#define FILES 16
#define DRIVES 2
#define IDLE 0
#define QUEUED 1
#define DISPATCHED 2
#define RESPONSE 3
#define OPEN_STAT 1
#define OPEN_CREATE 2
#define OPEN_TRUNCATE 3
typedef struct {
  u16 tx, rx, pid;
  u8 used, state, volume, phase, file;
  u8 packet[400];
} Client;
typedef struct {
  u16 tx, rx, pid, generation;
  int active;
  u8 online, starting;
  int management;
  u32 deadline;
} Volume;
typedef struct {
  u16 owner, connection, volume_generation;
  u8 live, generation, volume, flags;
  u32 position;
  char path[64];
} File;
static Client clients[CLIENTS];
static Volume volumes[DRIVES];
static File files[FILES];
static u16 listener;
static u8 work[400], cwd[68], cwd_args[10], proc[64];
static char path[64];
static int rawrecv(u16 h, u8 *p) {
  u8 a[10];
  mlos_put_u16(a, h);
  mlos_put_u16(a + 2, (u16)p);
  mlos_put_u16(a + 4, 400);
  mlos_put_u16(a + 6, 0);
  mlos_put_u16(a + 8, 0);
  return mlos_call(SYS_RECEIVE, a);
}
static int rawsend(u16 h, u8 *p) {
  u8 a[10];
  mlos_put_u16(a, h);
  mlos_put_u16(a + 2, (u16)p);
  mlos_put_u16(a + 4, 400);
  mlos_put_u16(a + 6, 0);
  mlos_put_u16(a + 8, 0);
  return mlos_call(SYS_SEND, a);
}
static void response(Client *c, int result) {
  mlos_put_u16(c->packet + 2, (u16)result);
  c->packet[1] = result < 0 ? 128 : 0;
  c->state = RESPONSE;
}
static void handle_response(Client *c, u16 token) {
  mlos_put_u16(c->packet + 2, token);
  c->packet[1] = 0;
  c->state = RESPONSE;
}
static int error_code(int r) {
  switch (r) {
  case -1:
    return SYS_EIO;
  case -5:
    return SYS_ENOENT;
  case -6:
    return SYS_ENOTDIR;
  case -7:
    return SYS_EISDIR;
  case -10:
    return SYS_ENAMETOOLONG;
  case -12:
    return SYS_EEXIST;
  case -13:
    return SYS_ENOSPC;
  case -14:
    return SYS_EBUSY;
  case -15:
    return SYS_EROFS;
  default:
    return SYS_EIO;
  }
}
static int cwd_get(u16 pid) {
  mlos_put_u16(cwd_args, pid);
  cwd_args[2] = 0;
  cwd_args[3] = 0;
  mlos_put_u16(cwd_args + 4, (u16)cwd);
  return mlos_call(SYS_CWD, cwd_args);
}
static int cwd_set(u16 pid, u8 volume) {
  mlos_put_u16(cwd_args, pid);
  cwd_args[2] = 1;
  cwd_args[3] = 0;
  mlos_put_u16(cwd_args + 4, (u16)path);
  mlos_put_u16(cwd_args + 6, volume);
  mlos_put_u16(cwd_args + 8, volumes[volume].generation);
  return mlos_call(SYS_CWD, cwd_args);
}
/* Normalize one bounded absolute/relative Latin1 path, with root-clamped '..'.
 */
static int normalize(Client *c, const char *name, char *out) {
  char input[128];
  u16 n = 0, i = 0, j = 0, start;
  if (!name[0])
    return SYS_EINVAL;
  if (name[0] != '/') {
    if (cwd_get(c->pid))
      return SYS_EIO;
    if (get16(cwd) >= DRIVES)
      return SYS_EIO;
    if (get16(cwd + 2) && (!volumes[get16(cwd)].online ||
                           get16(cwd + 2) != volumes[get16(cwd)].generation))
      return SYS_EIO;
    strcpy(input, (char *)cwd + 4);
    n = strlen(input);
    if (n > 1)
      input[n++] = '/';
  }
  if (n + strlen(name) >= sizeof(input))
    return SYS_ENAMETOOLONG;
  strcpy(input + n, name);
  out[0] = '/';
  j = 1;
  while (input[i]) {
    while (input[i] == '/')
      i++;
    if (!input[i])
      break;
    start = i;
    while (input[i] && input[i] != '/')
      i++;
    if (i - start == 1 && input[start] == '.')
      continue;
    if (i - start == 2 && input[start] == '.' && input[start + 1] == '.') {
      while (j > 1 && out[j - 1] != '/')
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
      out[j++] = '/';
    }
    if (j + i - start > 63)
      return SYS_ENAMETOOLONG;
    while (start < i)
      out[j++] = input[start++];
  }
  out[j] = 0;
  return 0;
}
static u8 volume_for(const char *p) {
  return !strncmp(p, "/disk1", 6) && (p[6] == 0 || p[6] == '/') ? 1 : 0;
}
static const char *relative_path(const char *p, u8 volume) {
  if (volume && p[6])
    return p + 6;
  if (volume)
    return "/";
  return p;
}
static int is_prefix(const char *a, const char *b) {
  u16 n = strlen(a);
  return !strncmp(a, b, n) && (b[n] == 0 || b[n] == '/' || n == 1);
}
static int locks(const char *p, u8 volume, int writer, int subtree) {
  u8 i;
  for (i = 0; i < FILES; i++)
    if (files[i].live && files[i].volume == volume &&
        files[i].volume_generation == volumes[volume].generation) {
      if ((subtree && is_prefix(p, files[i].path)) ||
          !strcmp(p, files[i].path)) {
        if (subtree || writer || (files[i].flags & F_WRITE_FLAG))
          return SYS_EBUSY;
      }
    }
  return 0;
}
static int cwd_busy(const char *p, u8 volume) {
  u8 i;
  if (kword(SYS_PROC_INFO, (u16)proc))
    return SYS_EIO;
  for (i = 0; i < 8; i++)
    if (proc[i * 8 + 4] && proc[i * 8 + 4] != 5) {
      if (cwd_get(get16(proc + i * 8)))
        continue;
      if (get16(cwd) == volume &&
          get16(cwd + 2) == volumes[volume].generation &&
          is_prefix(p, (char *)cwd + 4))
        return SYS_EBUSY;
    }
  return 0;
}
static int new_file(void) {
  u8 i;
  for (i = 0; i < FILES; i++)
    if (!files[i].live && files[i].generation < 255)
      return i;
  return SYS_ENOMEM;
}
static int file_index(Client *c, int stale_close) {
  u16 token = get16(c->packet + 12);
  u8 i = (u8)((u8)token - 128);
  if (!i || i > FILES)
    return SYS_EHANDLE;
  i--;
  if (!files[i].live || files[i].generation != (u8)(token >> 8))
    return SYS_ESTALE;
  if (files[i].owner != c->pid)
    return SYS_EOWNER;
  if (!stale_close &&
      (files[i].volume_generation != volumes[files[i].volume].generation ||
       !volumes[files[i].volume].online))
    return SYS_ESTALE;
  return i;
}
static void publish_file(Client *c) {
  File *f = &files[c->file];
  f->live = 1;
  f->generation++;
  f->position = 0;
  handle_response(c, ((u16)f->generation << 8) | (c->file + 129));
}
static void disconnect(Client *c) {
  u8 i;
  for (i = 0; i < FILES; i++)
    if (files[i].owner == c->pid && files[i].connection == c->rx)
      files[i].live = 0;
  kclose(c->tx);
  kclose(c->rx);
  c->used = 0;
  c->state = IDLE;
}
static void publish_volume(u8 v) {
  u8 p[4];
  p[0] = v;
  p[1] = volumes[v].online;
  mlos_put_u16(p + 2, volumes[v].generation);
  mlos_call(SYS_FS_PUBLISH, p);
}
static void offline(u8 v) {
  volumes[v].online = 0;
  if (volumes[v].generation < 65535)
    volumes[v].generation++;
  publish_volume(v);
  kclose(volumes[v].tx);
  kclose(volumes[v].rx);
  volumes[v].tx = volumes[v].rx = 0;
  if (volumes[v].pid)
    kword(SYS_KILL, volumes[v].pid);
}
static u32 now(void) {
  u8 t[4];
  kword(SYS_TICKS, (u16)t);
  return get32(t);
}
static int worker_dead(u8 v) {
  u8 i;
  if (!volumes[v].pid)
    return 1;
  kword(SYS_PROC_INFO, (u16)proc);
  for (i = 0; i < 8; i++)
    if (get16(proc + i * 8) == volumes[v].pid && proc[i * 8 + 4]) {
      if (proc[i * 8 + 4] != 5)
        return 0;
      kwait(volumes[v].pid);
      break;
    }
  volumes[v].pid = 0;
  return 1;
}
static void management(Client *c, u8 v, u8 op) {
  u8 i;
  int r;
  if (volumes[v].starting) {
    response(c, SYS_EBUSY);
    return;
  }
  if (op == F_UNMOUNT) {
    if (!volumes[v].online) {
      response(c, SYS_ENODEV);
      return;
    }
    for (i = 0; i < FILES; i++)
      if (files[i].live && files[i].volume == v &&
          files[i].volume_generation == volumes[v].generation) {
        response(c, SYS_EBUSY);
        return;
      }
    r = cwd_busy(v ? "/disk1" : "/", v);
    if (r) {
      response(c, r);
      return;
    }
    if (volumes[v].active >= 0) {
      response(c, SYS_EBUSY);
      return;
    }
    offline(v);
    if (volumes[v].pid)
      kword(SYS_KILL, volumes[v].pid);
    volumes[v].starting = 2;
  } else {
    if (volumes[v].generation == 65535) {
      response(c, SYS_EOVERFLOW);
      return;
    }
    if (volumes[v].online) {
      response(c, SYS_EBUSY);
      return;
    }
    volumes[v].starting = 1;
  }
  volumes[v].management = (int)(c - clients);
  volumes[v].deadline = now() + 3000UL;
  c->volume = v;
  c->state = DISPATCHED;
}
/* Explicit mount/recovery is a continuation: another drive keeps dispatching
   while this worker validates, waits, fails, or settles old requests. */
static void mount_progress(u8 v) {
  Volume *d = &volumes[v];
  Client *c;
  int r;
  u16 tx, rx;
  if (!d->starting)
    return;
  c = &clients[d->management];
  if (d->starting == 3) {
    if (worker_dead(v)) {
      d->starting = 0;
      response(c, SYS_EIO);
      return;
    }
  } else {
    if (!worker_dead(v))
      return;
    if (d->starting == 2) {
      d->starting = 0;
      response(c, 0);
      return;
    }
  }
  if ((long)(now() - d->deadline) >= 0) {
    if (d->pid)
      kword(SYS_KILL, d->pid);
    d->starting = 0;
    response(c, SYS_EIO);
    return;
  }
  if (!d->pid) {
    r = kspawn(v ? "fs1.mlx" : "fs0.mlx", 0, 0, 0);
    if (r == SYS_EAGAIN)
      return;
    if (r < 0) {
      d->starting = 0;
      response(c, r);
      return;
    }
    d->pid = (u16)r;
    d->starting = 3;
  }
  r = kconnect(v ? "fs1" : "fs0", &tx, &rx);
  if (r)
    return;
  d->tx = tx;
  d->rx = rx;
  d->online = 1;
  d->generation++;
  publish_volume(v);
  d->active = -1;
  d->starting = 0;
  response(c, 0);
}
static int immutable(const char *p) {
  u16 n = strlen(p);
  return !strcmp(p, "/mlos.bin") ||
         (n > 4 && (!strcmp(p + n - 4, ".mlx") || !strcmp(p + n - 4, ".mld")));
}
static void prepare(Client *c) {
  u8 op = c->packet[0], v;
  int r, index;
  u32 offset;
  c->packet[79] = 0;
  c->packet[143] = 0;
  c->phase = 0;
  if (get16(c->packet + 14) != 1) {
    response(c, SYS_ENOSYS);
    return;
  }
  if (op != F_OPEN && c->packet[1]) {
    response(c, SYS_EINVAL);
    return;
  }
  if (op > F_UNMOUNT) {
    response(c, SYS_ENOSYS);
    return;
  }
  if (op == F_CLOSE) {
    r = file_index(c, 1);
    if (r >= 0) {
      files[r].live = 0;
      r = 0;
    }
    response(c, r);
    return;
  }
  if (op == F_READ || op == F_WRITE || op == F_SEEK) {
    index = file_index(c, 0);
    if (index < 0) {
      response(c, index);
      return;
    }
    c->file = (u8)index;
    v = files[index].volume;
    c->volume = v;
    if (op == F_SEEK) {
      offset = get32(c->packet + 8);
      files[index].position = offset;
      response(c, 0);
      return;
    }
    if (op == F_WRITE && !(files[index].flags & F_WRITE_FLAG)) {
      response(c, SYS_EPERM);
      return;
    }
    if (get16(c->packet + 6) > 256) {
      response(c, SYS_EINVAL);
      return;
    }
    if (!get16(c->packet + 6)) {
      mlos_put_u16(c->packet + 4, 0);
      response(c, 0);
      return;
    }
    strcpy((char *)c->packet + 16, files[index].path);
    put32(c->packet + 8, files[index].position);
    c->state = QUEUED;
    return;
  }
  if (op == F_GETCWD) {
    r = cwd_get(c->pid);
    if (!r) {
      v = (u8)get16(cwd);
      if (v >= DRIVES)
        r = SYS_EIO;
      else if (get16(cwd + 2) &&
               (!volumes[v].online || get16(cwd + 2) != volumes[v].generation))
        r = SYS_EIO;
      else
        strcpy((char *)c->packet + 144, (char *)cwd + 4);
    }
    response(c, r);
    return;
  }
  if (op == F_MOUNTS) {
    c->packet[144] = volumes[0].online;
    c->packet[145] = volumes[1].online;
    mlos_put_u16(c->packet + 4, 2);
    response(c, 0);
    return;
  }
  if (op == F_RECOVER || op == F_UNMOUNT) {
    v = volume_for((char *)c->packet + 16);
    management(c, v, op);
    return;
  }
  r = normalize(c, (char *)c->packet + 16, path);
  if (r) {
    response(c, r);
    return;
  }
  if (!strncmp(path, "/proc", 5) && (path[5] == 0 || path[5] == '/')) {
    response(c, SYS_EROFS);
    return;
  }
  v = volume_for(path);
  c->volume = v;
  if (!volumes[v].online) {
    response(c, SYS_ENODEV);
    return;
  }
  strcpy((char *)c->packet + 16, path);
  if (op == F_READ_PATH || op == F_WRITE_PATH || op == F_TRUNCATE) {
    response(c, SYS_EPERM);
    return;
  }
  if (op == F_OPEN) {
    if (immutable(path) && (c->packet[1] & 7)) {
      response(c, SYS_EROFS);
      return;
    }
    if ((c->packet[1] & ~7) || ((c->packet[1] & 6) && !(c->packet[1] & 1))) {
      response(c, SYS_EINVAL);
      return;
    }
    r = locks(path, v, c->packet[1] & F_WRITE_FLAG, 0);
    if (r) {
      response(c, r);
      return;
    }
    index = new_file();
    if (index < 0) {
      response(c, index);
      return;
    }
    c->file = (u8)index;
    files[index].live = 2;
    files[index].owner = c->pid;
    files[index].connection = c->rx;
    files[index].volume = v;
    files[index].volume_generation = volumes[v].generation;
    files[index].flags = c->packet[1];
    strcpy(files[index].path, path);
    c->phase = OPEN_STAT;
  }
  if (op >= F_CREATE && op <= F_RENAME) {
    if (immutable(path)) {
      response(c, SYS_EROFS);
      return;
    }
    if (op == F_RMDIR || op == F_RENAME) {
      r = cwd_busy(path, v);
      if (r) {
        response(c, r);
        return;
      }
    }
    r = locks(path, v, 1, 1);
    if (r) {
      response(c, r);
      return;
    }
    if (op == F_RENAME) {
      r = normalize(c, (char *)c->packet + 80, path);
      if (r || volume_for(path) != v) {
        response(c, r ? r : SYS_EINVAL);
        return;
      }
      if (!strncmp(path, "/proc", 5) && (path[5] == 0 || path[5] == '/')) {
        response(c, SYS_EROFS);
        return;
      }
      if (immutable(path)) {
        response(c, SYS_EROFS);
        return;
      }
      if (locks(path, v, 1, 1)) {
        response(c, SYS_EBUSY);
        return;
      }
      strcpy((char *)c->packet + 80, path);
    }
  }
  c->state = QUEUED;
}
static void dispatch(Client *c, u8 index) {
  u8 op = c->packet[0], v = c->volume;
  int r;
  memcpy(work, c->packet, 400);
  strcpy((char *)work + 16, relative_path((char *)c->packet + 16, v));
  if (op == F_RENAME)
    strcpy((char *)work + 80, relative_path((char *)c->packet + 80, v));
  if (op == F_OPEN) {
    work[0] = c->phase == OPEN_CREATE     ? F_CREATE
              : c->phase == OPEN_TRUNCATE ? F_TRUNCATE
                                          : F_STAT;
    put32(work + 8, 0);
  }
  if (op == F_CHDIR)
    work[0] = F_STAT;
  if (op == F_READ)
    work[0] = F_READ_PATH;
  if (op == F_WRITE)
    work[0] = F_WRITE_PATH;
  r = rawsend(volumes[v].tx, work);
  if (r == 400) {
    c->state = DISPATCHED;
    volumes[v].active = index;
  } else if (r != SYS_EAGAIN) {
    offline(v);
    response(c, SYS_EIO);
  }
}
static void complete(Client *c) {
  int status = (int)get16(work + 2);
  u8 op = c->packet[0];
  u16 count = get16(work + 4);
  if (status == -1 || status == -3 || status == -4) {
    if ((op == F_READ || op == F_WRITE) && count <= 256) {
      memcpy(c->packet + 144, work + 144, 256);
      mlos_put_u16(c->packet + 4, count);
      files[c->file].position += count;
    }
    offline(c->volume);
    if (op == F_OPEN)
      files[c->file].live = 0;
    response(c, SYS_EIO);
    return;
  }
  if (op == F_OPEN) {
    File *f = &files[c->file];
    if (c->phase == OPEN_STAT) {
      if (status == -5 && (f->flags & F_CREATE_FLAG)) {
        c->phase = OPEN_CREATE;
        c->state = QUEUED;
        return;
      }
      if (status) {
        f->live = 0;
        response(c, error_code(status));
        return;
      }
      if (work[145] & 1) {
        f->live = 0;
        response(c, SYS_EISDIR);
        return;
      }
      if ((f->flags & (F_WRITE_FLAG | F_TRUNCATE_FLAG)) ==
          (F_WRITE_FLAG | F_TRUNCATE_FLAG)) {
        c->phase = OPEN_TRUNCATE;
        c->state = QUEUED;
        return;
      }
    } else if (status) {
      f->live = 0;
      response(c, error_code(status));
      return;
    }
    publish_file(c);
    return;
  }
  if (status) {
    response(c, error_code(status));
    return;
  }
  if (op == F_CHDIR) {
    if (!(work[145] & 1)) {
      response(c, SYS_ENOTDIR);
      return;
    }
    strcpy(path, (char *)c->packet + 16);
    response(c, cwd_set(c->pid, c->volume));
    return;
  }
  if (op == F_READ || op == F_WRITE)
    files[c->file].position += count;
  memcpy(c->packet + 144, work + 144, 256);
  mlos_put_u16(c->packet + 4, count);
  memcpy(c->packet + 8, work + 8, 4);
  response(c, 0);
}
static int start_volume(u8 v) {
  const char *name = v ? "fs1" : "fs0";
  const char *image = v ? "fs1.mlx" : "fs0.mlx";
  int pid, i, r;
  pid = kspawn(image, 0, 0, 0);
  if (pid < 0)
    return pid;
  volumes[v].pid = (u16)pid;
  for (i = 0; i < 3000; i++) {
    r = kconnect(name, &volumes[v].tx, &volumes[v].rx);
    if (!r) {
      volumes[v].online = 1;
      volumes[v].generation++;
      publish_volume(v);
      volumes[v].active = -1;
      return 0;
    }
    ksleep(1);
  }
  return SYS_EIO;
}
/* Wait only on work this pass could not finish. At most listener + 3 clients
   + 2 worker endpoints. Mount/discovery retains its bounded one-tick retry
   until the worker has registered its listener (no service-registry wait ABI). */
static void wait_for_work(void) {
  u8 handles[16], args[8], i, v, count = 0, space = 0;
  for (i = 0; i < CLIENTS; i++) {
    Client *c = &clients[i];
    if (!c->used) {
      space = 1;
    } else if (c->state == IDLE || c->state == RESPONSE) {
      mlos_put_u16(handles + 2 * count++, c->state == IDLE ? c->rx : c->tx);
    }
  }
  if (space)
    mlos_put_u16(handles + 2 * count++, listener);
  for (v = 0; v < DRIVES; v++) {
    if (volumes[v].starting) {
      ksleep(1);
      return;
    }
    if (!volumes[v].online)
      continue;
    if (volumes[v].active >= 0) {
      mlos_put_u16(handles + 2 * count++, volumes[v].rx);
    } else {
      for (i = 0; i < CLIENTS; i++)
        if (clients[i].used && clients[i].state == QUEUED && clients[i].volume == v) {
          mlos_put_u16(handles + 2 * count++, volumes[v].tx);
          break;
        }
    }
  }
  mlos_put_u16(args, (u16)handles);
  args[2] = count;
  args[3] = 0;
  put32(args + 4, 0);
  mlos_call(SYS_WAIT_ANY, args);
}
int main(void) {
  u8 i, v;
  int r;
  u16 tx, rx;
  mlos_call(SYS_FS_REGISTER, 0);
  for (v = 0; v < DRIVES; v++) {
    volumes[v].active = -1;
    volumes[v].generation = 1;
  }
  if (start_volume(0))
    kexit(125);
  listener = (u16)klisten("fs");
  if (kerror((int)listener))
    kexit(125);
  for (;;) {
    for (i = 0; i < CLIENTS; i++)
      if (!clients[i].used) {
        u8 args[4], out[4];
        mlos_put_u16(args, listener);
        mlos_put_u16(args + 2, (u16)out);
        r = mlos_call(SYS_ACCEPT, args);
        if (!r) {
          tx = get16(out);
          rx = get16(out + 2);
          clients[i].tx = tx;
          clients[i].rx = rx;
          clients[i].pid = (u16)kword(SYS_PEER, rx);
          clients[i].used = 1;
          clients[i].state = IDLE;
        }
        break;
      }
    for (v = 0; v < DRIVES; v++)
      mount_progress(v);
    for (v = 0; v < DRIVES; v++)
      if (volumes[v].online && volumes[v].active >= 0) {
        r = rawrecv(volumes[v].rx, work);
        if (r == 400) {
          i = (u8)volumes[v].active;
          volumes[v].active = -1;
          complete(&clients[i]);
        } else if (r == 0 || r == SYS_EPIPE) {
          i = (u8)volumes[v].active;
          volumes[v].active = -1;
          offline(v);
          response(&clients[i], SYS_EIO);
        }
      }
    for (i = 0; i < CLIENTS; i++)
      if (clients[i].used) {
        Client *c = &clients[i];
        if (c->state == RESPONSE) {
          r = rawsend(c->tx, c->packet);
          if (r == 400)
            c->state = IDLE;
          else if (r != SYS_EAGAIN)
            disconnect(c);
        }
        if (c->state == IDLE) {
          r = rawrecv(c->rx, c->packet);
          if (r == 400)
            prepare(c);
          else if (r == 0)
            disconnect(c);
        }
        if (c->state == QUEUED) {
          if (!volumes[c->volume].online) {
            if (c->packet[0] == F_OPEN)
              files[c->file].live = 0;
            response(c, SYS_EIO);
          } else if (volumes[c->volume].active < 0)
            dispatch(c, i);
        }
      }
    wait_for_work();
  }
  return 0;
}
