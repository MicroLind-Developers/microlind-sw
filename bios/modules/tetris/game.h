#ifndef MICROLIND_TETRIS_GAME_H
#define MICROLIND_TETRIS_GAME_H

#ifdef TETRIS_TARGET
#include "integer.h"
#else
#include <stdint.h>
#endif

#define TETRIS_WIDTH 10
#define TETRIS_HEIGHT 20
#define TETRIS_PIECES 7
#define TETRIS_I 1
#define TETRIS_O 2
#define TETRIS_T 3
#define TETRIS_S 4
#define TETRIS_Z 5
#define TETRIS_J 6
#define TETRIS_L 7

#define TETRIS_MOVED 1
#define TETRIS_LOCKED 2
#define TETRIS_CLEARED 4
#define TETRIS_OVER 8

/* Board cells are 0 (empty) or a piece ID. Active cells are an overlay; only
 * locking changes the settled board. All state lives in the caller's object.
 * No allocation, I/O, or interrupt access occurs in this module. */
typedef struct {
    uint8_t board[TETRIS_HEIGHT][TETRIS_WIDTH];
    uint32_t score;
    uint16_t lines;
    uint16_t level;
    uint16_t random;
    int16_t x, y;
    uint8_t piece, rotation, next, over;
    uint8_t bag[TETRIS_PIECES];
    uint8_t bag_index, gravity;
    uint8_t last_clear;
} TetrisGame;

void tetris_new(TetrisGame *game, uint16_t seed);
uint16_t tetris_mask(uint8_t piece, uint8_t rotation);
uint8_t tetris_cell(const TetrisGame *game, uint8_t x, uint8_t y);
uint8_t tetris_move(TetrisGame *game, int16_t direction);
uint8_t tetris_rotate(TetrisGame *game);
/* Drop returns event bits; a blocked drop locks immediately and spawns the
 * preview piece. Hard drop awards two points/row; soft drop one/row. */
uint8_t tetris_soft_drop(TetrisGame *game);
uint8_t tetris_hard_drop(TetrisGame *game);
uint8_t tetris_tick(TetrisGame *game);
/* One tick is 10 ms. Gravity starts at 80 ticks, falls by 8 per level, and
 * reaches its 8-tick minimum at level 10. */
uint8_t tetris_gravity_ticks(const TetrisGame *game);

#endif
