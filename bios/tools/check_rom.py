#!/usr/bin/env python3
"""Reject BIOS address collisions, I/O bytes, and invalid module/vector tables."""

import argparse
from pathlib import Path
import re
import sys

from image_formats import image_bytes, read_records


SERVICES = (
    "CF_INIT", "CF_READ_SECTOR", "CF_WRITE_SECTOR", "SERIAL_PRINT_A",
    "SERIAL_PRINT_CHAR_A", "BIOS_SERIAL_TRY_GETC", "READ_JOY1", "VDC_SET_CURSOR",
    "VDC_WRITE_VRAM_BYTE", "VDC_SET_UPDATE_ADDRESS", "VDC_WRITE_SELECTED",
    "VDC_WRITE", "VDC_READ", "VDC_CLEAR_SCREEN", "VDC_PRINT",
    "VDC_SET_FOREGROUND_COLOR", "VDC_SET_BACKGROUND_COLOR", "BIOS_INSTALL_IRQ_HANDLER",
    "BIOS_LOAD_MODULE", "BIOS_RUN_MODULE",
)


def validate_rom(image, symbols=None):
    for address in image:
        if not (0xE000 <= address < 0xF400 or 0xF800 <= address <= 0xFFFF):
            raise ValueError(f"BIOS byte outside ROM at ${address:04X}")
    if symbols is None:
        return
    def region(address, count):
        try:
            return bytes(image[address + i] for i in range(count))
        except KeyError as exc:
            raise ValueError(f"missing BIOS byte at ${exc.args[0]:04X}") from exc
    header = b"MBR1\x00\x01" + len(SERVICES).to_bytes(2, "big")
    if region(0xF880, 8) != header:
        raise ValueError("invalid module ABI header")
    for index, name in enumerate(SERVICES):
        entry = region(0xF888 + index * 3, 3)
        if entry[0] != 0x7E or int.from_bytes(entry[1:], "big") != symbols[name]:
            raise ValueError(f"module service {index} does not jump to {name}")
    names = ("HOOK_TRAP", "HOOK_SWI3", "HOOK_SWI2", "HOOK_FIRQ", "HOOK_IRQ",
             "HOOK_SWI", "HOOK_NMI", "HOOK_RESET")
    for index, name in enumerate(names):
        target = int.from_bytes(region(0xFFF0 + index * 2, 2), "big")
        if target != symbols[name] or target not in image:
            raise ValueError(f"invalid CPU vector {name}")
    if symbols["VDC_PETSCII_LOWERCASE_NORMAL"] != 0xF900:
        raise ValueError("font is not in its reserved ROM region")
    for name, limit in (("BIOS_LOW_END", 0xF400), ("BIOS_UPPER_END", 0xFE00),
                        ("BIOS_RESET_END", 0xFFF0)):
        if symbols[name] > limit:
            raise ValueError(f"{name} exceeds ${limit:04X}")


def read_symbols(path):
    symbols = {}
    for line in Path(path).read_text().splitlines():
        match = re.fullmatch(r"(\w+) EQU \$([0-9A-Fa-f]+)", line)
        if match:
            symbols[match[1]] = int(match[2], 16)
    return symbols


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image")
    parser.add_argument("--symbols", required=True)
    args = parser.parse_args()
    try:
        image = image_bytes(read_records(args.image))
        symbols = read_symbols(args.symbols)
        validate_rom(image, symbols)
        free = 0xF400 - symbols["BIOS_LOW_END"]
        print(f"ROM verified: {len(image)} bytes; {free} bytes free below I/O")
    except (ValueError, KeyError, OSError) as exc:
        print(f"ROM validation failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
