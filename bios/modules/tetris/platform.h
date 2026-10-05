#ifndef MICROLIND_TETRIS_PLATFORM_H
#define MICROLIND_TETRIS_PLATFORM_H
#include "game.h"
/* CMOC stack-argument wrappers. Display routines return 0 or -1. */
uint16_t tg_platform_init(void);
void tg_platform_done(void);
uint16_t tg_tick(void);
uint16_t tg_joy(void);
int16_t tg_serial(void);
void tg_putc(uint16_t value);
int16_t tg_vram(uint16_t address, uint16_t value);
int16_t tg_vram_read(uint16_t address);
int16_t tg_cell(uint16_t address, uint16_t glyph, uint16_t attribute);
int16_t tg_reg(uint16_t index, uint16_t value);
int16_t tg_reg_read(uint16_t index);
int16_t tg_clear(void);
void tg_sound(uint16_t enabled);
void tg_effect(uint16_t effect);
#endif
