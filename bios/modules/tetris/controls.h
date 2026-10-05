#ifndef MICROLIND_TETRIS_CONTROLS_H
#define MICROLIND_TETRIS_CONTROLS_H
#include "game.h"

#define TG_LEFT 1
#define TG_RIGHT 2
#define TG_ROTATE 4
#define TG_SOFT 8
#define TG_HARD 16
#define TG_PAUSE 32

typedef struct {
    int16_t horizontal;
    uint8_t previous, repeat, down_repeat, chord, up_armed, cancelled;
} TetrisInput;

void tetris_input_reset(TetrisInput *input, uint8_t held);
/* joy uses BIOS pressed bits: up=1, down=2, left=4, right=8, button=16.
 * Call once per 10 ms tick. The pause chord consumes the up-release drop. */
uint8_t tetris_input_tick(TetrisInput *input, uint8_t joy);
#endif
