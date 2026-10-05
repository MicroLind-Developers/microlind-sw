"""Strict readers for assembler address records; retain duplicates for validation."""

from pathlib import Path


def read_records(path):
    records = []
    base = 0
    ended = False
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        if ended:
            raise ValueError(f"line {number}: data after termination record")
        try:
            if line.startswith(":"):
                raw = bytes.fromhex(line[1:])
                if len(raw) < 5 or len(raw) != raw[0] + 5 or sum(raw) & 255:
                    raise ValueError("bad Intel HEX length or checksum")
                address = int.from_bytes(raw[1:3], "big")
                kind, data = raw[3], raw[4:-1]
                if kind == 0:
                    records.append((base + address, data))
                elif kind == 1 and not data and address == 0:
                    ended = True
                elif kind in (2, 4) and len(data) == 2 and address == 0:
                    base = int.from_bytes(data, "big") << (4 if kind == 2 else 16)
                elif kind in (3, 5) and len(data) == 4 and address == 0:
                    pass
                else:
                    raise ValueError("unsupported or malformed Intel HEX record")
            elif len(line) >= 2 and line[0] == "S":
                widths = {"0": 2, "1": 2, "2": 3, "3": 4, "5": 2, "6": 3,
                          "7": 4, "8": 3, "9": 2}
                width = widths.get(line[1])
                raw = bytes.fromhex(line[2:])
                if width is None or len(raw) < width + 2 or len(raw) != raw[0] + 1:
                    raise ValueError("bad S-record type or length")
                if sum(raw) & 255 != 255:
                    raise ValueError("bad S-record checksum")
                address = int.from_bytes(raw[1:1 + width], "big")
                data = raw[1 + width:-1]
                if line[1] in "123":
                    records.append((address, data))
                elif line[1] in "789":
                    if data:
                        raise ValueError("data in S-record termination")
                    ended = True
            else:
                raise ValueError("expected Intel HEX or Motorola S-record")
        except ValueError as exc:
            raise ValueError(f"line {number}: {exc}") from exc
    if not ended or not records:
        raise ValueError("missing termination record or empty image")
    return records


def image_bytes(records):
    image = {}
    for address, data in records:
        for offset, byte in enumerate(data):
            current = address + offset
            if current in image:
                raise ValueError(f"overlapping records at ${current:04X}")
            image[current] = byte
    return image
