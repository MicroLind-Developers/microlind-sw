#include "save.h"

static uint32_t get32(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) | bytes[3];
}

static void put32(uint8_t *bytes, uint32_t value)
{
    bytes[0] = (uint8_t)(value >> 24);
    bytes[1] = (uint8_t)(value >> 16);
    bytes[2] = (uint8_t)(value >> 8);
    bytes[3] = (uint8_t)value;
}

static uint32_t checksum(const uint8_t *record)
{
    uint8_t i;
    uint32_t sum = 0;
    for (i = 0; i < 60; ++i) sum += record[i];
    return sum;
}

void tetris_save_defaults(TetrisSave *save)
{
    uint8_t i;
    for (i = 0; i < 5; ++i) save->scores[i] = 0;
    save->sequence = 0;
    save->sound = 1;
    save->slot = 1;
    save->valid = 0;
}

static uint8_t valid_record(const uint8_t *record)
{
    uint8_t i;
    if (record[0] != 'T' || record[1] != 'E' || record[2] != 'T' || record[3] != '1' ||
        record[4] != 1 || record[5] > 1 || record[6] || record[7]) return 0;
    for (i = 32; i < 60; ++i) if (record[i]) return 0;
    for (i = 0; i < 4; ++i)
        if (get32(record + 12 + i * 4) < get32(record + 16 + i * 4)) return 0;
    return checksum(record) == get32(record + 60);
}

uint8_t tetris_save_decode(TetrisSave *save, const uint8_t *bytes, uint16_t length)
{
    uint8_t slot, i;
    uint32_t sequence, delta;
    const uint8_t *record;
    tetris_save_defaults(save);
    for (slot = 0; slot < 2; ++slot) {
        if (length < (uint16_t)slot * TG_RECORD_STRIDE + TG_RECORD_BYTES) continue;
        record = bytes + (uint16_t)slot * TG_RECORD_STRIDE;
        if (!valid_record(record)) continue;
        sequence = get32(record + 8);
        delta = sequence - save->sequence;
        if (save->valid && (!delta || delta >= 0x80000000UL)) continue;
        for (i = 0; i < 5; ++i) save->scores[i] = get32(record + 12 + i * 4);
        save->sequence = sequence;
        save->sound = record[5];
        save->slot = slot;
        save->valid = 1;
    }
    return save->valid;
}

void tetris_save_encode(const TetrisSave *save, uint8_t *record)
{
    uint8_t i;
    for (i = 0; i < TG_RECORD_BYTES; ++i) record[i] = 0;
    record[0] = 'T'; record[1] = 'E'; record[2] = 'T'; record[3] = '1';
    record[4] = 1;
    record[5] = save->sound;
    put32(record + 8, save->sequence + 1);
    for (i = 0; i < 5; ++i) put32(record + 12 + i * 4, save->scores[i]);
    put32(record + 60, checksum(record));
}

void tetris_save_committed(TetrisSave *save)
{
    ++save->sequence;
    save->slot ^= 1;
    save->valid = 1;
}

uint8_t tetris_high_score(TetrisSave *save, uint32_t score)
{
    uint8_t index, move;
    for (index = 0; index < 5; ++index) {
        if (score > save->scores[index]) {
            for (move = 4; move > index; --move) save->scores[move] = save->scores[move - 1];
            save->scores[index] = score;
            return 1;
        }
    }
    return 0;
}
