#!/usr/bin/env python3
"""Validate the packaged filesystem's fixed descriptor, entries and RAM bounds."""
import argparse
from pathlib import Path
from check_rom import read_symbols
from module_format import unpack_module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module")
    parser.add_argument("--symbols", required=True)
    args = parser.parse_args()
    symbols = read_symbols(args.symbols)
    kind, load, entry, memory, payload = unpack_module(Path(args.module).read_bytes())
    if (kind, load, entry, memory) != (0, 0x4000, 0, 0x8000):
        parser.error("unexpected filesystem module region or entry")
    if payload[16:24] != b"FSR1\0\1\0\x0B":
        parser.error("invalid filesystem descriptor")
    for index, name in enumerate(("FS_MOUNT", "FS_STAT", "FS_LIST", "FS_READ", "FS_STATS",
                                  "FS_WRITE", "FS_CREATE", "FS_UNLINK", "FS_MKDIR",
                                  "FS_RMDIR", "FS_RENAME")):
        offset = 24 + index * 3
        if payload[offset:offset + 3] != b"\x7E" + symbols[name].to_bytes(2, "big"):
            parser.error(f"invalid {name} jump")
    if len(payload) != symbols["FS_CODE_END"] - load or symbols["FS_CODE_END"] > symbols["FS_STATE"]:
        parser.error("filesystem code overlaps state")
    print(f"Filesystem verified: {len(payload)} code bytes, {memory} reserved RAM bytes")


if __name__ == "__main__":
    main()
