/* The same semantic tests run on the host and as a CMOC RAM application. */
#include "game.h"
#ifndef TETRIS_TARGET
#include <stdio.h>
#else
extern void diag_putc(unsigned char value);
#endif

static TetrisGame a, b;
static uint8_t expected[TETRIS_HEIGHT][TETRIS_WIDTH];
static uint16_t failures, checks;

static void text(const char *message)
{
#ifdef TETRIS_TARGET
    while (*message) diag_putc(*message++);
#else
    fputs(message, stdout);
#endif
}

static uint8_t check(uint8_t condition, uint16_t line)
{
    ++checks;
    if (!condition) {
        ++failures;
        text("Tetris rules FAIL at line ");
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
    return condition;
}

#define CHECK(expression) do { if (!check((expression) != 0, __LINE__)) return; } while (0)

static void empty(TetrisGame *game)
{
    uint8_t row, column;
    for (row = 0; row < TETRIS_HEIGHT; ++row)
        for (column = 0; column < TETRIS_WIDTH; ++column)
            game->board[row][column] = 0;
}

static uint16_t settled(const TetrisGame *game)
{
    uint8_t row, column;
    uint16_t count = 0;
    for (row = 0; row < TETRIS_HEIGHT; ++row)
        for (column = 0; column < TETRIS_WIDTH; ++column)
            if (game->board[row][column]) ++count;
    return count;
}

static void setup_clear(uint8_t count)
{
    uint8_t row, column;
    empty(&a);
    for (row = TETRIS_HEIGHT - count; row < TETRIS_HEIGHT; ++row)
        for (column = 0; column < TETRIS_WIDTH; ++column)
            a.board[row][column] = column == 5 ? 0 : TETRIS_J;
    a.piece = TETRIS_I;
    a.rotation = 1;
    a.x = 3;
    a.y = 16;
}

static void initial_and_bag(void)
{
    uint8_t bag, i, used;
    tetris_new(&a, 1);
    CHECK(a.score == 0 && a.lines == 0 && a.level == 1 && !a.over);
    CHECK(a.x == 3 && a.y == 0 && a.rotation == 0 && settled(&a) == 0);
    CHECK(a.piece != a.next);
    for (bag = 0; bag < 12; ++bag) {
        used = 0;
        for (i = 0; i < TETRIS_PIECES; ++i) {
            CHECK(a.piece >= 1 && a.piece <= TETRIS_PIECES);
            CHECK(!(used & (1U << a.piece)));
            used |= (uint8_t)(1U << a.piece);
            CHECK(tetris_hard_drop(&a) & TETRIS_LOCKED);
            empty(&a);
            CHECK(!a.over);
        }
        CHECK(used == 0xFE);
    }
    tetris_new(&a, 0);
    tetris_new(&b, 1);
    CHECK(a.piece == b.piece && a.next == b.next && a.random == b.random);
}

static void deterministic_sequence(void)
{
    uint8_t i;
    tetris_new(&a, 0xBEEF);
    tetris_new(&b, 0xBEEF);
    for (i = 0; i < 80; ++i) {
        CHECK(a.piece == b.piece && a.next == b.next && a.random == b.random);
        CHECK(tetris_hard_drop(&a) == tetris_hard_drop(&b));
        empty(&a);
        empty(&b);
    }
}

static void rotation_geometry(void)
{
    uint8_t piece, rotation, row, column, count, size;
    uint16_t mask, rotated, bit;
    tetris_new(&a, 12);
    CHECK(tetris_mask(0, 0) == 0 && tetris_mask(8, 0) == 0);
    for (piece = 1; piece <= TETRIS_PIECES; ++piece) {
        size = piece == TETRIS_I ? 4 : 3;
        for (rotation = 0; rotation < 4; ++rotation) {
            mask = tetris_mask(piece, rotation);
            count = 0;
            rotated = 0;
            for (row = 0; row < size; ++row) {
                for (column = 0; column < size; ++column) {
                    bit = (uint16_t)(1U << (row * 4 + column));
                    if (mask & bit) {
                        ++count;
                        rotated |= (uint16_t)(1U << (column * 4 + size - 1 - row));
                    }
                }
            }
            CHECK(count == 4);
            if (piece == TETRIS_O) CHECK(mask == tetris_mask(piece, rotation + 1));
            else CHECK(rotated == tetris_mask(piece, rotation + 1));
        }
        a.piece = piece;
        a.rotation = 0;
        a.x = 3;
        a.y = 3;
        for (rotation = 0; rotation < 4; ++rotation) CHECK(tetris_rotate(&a) == TETRIS_MOVED);
        CHECK(a.rotation == 0 && settled(&a) == 0);
    }
}

static void walls_and_blocked_rotation(void)
{
    tetris_new(&a, 12);
    a.piece = TETRIS_I;
    a.rotation = 1;
    a.x = -2;
    a.y = 4;
    CHECK(tetris_move(&a, -1) == 0 && a.x == -2);
    CHECK(tetris_rotate(&a) == 0 && a.rotation == 1 && a.x == -2);
    CHECK(tetris_move(&a, 1) == TETRIS_MOVED && a.x == -1);
    CHECK(tetris_move(&a, 0) == 0 && tetris_move(&a, 2) == 0);
    a.rotation = 0;
    a.x = 6;
    CHECK(tetris_move(&a, 1) == 0 && a.x == 6);
    a.x = 3;
    a.y = 17;
    CHECK(tetris_rotate(&a) == 0 && a.rotation == 0);
}

static void obstacle_and_immediate_lock(void)
{
    uint8_t preview, events;
    tetris_new(&a, 12);
    a.piece = TETRIS_O;
    a.x = 3;
    a.y = 17;
    a.board[19][4] = TETRIS_J;
    preview = a.next;
    events = tetris_soft_drop(&a);
    CHECK(events == TETRIS_LOCKED);
    CHECK(a.piece == preview && a.y == 0 && a.gravity == 0);
    CHECK(settled(&a) == 5 && a.board[19][4] == TETRIS_J);
    CHECK(a.board[17][4] == TETRIS_O && a.board[18][5] == TETRIS_O);
    CHECK(a.score == 0);
}

static void drop_points_and_overlay(void)
{
    uint8_t preview;
    tetris_new(&a, 12);
    a.piece = TETRIS_O;
    CHECK(tetris_cell(&a, 4, 0) == TETRIS_O && tetris_cell(&a, 5, 1) == TETRIS_O);
    CHECK(tetris_cell(&a, 10, 0) == 0 && tetris_cell(&a, 0, 20) == 0);
    CHECK(settled(&a) == 0);
    CHECK(tetris_soft_drop(&a) == TETRIS_MOVED && a.score == 1 && a.y == 1);
    preview = a.next;
    CHECK(tetris_hard_drop(&a) == (TETRIS_MOVED | TETRIS_LOCKED));
    CHECK(a.score == 35 && a.piece == preview && settled(&a) == 4);
    CHECK(a.board[18][4] == TETRIS_O && a.board[19][5] == TETRIS_O);
}

static void line_scores(void)
{
    static const uint16_t points[5] = {0, 40, 100, 300, 1200};
    uint8_t count, events;
    for (count = 1; count <= 4; ++count) {
        tetris_new(&a, 12);
        setup_clear(count);
        events = tetris_hard_drop(&a);
        CHECK(events == (TETRIS_LOCKED | TETRIS_CLEARED));
        CHECK(a.last_clear == count && a.lines == count && a.score == points[count]);
        CHECK(settled(&a) == 4 - count);
        CHECK(a.board[0][5] == 0 && a.board[19][5] == (count == 4 ? 0 : TETRIS_I));
    }
}

static void nonadjacent_compaction(void)
{
    uint8_t row, column;
    tetris_new(&a, 12);
    a.piece = TETRIS_O;
    a.x = 3;
    a.y = 18;
    for (column = 0; column < TETRIS_WIDTH; ++column) {
        a.board[10][column] = TETRIS_T;
        a.board[12][column] = TETRIS_L;
    }
    a.board[9][0] = TETRIS_Z;
    a.board[11][1] = TETRIS_S;
    for (row = 0; row < TETRIS_HEIGHT; ++row)
        for (column = 0; column < TETRIS_WIDTH; ++column)
            expected[row][column] = 0;
    expected[11][0] = TETRIS_Z;
    expected[12][1] = TETRIS_S;
    expected[18][4] = expected[18][5] = TETRIS_O;
    expected[19][4] = expected[19][5] = TETRIS_O;
    CHECK(tetris_soft_drop(&a) == (TETRIS_LOCKED | TETRIS_CLEARED));
    CHECK(a.last_clear == 2 && a.score == 100);
    for (row = 0; row < TETRIS_HEIGHT; ++row)
        for (column = 0; column < TETRIS_WIDTH; ++column)
            CHECK(a.board[row][column] == expected[row][column]);
}

static void levels_and_gravity(void)
{
    uint8_t tick;
    tetris_new(&a, 12);
    a.piece = TETRIS_O;
    CHECK(tetris_gravity_ticks(&a) == 80);
    for (tick = 0; tick < 79; ++tick) CHECK(tetris_tick(&a) == 0);
    CHECK(a.y == 0 && a.score == 0);
    CHECK(tetris_tick(&a) == TETRIS_MOVED && a.y == 1 && a.score == 0);
    a.y = 18;
    a.gravity = 79;
    CHECK(tetris_tick(&a) == TETRIS_LOCKED && a.gravity == 0);
    a.lines = 9;
    setup_clear(1);
    CHECK(tetris_hard_drop(&a) & TETRIS_CLEARED);
    CHECK(a.lines == 10 && a.level == 2 && a.score == 40);
    CHECK(tetris_gravity_ticks(&a) == 72);
    setup_clear(1);
    CHECK(tetris_hard_drop(&a) & TETRIS_CLEARED);
    CHECK(a.score == 120 && a.lines == 11);
    a.level = 9;
    CHECK(tetris_gravity_ticks(&a) == 16);
    a.level = 10;
    CHECK(tetris_gravity_ticks(&a) == 8);
    a.level = 6554;
    CHECK(tetris_gravity_ticks(&a) == 8);
}

static void top_out_and_finished_actions(void)
{
    uint8_t column;
    tetris_new(&a, 12);
    a.piece = TETRIS_O;
    a.y = 18;
    for (column = 3; column <= 6; ++column)
        a.board[0][column] = a.board[1][column] = TETRIS_Z;
    CHECK(tetris_soft_drop(&a) == (TETRIS_LOCKED | TETRIS_OVER));
    CHECK(a.over && settled(&a) == 12);
    CHECK(tetris_move(&a, 1) == 0 && tetris_rotate(&a) == 0);
    CHECK(tetris_hard_drop(&a) == 0 && tetris_soft_drop(&a) == 0 && tetris_tick(&a) == 0);
    CHECK(a.score == 0 && settled(&a) == 12);
}

static void wide_and_saturating_scores(void)
{
    tetris_new(&a, 12);
    a.lines = 99;
    a.level = 10;
    a.score = 65530UL;
    setup_clear(4);
    CHECK(tetris_hard_drop(&a) & TETRIS_CLEARED);
    CHECK(a.score == 77530UL && a.lines == 103 && a.level == 11);
    a.score = 0xFFFFFFFEUL;
    a.piece = TETRIS_O;
    a.x = 3;
    a.y = 0;
    empty(&a);
    CHECK(tetris_hard_drop(&a) & TETRIS_LOCKED);
    CHECK(a.score == 0xFFFFFFFFUL);
    a.lines = 65534U;
    a.level = 6554U;
    setup_clear(4);
    CHECK(tetris_hard_drop(&a) & TETRIS_CLEARED);
    CHECK(a.lines == 65535U && a.level == 6554U && a.score == 0xFFFFFFFFUL);
}

int main(void)
{
    initial_and_bag();
    deterministic_sequence();
    rotation_geometry();
    walls_and_blocked_rotation();
    obstacle_and_immediate_lock();
    drop_points_and_overlay();
    line_scores();
    nonadjacent_compaction();
    levels_and_gravity();
    top_out_and_finished_actions();
    wide_and_saturating_scores();
    if (failures) return 1;
    text("Tetris rules PASS\r\n");
#ifndef TETRIS_TARGET
    printf("%u checks; state %lu bytes\n", checks, (unsigned long)sizeof(TetrisGame));
#endif
    return 0;
}
