#!/usr/bin/env python3
"""Execute BIOS integration checks with the microlind-sim CLI and disposable CF images."""

import argparse
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import struct

from check_rom import read_symbols, validate_rom
from image_formats import image_bytes, read_records
from module_format import pack_module


BIOS = Path(__file__).resolve().parents[1]


def write_ihex(path, image):
    """Emit a fixture image, including RAM probes and a private reset vector."""
    addresses = sorted(image)
    records = []
    while addresses:
        start = addresses[0]
        count = 1
        while count < min(16, len(addresses)) and addresses[count] == start + count:
            count += 1
        data = bytes(image[address] for address in addresses[:count])
        raw = bytes((count,)) + start.to_bytes(2, "big") + b"\x00" + data
        records.append(":" + (raw + bytes((-sum(raw) & 255,))).hex().upper())
        del addresses[:count]
    path.write_text("\n".join(records) + "\n:00000001FF\n")


class SimulatorTests(unittest.TestCase):
    simulator = None
    rom = None
    symbols = None
    assembler = None
    fixture_builder = None

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="microlind-bios-sim-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.disk = self.directory / "cf.img"
        self.original = b"MLPT" + bytes(508) + bytes(range(256)) * 2 + bytes([0xC3]) * 1024
        self.disk.write_bytes(self.original)

    def config(self, *, video=True, media=True, read_only=False, banked=False):
        text = """[ROM]
START=0xE000
END=0xF3FF
[ROM]
START=0xF800
END=0xFFFF
[RAM]
START=0x0000
END=0xDFFF
"""
        if banked:
            text += "BANK_SIZE=16384\nAVAILABLE=524288\n"
        text += """[SERIAL]
IO_START_ADDRESS=0xF430
IO_END_ADDRESS=0xF43F
IRQ_LEVEL=1
[CF]
IO_START_ADDRESS=0xF418
IO_END_ADDRESS=0xF41F
"""
        if media:
            text += f"IMAGE={self.disk}\nREAD_ONLY={'true' if read_only else 'false'}\n"
        text += """[PARALLEL]
IO_START_ADDRESS=0xF420
IO_END_ADDRESS=0xF42F
IRQ_LEVEL=2
"""
        if video:
            text += """[VIDEO]
IO_START_ADDRESS=0xF440
IO_END_ADDRESS=0xF441
VRAM_SIZE=65536
"""
        if banked:
            text += """[MEMORY_MAPPER]
BANK_0_REGISTER=0xF400
BANK_1_REGISTER=0xF401
BANK_2_REGISTER=0xF402
BANK_3_REGISTER=0xF403
WINDOW_0=0x0000-0x3FFF
WINDOW_1=0x4000-0x7FFF
WINDOW_2=0x8000-0xBFFF
WINDOW_3=0xC000-0xDFFF
"""
        path = self.directory / "hardware.cfg"
        path.write_text(text)
        return path

    def probe(self, name, definitions=None, *, entry=0x0400, extra_ram=None):
        source = self.directory / "probe.asm"
        prefix = f'    include "{BIOS / "include/module.inc"}"\n'
        prefix += f'    include "{BIOS / "include/filesystem.inc"}"\n'
        for symbol in ("SERIAL_INIT", "SERIAL_START", "PARALLEL_INIT",
                       "PARALLEL_IRQ_HANDLER", "BIOS_MODULE_IRQ_VECTOR", "BOOT_MLOS_UTIL"):
            prefix += f"{symbol} equ ${self.symbols[symbol]:04X}\n"
        for symbol, value in (definitions or {}).items():
            prefix += f"{symbol} equ ${value:X}\n"
        source.write_text(prefix + (BIOS / "tests/simulator" / name).read_text())
        binary = self.directory / "probe.ihex"
        result = subprocess.run([self.assembler, "-3", "-f", "ihex", "-o", str(binary),
                                 str(source)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        image = image_bytes(read_records(self.rom))
        validate_rom(image, self.symbols)
        probe = image_bytes(read_records(binary))
        self.assertTrue(all(entry <= address < entry + 0x0C00 for address in probe))
        image.update(probe)
        image.update({address: 0 for address in range(0x0300, 0x0310)})
        image.update(extra_ram or {})
        image.update({0xFFFE: entry >> 8, 0xFFFF: entry & 255})
        output = self.directory / "fixture.ihex"
        write_ihex(output, image)
        return output

    def run_cli(self, image, commands, *, timeout=30, **configuration):
        result = subprocess.run([str(self.simulator), "--6309", "--ihex", "--rom", str(image),
                                 "--config", str(self.config(**configuration))],
                                input=commands + "\nexit\n", capture_output=True,
                                text=True, timeout=timeout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def memory(self, output, address, count=None):
        if count is not None:
            data = bytearray()
            while len(data) < count:
                data.extend(self.memory(output, address + len(data)))
            return bytes(data[:count])
        match = re.search(rf"\b{address:04x}: ((?:[0-9a-f]{{2}} +)+)", output)
        self.assertIsNotNone(match, output)
        return bytes.fromhex(match.group(1))

    def test_boot_with_vdc_and_cf(self):
        output = self.run_cli(self.rom, "run 3000000\nregs\npeek 0xD80C 2", banked=True)
        self.assertEqual(self.memory(output, 0xD80C), b"\x01\x01")
        self.assertIn("[SERIAL TX] '>'", output)
        self.assertEqual(self.disk.read_bytes(), self.original)

    def test_boot_without_vdc_or_cf(self):
        output = self.run_cli(self.rom, "run 3000000\nregs\npeek 0xD80C 2",
                              video=False, media=False, banked=True)
        self.assertEqual(self.memory(output, 0xD80C), b"\x00\x00")
        self.assertIn("[SERIAL TX] '>'", output)

    def test_cf_read_write_round_trip_and_registers(self):
        image = self.probe("cf_transfer.asm")
        output = self.run_cli(image, "run 30000\nregs\npeek 0x0300 16")
        self.assertEqual(self.memory(output, 0x0300)[:2], b"\x04\xA5", output)
        expected = bytearray(self.original)
        expected[1024:1536] = bytes(value ^ 0x5A for value in self.original[512:1024])
        self.assertEqual(self.disk.read_bytes(), expected)

    def check_cf_error(self, lba, service, expected_status, **configuration):
        image = self.probe("cf_error.asm", {"TEST_LBA": lba, "TEST_SERVICE": service})
        output = self.run_cli(image, "run 600000\nregs\npeek 0x0300 16\npeek 0xF41A 5",
                              **configuration)
        memory = self.memory(output, 0x0300)
        self.assertEqual(memory[1], 0xA5, output)
        self.assertEqual(memory[2], expected_status, output)
        self.assertEqual(memory[3] & 1, 1, output)
        self.assertEqual(memory[4:12], bytes.fromhex("100013572468") +
                         (lba & 0xFFFF).to_bytes(2, "big"), output)
        self.assertEqual(self.disk.read_bytes(), self.original)
        return output

    def test_cf_lba28_overflow_rejected(self):
        for service in (0xF88B, 0xF88E):
            with self.subTest(service=service):
                output = self.check_cf_error(0x10000000, service, 2)
                self.assertEqual(self.memory(output, 0xF41A), bytes.fromhex("01010000E0"))

    def test_cf_outside_media_rejected(self):
        for service in (0xF88B, 0xF88E):
            with self.subTest(service=service):
                self.check_cf_error(4, service, 2)

    def test_cf_read_only_write_rejected(self):
        self.check_cf_error(2, 0xF88E, 2, read_only=True)

    def test_cf_absent_media_timeout(self):
        for service in (0xF88B, 0xF88E):
            with self.subTest(service=service):
                self.check_cf_error(1, service, 1, media=False)

    def test_mlpt_is_not_executed_by_legacy_boot(self):
        image = self.probe("mlpt_guard.asm")
        output = self.run_cli(image, "run 10000\nregs\npeek 0x0300 16")
        self.assertEqual(self.memory(output, 0x0300)[1], 0xA5, output)
        serial = bytes(int(byte, 16) for byte in
                       re.findall(r"\[SERIAL TX\].*?0x([0-9a-f]{2})", output))
        self.assertIn(b"MLFS card: file boot required.", serial)
        self.assertEqual(self.disk.read_bytes(), self.original)

    def test_vdc_serial_and_real_timer_irq(self):
        image = self.probe("hardware.asm")
        output = self.run_cli(image, "run 10000\nserin K\npoke 0x030F 1\n"
                              "run 10000\nregs\npeek 0x0300 16")
        memory = self.memory(output, 0x0300)
        self.assertEqual(memory[:2], b"\x05\xA5", output)
        self.assertEqual(memory[14], 1, output)
        self.assertNotIn("[SERIAL TX]", output, "Nonblocking input must not echo")

    def boot_fixture(self, blob, log2=9, slot=5):
        module = self.directory / "module.mlp"
        module.write_bytes(blob)
        result = subprocess.run([str(self.fixture_builder), str(self.disk), str(log2),
                                 str(module), str(slot)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.original = self.disk.read_bytes()
        # Locate target dentry and data using actual disk metadata.
        self.root = 512 + int.from_bytes(self.original[512 + 21:512 + 25], "big") * (1 << log2)
        self.dentry = self.root + slot * 128
        self.data = 512 + int.from_bytes(self.original[self.dentry + 64:self.dentry + 68], "big") * (1 << log2)

    def load_probe(self, kind=0, *, run=False, extra_ram=None):
        return self.probe("module_load.asm", {"TEST_KIND": kind,
                          "TEST_SERVICE": self.symbols["BIOS_MODULE_RUN" if run else "BIOS_MODULE_LOAD"]},
                          entry=0xC000, extra_ram=extra_ram)

    def check_load_error(self, image, status, **configuration):
        output = self.run_cli(image, "run 100000\nregs\npeek 0x0300 16\npeek 0x0310 16",
                              **configuration)
        result = self.memory(output, 0x0300)
        self.assertEqual(result[15], 0xA5, output)
        self.assertEqual(result[0], status, output)
        self.assertEqual(result[1] & 1, 1, output)
        self.assertEqual(self.memory(output, 0x0310)[4], 0, "Rejected module executed")
        self.assertEqual(self.disk.read_bytes(), self.original)

    def test_module_load_all_block_sizes(self):
        for log2 in range(9, 17):
            with self.subTest(log2=log2):
                payload = bytes((i * 17 + i // 256 + 3) & 255 for i in range(1500))
                self.boot_fixture(pack_module(payload, 0, entry=7, memory_size=1532), log2)
                ram = {address: 0xCC for address in range(0x4000, 0x4600)}
                ram.update({0x3FFF: 0x5A, 0x4600: 0xA5})
                image = self.load_probe(extra_ram=ram)
                output = self.run_cli(image, "run 100000\nregs\npeek 0x0300 16\n"
                                      "peek 0x3FFF 1\npeek 0x4000 1536\npeek 0x4600 1")
                result = self.memory(output, 0x0300)
                self.assertEqual(result[15], 0xA5, output)
                self.assertEqual(result[0:1], b"\0", output)
                self.assertEqual(result[1] & 1, 0, output)
                self.assertEqual(result[2:6], bytes.fromhex("4007E000"), output)
                self.assertEqual(self.memory(output, 0x3FFF), b"\x5A")
                self.assertEqual(self.memory(output, 0x4000, 1536), payload + bytes(32) + b"\xCC" * 4)
                self.assertEqual(self.memory(output, 0x4600), b"\xA5")
                self.assertEqual(self.disk.read_bytes(), self.original)

    def test_module_ram_and_sector_boundaries(self):
        cases = [(0, 1, 0x8000), (0, 0x8000, 0x8000), (1, 1, 0x3C00),
                 (1, 0x3C00, 0x3C00), (0, 492, 492), (0, 493, 493),
                 (0, 1004, 1004), (0, 1005, 1005)]
        for kind, size, memory in cases:
            with self.subTest(kind=kind, size=size, memory=memory):
                base = 0x4000 if kind == 0 else 0x0400
                limit = 0xC000 if kind == 0 else 0x4000
                payload = bytes((i * 31 + i // 256) & 255 for i in range(size))
                self.boot_fixture(pack_module(payload, kind, entry=size - 1, memory_size=memory))
                ram = {a: 0xCC for a in range(base, limit)}
                ram[base - 1] = 0x5A
                if kind == 1:
                    ram[limit] = 0xA5
                image = self.load_probe(kind, extra_ram=ram)
                output = self.run_cli(image, f"run 1000000\nregs\npeek 0x0300 16\n"
                                      f"peek {base - 1} 1\npeek {base + memory - 1} 1\n"
                                      f"peek {limit} 1")
                result = self.memory(output, 0x0300)
                self.assertEqual(result[15], 0xA5, output)
                self.assertEqual(result[0], 0, output)
                self.assertEqual(result[1] & 1, 0, output)
                self.assertEqual(int.from_bytes(result[2:4], "big"), base + size - 1)
                self.assertEqual(self.memory(output, base - 1), b"\x5A")
                self.assertEqual(self.memory(output, base + memory - 1),
                                 payload[-1:] if memory == size else b"\0")
                self.assertEqual(self.memory(output, limit), b"\x1A" if kind == 0 else b"\xA5")
                self.assertEqual(self.disk.read_bytes(), self.original)

    def test_module_launcher_passes_apis_and_returns(self):
        # STX/STY record entry arguments; mark execution, change DP/U, then RTS.
        payload = bytes.fromhex("BF031010BF031286A7B7031486771F8BCE123439")
        for kind, base in ((0, 0x4000), (1, 0x0400)):
            with self.subTest(kind=kind):
                self.boot_fixture(pack_module(payload, kind, memory_size=64))
                image = self.load_probe(kind, run=True, extra_ram={a: 0 for a in range(0x0310, 0x0320)})
                output = self.run_cli(image, "run 100000\nregs\npeek 0x0300 16\npeek 0x0310 16")
                result = self.memory(output, 0x0300)
                self.assertEqual(result[15], 0xA5, output)
                self.assertEqual(result[0], 0, output)
                self.assertEqual(result[1] & 0x51, 0x50, output)
                self.assertEqual(result[4:9], bytes.fromhex("E000ABCD12"), output)
                self.assertEqual(self.memory(output, 0x0310)[:5], bytes.fromhex("F880ABCDA7"), output)
                self.assertEqual(self.disk.read_bytes(), self.original)

    def test_module_invalid_metadata(self):
        blob = pack_module(b"\x39" * 600, 0)
        cases = [(0, b"FAIL"), (4, b"\x02"), (7, b"\0\0"), (7, b"\0\x11"),
                 (9, bytes(4)), (9, bytes.fromhex("10000000")),
                 (13, bytes(4)), (13, bytes.fromhex("FFFFFFFF")),
                 (17, b"\x02"), (18, b"\x08"), (18, b"\x11"),
                 (512, b"FAIL"), (516, b"\x02"), (519, b"\x0A"),
                 (557, bytes(4)),
                 (13, bytes.fromhex("FFFFFFFF0110"))]  # Block-to-sector shift overflow.
        image = self.load_probe(run=True, extra_ram={a: 0 for a in range(0x0310, 0x0320)})
        for offset, change in cases:
            with self.subTest(offset=offset, value=change.hex()):
                self.boot_fixture(blob)
                disk = bytearray(self.original)
                disk[offset:offset + len(change)] = change
                self.disk.write_bytes(disk)
                self.original = bytes(disk)
                self.check_load_error(image, 2)

    def test_module_invalid_header_or_checksum(self):
        good = pack_module(b"\x39" * 600, 0)
        cases = [(0, b"FAIL", 5), (4, b"\0\x02", 5), (6, b"\0\x01", 5),
                 (8, b"\xD8\0", 5), (10, b"\x02\x58", 5), (12, b"\0\0", 5),
                 (12, b"\x02\x59", 5), (14, b"\x80\x01", 5),
                 (14, b"\x02\x57", 5), (16, bytes(4), 6), (619, b"\x38", 6)]
        image = self.load_probe(run=True, extra_ram={a: 0 for a in range(0x0310, 0x0320)})
        for offset, change, status in cases:
            with self.subTest(offset=offset, value=change.hex()):
                blob = bytearray(good)
                blob[offset:offset + len(change)] = change
                self.boot_fixture(blob)
                self.check_load_error(image, status)

    def test_module_missing_or_unsupported_extent(self):
        blob = pack_module(b"\x39" * 600, 0)
        cases = [(0, b"\0", 3), (1, b"\x01", 4), (14, b"\x02", 4),
                 (15, b"\x02", 4), (96, b"\0\0\0\x01", 4),
                 (2, b"\0\x01\0\0", 4), (64, bytes(4), 4),
                 (68, bytes(4), 4), (68, bytes.fromhex("FFFFFFFF"), 4),
                 (68, bytes.fromhex("00000001"), 4)]
        image = self.load_probe(run=True, extra_ram={a: 0 for a in range(0x0310, 0x0320)})
        for offset, change, status in cases:
            with self.subTest(offset=offset, value=change.hex()):
                self.boot_fixture(blob)
                disk = bytearray(self.original)
                start = self.dentry + offset
                disk[start:start + len(change)] = change
                self.disk.write_bytes(disk)
                self.original = bytes(disk)
                self.check_load_error(image, status)

    def test_module_superblock_extent_bounds(self):
        blob = pack_module(b"\x39" * 600, 0)
        cases = [(9, 95), (13, 0), (13, 96), (17, 0), (17, 96),
                 (17, 0xFFFFFFFF), (21, 0), (21, 1), (21, 96),
                 (25, 0), (25, 96), (25, 0xFFFFFFFF)]
        image = self.load_probe(run=True, extra_ram={a: 0 for a in range(0x0310, 0x0320)})
        for offset, value in cases:
            with self.subTest(offset=offset, value=value):
                self.boot_fixture(blob)
                disk = bytearray(self.original)
                struct.pack_into(">I", disk, 512 + offset, value)
                disk[557:561] = bytes(4)
                struct.pack_into(">I", disk, 557, sum(disk[512:1024]))
                self.disk.write_bytes(disk)
                self.original = bytes(disk)
                self.check_load_error(image, 2)

    def test_module_cf_failure_during_payload(self):
        self.boot_fixture(pack_module(b"\x39" * 600, 0))
        self.original = self.original[:self.data + 512]
        self.disk.write_bytes(self.original)
        image = self.load_probe(run=True, extra_ram={a: 0 for a in range(0x0310, 0x0320)})
        self.check_load_error(image, 1)

    def test_bios_menu_launches_filesystem_module(self):
        payload = bytes.fromhex("BF031010BF031286A7B7031486771F8BCE123439")
        self.boot_fixture(pack_module(payload, 0, memory_size=64))
        output = self.run_cli(self.rom, "run 3000000\nserin 7\r\nrun 100000\n"
                              "regs\npeek 0x0310 16", banked=True)
        self.assertEqual(self.memory(output, 0x0310)[:5], bytes.fromhex("F8800000A7"), output)
        self.assertIn("DP=00", output)
        self.assertEqual(self.disk.read_bytes(), self.original)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, type=Path)
    parser.add_argument("--rom", required=True, type=Path)
    parser.add_argument("--symbols", required=True, type=Path)
    parser.add_argument("--assembler", default="lwasm")
    parser.add_argument("--cc", default="cc", help="Host compiler for production MLFS disk fixtures")
    args = parser.parse_args()
    SimulatorTests.simulator = args.simulator.resolve(strict=True)
    SimulatorTests.rom = args.rom.resolve(strict=True)
    SimulatorTests.symbols = read_symbols(args.symbols)
    SimulatorTests.assembler = args.assembler
    with tempfile.TemporaryDirectory(prefix="microlind-mlfs-fixtures-") as directory:
        builder = Path(directory) / "make_mlfs_fixture"
        result = subprocess.run([args.cc, "-std=c99", "-Wall", "-Wextra", "-Werror",
                                 "-I", str(BIOS.parent / "mlfs/lib/include"),
                                 str(BIOS / "tests/simulator/make_mlfs_fixture.c"),
                                 str(BIOS.parent / "mlfs/lib/src/mlfs.c"), "-o", str(builder)],
                                capture_output=True, text=True, timeout=30)
        if result.returncode:
            parser.error("could not build host MLFS fixtures: " + result.stderr)
        SimulatorTests.fixture_builder = builder
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(SimulatorTests)
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
