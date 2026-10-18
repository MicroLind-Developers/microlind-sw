/* Shared Latin1/7-bit CSI key decoder. At most8 sequence bytes and40 ticks
   between Escape and completion. Unsupported/malformed sequences are consumed
   as KEY_UNKNOWN. Ordinary bytes include Latin1 C1; they are never CSI
   controls. */
#include "terminal.h"
#include <cmoc.h>
static u32 ticks(void) {
  u8 p[4];
  kword(SYS_TICKS, (u16)p);
  return get32(p);
}
int term_mode(u8 raw) {
  u8 p[4];
  p[0] = 2;
  p[1] = raw;
  mlos_put_u16(p + 2, 0);
  return mlos_call(SYS_TTY_CONTROL, p);
}
static int keybyte(void) {
  int c;
  for (;;) {
    c = mlos_call(SYS_GETC, 0);
    if (c != SYS_EAGAIN)
      return c;
    ksleep(1);
  }
}
int term_key(void) {
  int c = keybyte(), kind, i, value = 0;
  u32 deadline;
  if (c != 27)
    return c;
  deadline = ticks() + 40UL;
  kind = 0;
  for (i = 0; i < 8; i++) {
    for (;;) {
      c = mlos_call(SYS_GETC, 0);
      if (c != SYS_EAGAIN)
        break;
      if ((long)(ticks() - deadline) >= 0)
        return i ? KEY_UNKNOWN : 27;
      ksleep(1);
    }
    if (c < 0)
      return c;
    if (i == 0) {
      if (c == '[')
        kind = 1;
      else if (c == 'O')
        kind = 2;
      else
        return KEY_UNKNOWN;
      continue;
    }
    if (c >= '0' && c <= '9' && kind == 1) {
      value = value * 10 + c - '0';
      if (value > 999)
        return KEY_UNKNOWN;
      continue;
    }
    if (c == 'A')
      return KEY_UP;
    if (c == 'B')
      return KEY_DOWN;
    if (c == 'C')
      return KEY_RIGHT;
    if (c == 'D')
      return KEY_LEFT;
    if (c == 'H')
      return KEY_HOME;
    if (c == 'F')
      return KEY_END;
    if (kind == 2 && c >= 'P' && c <= 'S')
      return KEY_F1 + c - 'P';
    if (c == '~' && kind == 1) {
      switch (value) {
      case 1:
      case 7:
        return KEY_HOME;
      case 4:
      case 8:
        return KEY_END;
      case 2:
        return KEY_INSERT;
      case 3:
        return KEY_DELETE;
      case 5:
        return KEY_PAGE_UP;
      case 6:
        return KEY_PAGE_DOWN;
      case 11:
      case 12:
      case 13:
      case 14:
      case 15:
        return KEY_F1 + value - 11;
      case 17:
      case 18:
      case 19:
      case 20:
      case 21:
        return KEY_F1 + value - 12;
      case 23:
      case 24:
        return KEY_F1 + value - 13;
      default:
        return KEY_UNKNOWN;
      }
    }
    return KEY_UNKNOWN;
  }
  return KEY_UNKNOWN;
}
int term_position(u8 row, u8 column) {
  char p[16];
  sprintf(p, "\033[%u;%uH", (u16)row, (u16)column);
  return kwrite(p, strlen(p));
}
int term_clear(void) { return kwrite("\033[2J\033[H", 7); }
int term_reverse(u8 on) { return kwrite(on ? "\033[7m" : "\033[0m", 4); }
int term_cursor(u8 visible) {
  return kwrite(visible ? "\033[?25h" : "\033[?25l", 6);
}
