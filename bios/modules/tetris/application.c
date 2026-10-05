#include "game.h"
#include "controls.h"
#include "save.h"
#include "platform.h"
#include "filesystem.h"

static TetrisGame game;
static TetrisInput input;
static TetrisSave saved;
static FsRequest request;
static uint8_t save_bytes[TG_SAVE_BYTES], record[TG_RECORD_BYTES];
static uint8_t cache[TETRIS_HEIGHT][TETRIS_WIDTH], glyph[16];
static uint8_t display_ok, display_saved, old_cursor, old_color;
static uint8_t paused, selection, exiting, dirty, score_recorded, save_dirty, save_error;
static uint8_t menu_previous, menu_repeat, menu_wait_release;
static int16_t menu_direction;
static uint32_t shown_score, shown_high[5];
static uint16_t shown_level, shown_lines;
static uint8_t shown_next, shown_menu, shown_error, first_draw;
static const uint8_t colors[8] = {0, 7, 13, 11, 5, 9, 3, 12};
static const char *menu_items[4] = {"Resume", "New Game", "Sound", "Exit"};

static void serial_text(const char *text)
{
    while (*text) tg_putc((uint8_t)*text++);
}

static void character(uint16_t address, uint8_t value, uint8_t color)
{
    if (display_ok && (tg_vram(address, value) || tg_vram(address + 0x800, color)))
        display_ok = 0;
}

static void label(uint8_t row, uint8_t column, const char *text)
{
    uint16_t address = (uint16_t)row * 80 + column;
    while (*text) character(address++, (uint8_t)*text++, 15);
}

static void number(uint8_t row, uint8_t column, uint32_t value)
{
    char digits[11];
    uint8_t index = 10;
    digits[10] = 0;
    do {
        digits[--index] = '0' + (uint8_t)(value % 10);
        value /= 10;
    } while (value && index);
    label(row, column, "          ");
    label(row, column, digits + index);
}

static uint8_t display_init(void)
{
    uint8_t i, row;
    int16_t value;
    display_ok = 1;
    value = tg_reg_read(10);
    if (value < 0) return 0;
    old_cursor = (uint8_t)value;
    value = tg_reg_read(26);
    if (value < 0) return 0;
    old_color = (uint8_t)value;
    for (i = 0; i < 16; ++i) {
        value = tg_vram_read(0x2000 + 127 * 16 + i);
        if (value < 0) return 0;
        glyph[i] = (uint8_t)value;
    }
    display_saved = 1;
    if (tg_reg(10, 0x20) || tg_reg(26, old_color & 0xF0) || tg_clear()) return 0;
    for (i = 0; i < 16; ++i)
        if (tg_vram(0x2000 + 127 * 16 + i, i < 8 ? 255 : 0)) return 0;
    for (row = 0; row < TETRIS_HEIGHT; ++row)
        for (i = 0; i < TETRIS_WIDTH; ++i) cache[row][i] = 255;
    label(0, 3, "MICROLIND TETRIS");
    label(1, 3, "+--------------------+");
    label(22, 3, "+--------------------+");
    for (row = 2; row < 22; ++row) {
        character((uint16_t)row * 80 + 3, 127, 15);
        character((uint16_t)row * 80 + 24, 127, 15);
    }
    label(2, 30, "SCORE"); label(5, 30, "LEVEL"); label(7, 30, "LINES");
    label(9, 30, "NEXT"); label(2, 52, "HIGH SCORES");
    label(23, 3, "JOY1: move, down=drop, button=rotate, up-release=hard drop");
    label(24, 3, "Up+button: pause | Serial A D S W Space P N M Q");
    first_draw = 1;
    return display_ok;
}

static void display_done(void)
{
    uint8_t i;
    if (!display_saved) return;
    display_ok = 1;
    for (i = 0; i < 16 && display_ok; ++i)
        if (tg_vram(0x2000 + 127 * 16 + i, glyph[i])) display_ok = 0;
    if (display_ok) {
        tg_reg(10, old_cursor);
        tg_reg(26, old_color);
        tg_clear();
    }
}

