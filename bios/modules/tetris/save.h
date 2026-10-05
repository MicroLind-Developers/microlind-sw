#ifndef MICROLIND_TETRIS_SAVE_H
#define MICROLIND_TETRIS_SAVE_H
#include "game.h"
#define TG_RECORD_BYTES 64
#define TG_RECORD_STRIDE 512
#define TG_SAVE_BYTES (TG_RECORD_STRIDE + TG_RECORD_BYTES)

typedef struct {
    uint32_t scores[5];
    uint32_t sequence;
    uint8_t sound, slot, valid;
} TetrisSave;

void tetris_save_defaults(TetrisSave *save);
/* Decode each complete record independently; a valid first record survives
 * a truncated/corrupt second one. Sequence comparison handles wraparound. */
uint8_t tetris_save_decode(TetrisSave *save, const uint8_t *bytes, uint16_t length);
void tetris_save_encode(const TetrisSave *save, uint8_t *record);
/* Call only after a complete, verified write to the other record slot. */
void tetris_save_committed(TetrisSave *save);
uint8_t tetris_high_score(TetrisSave *save, uint32_t score);
#endif
