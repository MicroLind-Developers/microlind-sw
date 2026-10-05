/* Shared host/CMOC tests for timing decisions and the portable save format. */
#include "controls.h"
#include "save.h"
#ifndef TETRIS_TARGET
#include <stdio.h>
#else
extern void diag_putc(unsigned char value);
#endif

static TetrisInput input;
static TetrisSave save, decoded;
static uint8_t bytes[TG_SAVE_BYTES];
static uint16_t failures, checks;

static void text(const char *value)
{
#ifdef TETRIS_TARGET
    while (*value) diag_putc(*value++);
#else
    fputs(value, stdout);
#endif
}

static uint8_t check(uint8_t result, uint16_t line)
{
    ++checks;
    if (!result) {
        ++failures;
        text("Tetris I/O FAIL at line ");
#ifdef TETRIS_TARGET
        {
            uint8_t i, digit;
            for (i = 0; i < 4; ++i) {
                digit = (uint8_t)((line >> 12) & 15);
                diag_putc(digit < 10 ? '0' + digit : 'A' + digit - 10);
                line <<= 4;
            }
        }
#else
        printf("%04X", line);
#endif
        text("\r\n");
    }
    return result;
}
#define CHECK(expression) do { if (!check((expression) != 0, __LINE__)) return; } while (0)

static void movement_repeat(void)
{
    uint8_t i;
    tetris_input_reset(&input, 0);
    CHECK(tetris_input_tick(&input, 4) == TG_LEFT);
    for (i = 0; i < 19; ++i) CHECK(tetris_input_tick(&input, 4) == 0);
    CHECK(tetris_input_tick(&input, 4) == TG_LEFT);
    for (i = 0; i < 5; ++i) CHECK(tetris_input_tick(&input, 4) == 0);
    CHECK(tetris_input_tick(&input, 4) == TG_LEFT);
    CHECK(tetris_input_tick(&input, 8) == TG_RIGHT);
    CHECK(tetris_input_tick(&input, 12) == 0);
    for (i = 0; i < 30; ++i) CHECK(tetris_input_tick(&input, 12) == 0);
    CHECK(tetris_input_tick(&input, 8) == TG_RIGHT);
    CHECK(tetris_input_tick(&input, 0) == 0);
    CHECK(tetris_input_tick(&input, 4) == TG_LEFT);
    tetris_input_reset(&input, 0);
    CHECK(tetris_input_tick(&input, 2) == TG_SOFT);
    for (i = 0; i < 5; ++i) CHECK(tetris_input_tick(&input, 2) == 0);
    CHECK(tetris_input_tick(&input, 2) == TG_SOFT);
    CHECK(tetris_input_tick(&input, 0) == 0);
}

static void edges_and_chords(void)
{
    uint8_t i;
    tetris_input_reset(&input, 0);
    CHECK(tetris_input_tick(&input, 16) == TG_ROTATE);
    for (i = 0; i < 60; ++i) CHECK(tetris_input_tick(&input, 16) == 0);
    CHECK(tetris_input_tick(&input, 0) == 0);
    CHECK(tetris_input_tick(&input, 16) == TG_ROTATE);
    tetris_input_reset(&input, 0);
    for (i = 0; i < 30; ++i) CHECK(tetris_input_tick(&input, 1) == 0);
    CHECK(tetris_input_tick(&input, 0) == TG_HARD);
    CHECK(tetris_input_tick(&input, 0) == 0);
    tetris_input_reset(&input, 0);
    for (i = 0; i < 49; ++i) CHECK(tetris_input_tick(&input, 17) == 0);
    CHECK(tetris_input_tick(&input, 17) == TG_PAUSE);
    for (i = 0; i < 60; ++i) CHECK(tetris_input_tick(&input, 17) == 0);
    CHECK(tetris_input_tick(&input, 0) == 0);
    tetris_input_reset(&input, 0);
    for (i = 0; i < 20; ++i) CHECK(tetris_input_tick(&input, 17) == 0);
    CHECK(tetris_input_tick(&input, 0) == TG_HARD);
    tetris_input_reset(&input, 0);
    for (i = 0; i < 30; ++i) CHECK(tetris_input_tick(&input, 17) == 0);
    CHECK(tetris_input_tick(&input, 1) == 0);
    for (i = 0; i < 30; ++i) CHECK(tetris_input_tick(&input, 17) == 0);
    CHECK(tetris_input_tick(&input, 0) == TG_HARD);
    tetris_input_reset(&input, 17);
    CHECK(tetris_input_tick(&input, 0) == 0);
}

