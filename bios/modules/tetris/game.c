#include "game.h"

/* Bit 4*y+x describes local cell (x,y). The I uses a 4x4 rotation box;
 * the five non-square, non-I pieces use a 3x3 box. O stays in place. */
static const uint16_t masks[TETRIS_PIECES][4] = {
    {0x00F0, 0x4444, 0x0F00, 0x2222},
    {0x0066, 0x0066, 0x0066, 0x0066},
    {0x0072, 0x0262, 0x0270, 0x0232},
    {0x0036, 0x0462, 0x0360, 0x0231},
    {0x0063, 0x0264, 0x0630, 0x0132},
    {0x0071, 0x0226, 0x0470, 0x0322},
    {0x0074, 0x0622, 0x0170, 0x0223}
};

uint16_t tetris_mask(uint8_t piece, uint8_t rotation)
{
    if (!piece || piece > TETRIS_PIECES) return 0;
    return masks[piece - 1][rotation & 3];
}

static uint16_t random_next(TetrisGame *game)
{
    uint16_t value = game->random;
    game->random = (uint16_t)((value >> 1) ^ ((value & 1) ? 0xB400U : 0U));
    return game->random;
}

static uint8_t bag_take(TetrisGame *game)
{
    uint8_t i, index, temp;
    if (game->bag_index == TETRIS_PIECES) {
        for (i = 0; i < TETRIS_PIECES; ++i) game->bag[i] = i + 1;
        for (i = TETRIS_PIECES - 1; i; --i) {
            index = (uint8_t)(random_next(game) % (i + 1));
            temp = game->bag[i];
            game->bag[i] = game->bag[index];
            game->bag[index] = temp;
        }
        game->bag_index = 0;
    }
    return game->bag[game->bag_index++];
}

static uint8_t fits(const TetrisGame *game, int16_t x, int16_t y, uint8_t rotation)
{
    uint16_t mask = tetris_mask(game->piece, rotation);
    uint8_t row, column;
    int16_t bx, by;
    for (row = 0; row < 4; ++row) {
        for (column = 0; column < 4; ++column) {
            if (mask & 1) {
                bx = x + column;
                by = y + row;
                if (bx < 0 || bx >= TETRIS_WIDTH || by < 0 || by >= TETRIS_HEIGHT)
                    return 0;
                if (game->board[by][bx]) return 0;
            }
            mask >>= 1;
        }
    }
    return 1;
}

static uint8_t spawn(TetrisGame *game)
{
    game->piece = game->next;
    game->next = bag_take(game);
    game->rotation = 0;
    game->x = 3;
    game->y = 0;
    game->gravity = 0;
    if (!fits(game, game->x, game->y, 0)) {
        game->over = 1;
        return TETRIS_OVER;
    }
    return 0;
}

void tetris_new(TetrisGame *game, uint16_t seed)
{
    uint8_t row, column;
    for (row = 0; row < TETRIS_HEIGHT; ++row)
        for (column = 0; column < TETRIS_WIDTH; ++column)
            game->board[row][column] = 0;
    game->score = 0;
    game->lines = 0;
    game->level = 1;
    game->random = seed ? seed : 1U;
    game->bag_index = TETRIS_PIECES;
    game->over = 0;
    game->last_clear = 0;
    game->next = bag_take(game);
    spawn(game);
}

static void add_score(TetrisGame *game, uint32_t points)
{
    if (game->score > 0xFFFFFFFFUL - points) game->score = 0xFFFFFFFFUL;
    else game->score += points;
}

static uint8_t clear_lines(TetrisGame *game)
{
    int16_t source, destination = TETRIS_HEIGHT - 1;
    uint8_t column, full, cleared = 0;
    for (source = TETRIS_HEIGHT - 1; source >= 0; --source) {
        full = 1;
        for (column = 0; column < TETRIS_WIDTH; ++column)
            if (!game->board[source][column]) full = 0;
        if (full) ++cleared;
        else {
            if (destination != source)
                for (column = 0; column < TETRIS_WIDTH; ++column)
                    game->board[destination][column] = game->board[source][column];
            --destination;
        }
    }
    while (destination >= 0) {
        for (column = 0; column < TETRIS_WIDTH; ++column)
            game->board[destination][column] = 0;
        --destination;
    }
    return cleared;
}

static uint8_t lock(TetrisGame *game)
{
    static const uint16_t points[5] = {0, 40, 100, 300, 1200};
    uint16_t mask = tetris_mask(game->piece, game->rotation);
    uint8_t row, column, cleared, events = TETRIS_LOCKED;
    for (row = 0; row < 4; ++row) {
        for (column = 0; column < 4; ++column) {
            if (mask & 1) game->board[game->y + row][game->x + column] = game->piece;
            mask >>= 1;
        }
    }
    cleared = clear_lines(game);
    game->last_clear = cleared;
    if (cleared) {
        add_score(game, (uint32_t)points[cleared] * game->level);
        if (game->lines > 65535U - cleared) game->lines = 65535U;
        else game->lines += cleared;
        game->level = game->lines / 10 + 1;
        events |= TETRIS_CLEARED;
    }
    return events | spawn(game);
}

uint8_t tetris_move(TetrisGame *game, int16_t direction)
{
    if (game->over || (direction != -1 && direction != 1)) return 0;
    if (!fits(game, game->x + direction, game->y, game->rotation)) return 0;
    game->x += direction;
    return TETRIS_MOVED;
}

uint8_t tetris_rotate(TetrisGame *game)
{
    uint8_t rotation = (game->rotation + 1) & 3;
    if (game->over || !fits(game, game->x, game->y, rotation)) return 0;
    game->rotation = rotation;
    return TETRIS_MOVED;
}

static uint8_t drop(TetrisGame *game, uint8_t soft)
{
    if (game->over) return 0;
    if (!fits(game, game->x, game->y + 1, game->rotation)) return lock(game);
    ++game->y;
    if (soft) add_score(game, 1);
    return TETRIS_MOVED;
}

uint8_t tetris_soft_drop(TetrisGame *game)
{
    return drop(game, 1);
}

uint8_t tetris_hard_drop(TetrisGame *game)
{
    uint8_t distance = 0;
    if (game->over) return 0;
    while (fits(game, game->x, game->y + 1, game->rotation)) {
        ++game->y;
        ++distance;
    }
    add_score(game, (uint32_t)distance * 2);
    return lock(game) | (distance ? TETRIS_MOVED : 0);
}

uint8_t tetris_gravity_ticks(const TetrisGame *game)
{
    if (game->level >= 10) return 8;
    return (uint8_t)(80 - (game->level - 1) * 8);
}

uint8_t tetris_tick(TetrisGame *game)
{
    if (game->over) return 0;
    if (++game->gravity < tetris_gravity_ticks(game)) return 0;
    game->gravity = 0;
    return drop(game, 0);
}

uint8_t tetris_cell(const TetrisGame *game, uint8_t x, uint8_t y)
{
    int16_t px = (int16_t)x - game->x;
    int16_t py = (int16_t)y - game->y;
    if (x >= TETRIS_WIDTH || y >= TETRIS_HEIGHT) return 0;
    if (!game->over && px >= 0 && px < 4 && py >= 0 && py < 4 &&
        (tetris_mask(game->piece, game->rotation) & (1U << (py * 4 + px))))
        return game->piece;
    return game->board[y][x];
}
