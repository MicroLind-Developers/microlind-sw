"""MLP1 package format shared by the packager and its host-side validation."""

import struct

HEADER = struct.Struct(">4s6HI")
ABI_VERSION = 1
REGIONS = {0: (0x4000, 0xC000), 1: (0x0400, 0x4000)}


def validate_header(abi, kind, load, entry, size, memory):
    if abi != ABI_VERSION or kind not in REGIONS:
        raise ValueError("unsupported module ABI or kind")
    base, limit = REGIONS[kind]
    if load != base or not 0 < size <= memory <= limit - base:
        raise ValueError("module does not fit its reserved RAM region")
    if not 0 <= entry < size:
        raise ValueError("entry point is outside the initialized payload")


def pack_module(payload, kind, entry=0, memory_size=None):
    memory = len(payload) if memory_size is None else memory_size
    if kind not in REGIONS:
        raise ValueError("unsupported module kind")
    load = REGIONS[kind][0]
    validate_header(ABI_VERSION, kind, load, entry, len(payload), memory)
    checksum = sum(payload) & 0xFFFFFFFF
    return HEADER.pack(b"MLP1", ABI_VERSION, kind, load, entry, len(payload),
                       memory, checksum) + payload


def unpack_module(blob):
    if len(blob) < HEADER.size:
        raise ValueError("truncated module header")
    magic, abi, kind, load, entry, size, memory, checksum = HEADER.unpack_from(blob)
    if magic != b"MLP1":
        raise ValueError("invalid module magic")
    validate_header(abi, kind, load, entry, size, memory)
    payload = blob[HEADER.size:]
    if len(payload) != size:
        raise ValueError("module length differs from header")
    if sum(payload) & 0xFFFFFFFF != checksum:
        raise ValueError("module payload checksum mismatch")
    return kind, load, entry, memory, payload