static void save_roundtrip(void)
{
    uint16_t i;
    for (i = 0; i < TG_SAVE_BYTES; ++i) bytes[i] = 0;
    CHECK(!tetris_save_decode(&decoded, bytes, TG_SAVE_BYTES));
    CHECK(decoded.sound == 1 && !decoded.valid && decoded.sequence == 0);
    tetris_save_defaults(&save);
    tetris_save_encode(&save, bytes);
    CHECK(save.sequence == 0 && save.slot == 1 && !save.valid);
    CHECK(bytes[0] == 'T' && bytes[1] == 'E' && bytes[2] == 'T' && bytes[3] == '1');
    CHECK(bytes[60] == 0 && bytes[61] == 0 && bytes[62] == 1 && bytes[63] == 0x21);
    CHECK(tetris_save_decode(&decoded, bytes, TG_RECORD_BYTES));
    CHECK(decoded.sound == 1 && decoded.sequence == 1 && decoded.slot == 0);
    tetris_save_committed(&save);
    CHECK(save.sequence == 1 && save.slot == 0 && save.valid);
    save.sound = 0;
    CHECK(tetris_high_score(&save, 0xFEDCBA98UL));
    CHECK(tetris_high_score(&save, 70000UL));
    tetris_save_encode(&save, bytes + TG_RECORD_STRIDE);
    CHECK(tetris_save_decode(&decoded, bytes, TG_SAVE_BYTES));
    CHECK(decoded.sound == 0 && decoded.sequence == 2 && decoded.slot == 1);
    CHECK(decoded.scores[0] == 0xFEDCBA98UL && decoded.scores[1] == 70000UL);
    bytes[TG_RECORD_STRIDE + 6] ^= 1;
    CHECK(tetris_save_decode(&decoded, bytes, TG_SAVE_BYTES));
    CHECK(decoded.slot == 0 && decoded.sequence == 1 && decoded.sound == 1);
}

static void corruption_and_truncation(void)
{
    uint16_t i;
    tetris_save_defaults(&save);
    for (i = 0; i < TG_SAVE_BYTES; ++i) bytes[i] = 0;
    tetris_save_encode(&save, bytes);
    for (i = 0; i < TG_RECORD_BYTES; ++i) {
        bytes[i] ^= 1;
        CHECK(!tetris_save_decode(&decoded, bytes, TG_RECORD_BYTES));
        bytes[i] ^= 1;
    }
    for (i = 0; i < TG_RECORD_BYTES; ++i) CHECK(!tetris_save_decode(&decoded, bytes, i));
    for (i = TG_RECORD_BYTES; i < TG_SAVE_BYTES; ++i)
        CHECK(tetris_save_decode(&decoded, bytes, i) && decoded.slot == 0);
    /* Keep the additive checksum unchanged but break reserved/version fields. */
    bytes[5] = 0; bytes[32] = 1;
    CHECK(!tetris_save_decode(&decoded, bytes, TG_RECORD_BYTES));
    bytes[32] = 0; bytes[4] = 2;
    CHECK(!tetris_save_decode(&decoded, bytes, TG_RECORD_BYTES));
    tetris_save_encode(&save, bytes);
    /* Encode ascending scores with an independently adjusted checksum. */
    bytes[15] = 1; bytes[19] = 2; bytes[63] = 0x24;
    CHECK(!tetris_save_decode(&decoded, bytes, TG_RECORD_BYTES));
}

static void sequence_wrap_and_ties(void)
{
    tetris_save_defaults(&save);
    save.sequence = 0xFFFFFFFEUL;
    tetris_save_encode(&save, bytes);
    tetris_save_committed(&save);
    save.sound = 0;
    tetris_save_encode(&save, bytes + TG_RECORD_STRIDE);
    CHECK(tetris_save_decode(&decoded, bytes, TG_SAVE_BYTES));
    CHECK(decoded.sequence == 0 && decoded.slot == 1 && decoded.sound == 0);
    tetris_save_defaults(&save);
    tetris_save_encode(&save, bytes);
    save.sound = 0;
    tetris_save_encode(&save, bytes + TG_RECORD_STRIDE);
    CHECK(tetris_save_decode(&decoded, bytes, TG_SAVE_BYTES));
    CHECK(decoded.sequence == 1 && decoded.slot == 0 && decoded.sound == 1);
}

static void high_score_order(void)
{
    tetris_save_defaults(&save);
    CHECK(!tetris_high_score(&save, 0));
    CHECK(tetris_high_score(&save, 40)); CHECK(tetris_high_score(&save, 10));
    CHECK(tetris_high_score(&save, 30)); CHECK(tetris_high_score(&save, 20));
    CHECK(tetris_high_score(&save, 50));
    CHECK(save.scores[0] == 50 && save.scores[1] == 40 && save.scores[2] == 30 &&
          save.scores[3] == 20 && save.scores[4] == 10);
    CHECK(tetris_high_score(&save, 40));
    CHECK(save.scores[0] == 50 && save.scores[1] == 40 && save.scores[2] == 40 &&
          save.scores[3] == 30 && save.scores[4] == 20);
    CHECK(!tetris_high_score(&save, 10));
    CHECK(tetris_high_score(&save, 0xFFFFFFFFUL) && save.scores[0] == 0xFFFFFFFFUL);
}

int main(void)
{
    movement_repeat(); edges_and_chords(); save_roundtrip();
    corruption_and_truncation(); sequence_wrap_and_ties(); high_score_order();
    if (failures) return 1;
    text("Tetris I/O PASS\r\n");
#ifndef TETRIS_TARGET
    printf("%u checks\n", checks);
#endif
    return 0;
}
