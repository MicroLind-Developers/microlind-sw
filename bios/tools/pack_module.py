#!/usr/bin/env python3
"""Package an addressed assembler image into a checked, fixed-address MLP1 file."""

import argparse
from pathlib import Path
import sys

from image_formats import image_bytes, read_records
from module_format import REGIONS, pack_module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", help="Intel HEX or Motorola S-record")
    parser.add_argument("output", help="output .mlp file")
    parser.add_argument("--kind", choices=("filesystem", "application"), required=True)
    parser.add_argument("--overlay", action="append", default=[],
                        help="additional addressed image, with no overlapping bytes")
    parser.add_argument("--entry", type=lambda s: int(s, 0), help="absolute entry address")
    parser.add_argument("--memory-size", type=lambda s: int(s, 0),
                        help="total initialized plus uninitialized byte count")
    args = parser.parse_args()
    try:
        kind = 0 if args.kind == "filesystem" else 1
        base, limit = REGIONS[kind]
        image = image_bytes(read_records(args.image))
        for path in args.overlay:
            overlay = image_bytes(read_records(path))
            if image.keys() & overlay.keys():
                raise ValueError("overlapping module images")
            image.update(overlay)
        if min(image) != base or max(image) >= limit:
            raise ValueError("image addresses are outside the module RAM region")
        entry = base if args.entry is None else args.entry
        payload = bytes(image.get(address, 0) for address in range(base, max(image) + 1))
        blob = pack_module(payload, kind, entry - base, args.memory_size)
        Path(args.output).write_bytes(blob)
        print(f"Packaged {len(payload)} bytes at ${base:04X}; entry ${entry:04X}")
    except (ValueError, OSError) as exc:
        print(f"Module packaging failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