static void draw(void)
{
    uint8_t row, column, value, i, menu;
    uint16_t mask;
    for (row = 0; row < TETRIS_HEIGHT; ++row) {
        for (column = 0; column < TETRIS_WIDTH; ++column) {
            value = tetris_cell(&game, column, row);
            if (value != cache[row][column]) {
                if (display_ok && tg_cell((uint16_t)(row + 2) * 80 + 4 + column * 2,
                                          value ? 127 : 32, colors[value])) display_ok = 0;
                cache[row][column] = value;
            }
        }
    }
    if (first_draw || shown_score != game.score) number(3, 30, game.score);
    if (first_draw || shown_level != game.level) number(6, 30, game.level);
    if (first_draw || shown_lines != game.lines) number(8, 30, game.lines);
    shown_score = game.score; shown_level = game.level; shown_lines = game.lines;
    for (i = 0; i < 5; ++i) {
        if (first_draw || shown_high[i] != saved.scores[i]) number(i + 4, 52, saved.scores[i]);
        shown_high[i] = saved.scores[i];
    }
    if (first_draw || shown_next != game.next) {
        mask = tetris_mask(game.next, 0);
        for (row = 0; row < 4; ++row) {
            for (column = 0; column < 4; ++column) {
                value = (mask & 1) ? game.next : 0;
                if (display_ok && tg_cell((uint16_t)(row + 10) * 80 + 30 + column * 2,
                                          value ? 127 : 32, colors[value])) display_ok = 0;
                mask >>= 1;
            }
        }
        shown_next = game.next;
    }
    menu = paused | (game.over << 1) | (saved.sound << 2) | (selection << 3);
    if (first_draw || shown_menu != menu) {
        label(14, 30, game.over ? "GAME OVER     " : paused ? "PAUSED        " : "              ");
        for (i = 0; i < 4; ++i) {
            label(i + 15, 30, "                 ");
            if (paused) {
                label(i + 15, 30, i == selection ? "> " : "  ");
                label(i + 15, 32, menu_items[i]);
                if (i == 2) label(i + 15, 38, saved.sound ? "ON" : "OFF");
            }
        }
        shown_menu = menu;
    }
    if (first_draw || shown_error != save_error)
        label(20, 30, save_error ? "Save failed        " : "                   ");
    shown_error = save_error;
    first_draw = 0;
    dirty = 0;
}

static void load_save(void)
{
    int16_t status;
    tetris_save_defaults(&saved);
    status = fs_mount(0);
    request.path = "/tetris.dat";
    request.buffer = save_bytes;
    request.count = TG_SAVE_BYTES;
    request.offset = 0;
    if (!status) status = fs_read(&request);
    if (!status) tetris_save_decode(&saved, save_bytes, request.transferred);
    save_dirty = !saved.valid;
}

static void store_save(void)
{
    int16_t status;
    uint16_t i;
    if (!save_dirty) return;
    request.path = "/tetris.dat";
    request.buffer = save_bytes;
    request.count = TG_SAVE_BYTES;
    request.offset = 0;
    status = fs_read(&request);
    if (status == FS_ENOENT) {
        request.offset = 2; /* Enough space for separate 512-byte sectors. */
        status = fs_create(&request);
        if (!status) {
            for (i = 0; i < TG_SAVE_BYTES; ++i) save_bytes[i] = 0;
            request.offset = 0;
            status = fs_write(&request);
            if (!status && request.transferred != TG_SAVE_BYTES) status = FS_EIO;
        }
    }
    if (!status) {
        tetris_save_encode(&saved, record);
        request.buffer = record;
        request.count = TG_RECORD_BYTES;
        request.offset = (uint32_t)(saved.slot ^ 1) * TG_RECORD_STRIDE;
        status = fs_write(&request);
        if (!status && request.transferred != TG_RECORD_BYTES) status = FS_EIO;
        if (!status) {
            request.buffer = save_bytes;
            status = fs_read(&request);
            if (!status && request.transferred != TG_RECORD_BYTES) status = FS_EIO;
            if (!status)
                for (i = 0; i < TG_RECORD_BYTES; ++i)
                    if (save_bytes[i] != record[i]) status = FS_EIO;
        }
    }
    save_error = status != 0;
    if (!status) {
        tetris_save_committed(&saved);
        save_dirty = 0;
    } else serial_text("Tetris save failed; scores retained for this session.\r\n");
    dirty = 1;
}

static void record_score(void)
{
    if (!score_recorded) {
        if (tetris_high_score(&saved, game.score)) save_dirty = 1;
        score_recorded = 1;
    }
}

static void new_game(void)
{
    record_score();
    store_save();
    tetris_new(&game, tg_tick() | 1);
    score_recorded = 0;
    paused = 0;
    tetris_input_reset(&input, (uint8_t)tg_joy());
    tg_sound(saved.sound);
    dirty = 1;
}

static void pause_game(void)
{
    paused = 1;
    selection = game.over ? 1 : 0;
    menu_previous = (uint8_t)tg_joy();
    menu_wait_release = menu_previous != 0;
    menu_direction = 0;
    menu_repeat = 0;
    tg_sound(0);
    dirty = 1;
}

