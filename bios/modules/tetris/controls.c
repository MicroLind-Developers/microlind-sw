#include "controls.h"

void tetris_input_reset(TetrisInput *input, uint8_t held)
{
    input->previous = held;
    input->horizontal = 0;
    input->repeat = 0;
    input->down_repeat = 0;
    input->chord = 0;
    input->up_armed = 0;
    input->cancelled = 1;
}

uint8_t tetris_input_tick(TetrisInput *input, uint8_t joy)
{
    uint8_t result = 0;
    uint8_t pressed = joy & (uint8_t)~input->previous;
    int16_t horizontal = 0;
    if ((joy & 12) == 4) horizontal = -1;
    if ((joy & 12) == 8) horizontal = 1;
    if (horizontal != input->horizontal) {
        input->horizontal = horizontal;
        input->repeat = 20;
        if (horizontal) result |= horizontal < 0 ? TG_LEFT : TG_RIGHT;
    } else if (horizontal && input->repeat && !--input->repeat) {
        result |= horizontal < 0 ? TG_LEFT : TG_RIGHT;
        input->repeat = 6;
    }
    if (pressed & 2) {
        result |= TG_SOFT;
        input->down_repeat = 6;
    } else if ((joy & 2) && input->down_repeat && !--input->down_repeat) {
        result |= TG_SOFT;
        input->down_repeat = 6;
    }
    if (!(joy & 2)) input->down_repeat = 0;
    if (pressed & 1) {
        input->up_armed = 1;
        input->cancelled = 0;
        input->chord = 0;
    }
    if ((joy & 17) == 17) {
        if (input->chord < 50) {
            if (++input->chord == 50) {
                result |= TG_PAUSE;
                input->cancelled = 1;
                input->up_armed = 0;
            }
        }
    } else {
        input->chord = 0;
        if ((pressed & 16) && !(joy & 1)) result |= TG_ROTATE;
    }
    if (!(joy & 1) && (input->previous & 1) && input->up_armed && !input->cancelled) {
        result |= TG_HARD;
        input->up_armed = 0;
    }
    input->previous = joy;
    return result;
}
