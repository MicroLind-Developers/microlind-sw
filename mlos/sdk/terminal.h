#ifndef MLOS_TERMINAL_H
#define MLOS_TERMINAL_H
#include "mlos.h"
#define KEY_UP 256
#define KEY_DOWN 257
#define KEY_RIGHT 258
#define KEY_LEFT 259
#define KEY_HOME 260
#define KEY_END 261
#define KEY_INSERT 262
#define KEY_DELETE 263
#define KEY_PAGE_UP 264
#define KEY_PAGE_DOWN 265
#define KEY_F1 272
#define KEY_UNKNOWN 511
int term_key(void);
int term_mode(u8 raw);
int term_position(u8 row, u8 column);
int term_clear(void);
int term_reverse(u8 on);
int term_cursor(u8 visible);
#endif