static void choose(void)
{
    if (!selection && !game.over) {
        paused = 0;
        tetris_input_reset(&input, (uint8_t)tg_joy());
        tg_sound(saved.sound);
    } else if (selection == 1) new_game();
    else if (selection == 2) {
        saved.sound ^= 1;
        save_dirty = 1;
        store_save();
    } else if (selection == 3) exiting = 1;
    dirty = 1;
}

static void event(uint8_t result)
{
    if (result) dirty = 1;
    if (result & TETRIS_OVER) {
        record_score();
        store_save();
        pause_game();
        tg_sound(saved.sound);
        tg_effect(4);
    } else if (result & TETRIS_CLEARED) tg_effect(3);
    else if (result & TETRIS_LOCKED) tg_effect(2);
}

static void actions(uint8_t action)
{
    uint8_t result = 0;
    if (action & TG_PAUSE) { pause_game(); return; }
    if (action & TG_LEFT) result |= tetris_move(&game, -1);
    if (action & TG_RIGHT) result |= tetris_move(&game, 1);
    if (action & TG_ROTATE) {
        if (tetris_rotate(&game)) { result |= TETRIS_MOVED; tg_effect(1); }
    }
    if (action & TG_HARD) result |= tetris_hard_drop(&game);
    else if (action & TG_SOFT) result |= tetris_soft_drop(&game);
    event(result);
}

static void menu_tick(uint8_t joy)
{
    int16_t direction = 0;
    uint8_t move = 0, pressed = joy & (uint8_t)~menu_previous;
    if (menu_wait_release) {
        if (!joy) { menu_wait_release = 0; menu_previous = 0; }
        return;
    }
    if ((joy & 3) == 1) direction = -1;
    if ((joy & 3) == 2) direction = 1;
    if (direction != menu_direction) {
        menu_direction = direction;
        menu_repeat = 20;
        if (direction) move = 1;
    } else if (direction && menu_repeat && !--menu_repeat) {
        move = 1;
        menu_repeat = 6;
    }
    if (move) {
        selection = (uint8_t)((selection + direction + 4) & 3);
        dirty = 1;
    }
    if (pressed & 16) choose();
    menu_previous = joy;
}

static void keyboard(int16_t key)
{
    if (key >= 'A' && key <= 'Z') key += 'a' - 'A';
    if (key == 'q') exiting = 1;
    else if (key == 'n') new_game();
    else if (key == 'm') {
        saved.sound ^= 1;
        save_dirty = 1;
        tg_sound(paused ? 0 : saved.sound);
        store_save();
    } else if (key == 'p') {
        if (!paused) pause_game();
        else if (!game.over) { selection = 0; choose(); }
    } else if (paused) {
        if (key == 'w' || key == 's') {
            selection = (selection + (key == 'w' ? 3 : 1)) & 3;
            dirty = 1;
        } else if (key == ' ') choose();
    } else {
        if (key == 'a') actions(TG_LEFT);
        if (key == 'd') actions(TG_RIGHT);
        if (key == 's') actions(TG_SOFT);
        if (key == 'w') actions(TG_ROTATE);
        if (key == ' ') actions(TG_HARD);
    }
}

int main(void)
{
    uint16_t last, now, elapsed;
    int16_t key;
    if (!tg_platform_init()) {
        serial_text("Tetris requires compatible BIOS/FS APIs, initialized VDC, and idle VIA timers.\r\n");
        return 1;
    }
    load_save();
    if (!display_init()) {
        serial_text("Tetris display initialization failed.\r\n");
        display_done(); tg_platform_done();
        return 1;
    }
    tetris_new(&game, tg_tick() | 1);
    tetris_input_reset(&input, (uint8_t)tg_joy());
    tg_sound(saved.sound);
    dirty = 1;
    serial_text("Tetris ready. Serial: A D S W Space P N M Q; joystick 1 active.\r\n");
    last = tg_tick();
    while (!exiting && display_ok) {
        now = tg_tick();
        elapsed = (uint16_t)(now - last);
        last = now;
        if (elapsed > 10) elapsed = 10;
        while (elapsed--) {
            if (paused) menu_tick((uint8_t)tg_joy());
            else {
                actions(tetris_input_tick(&input, (uint8_t)tg_joy()));
                if (!paused) event(tetris_tick(&game));
            }
        }
        key = tg_serial();
        if (key >= 0) keyboard(key);
        if (dirty) draw();
    }
    if (!display_ok) serial_text("Tetris display failed; returning to BIOS.\r\n");
    record_score();
    store_save();
    tg_sound(0);
    display_done();
    tg_platform_done();
    serial_text("Tetris exited.\r\n");
    return 0;
}
