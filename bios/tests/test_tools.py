"""Regression coverage for the actual ROM collisions and unsafe module loads."""

from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from check_rom import validate_rom
from image_formats import image_bytes, read_records
from module_format import pack_module, unpack_module


def ihex(address, data, kind=0):
    raw = bytes((len(data),)) + address.to_bytes(2, "big") + bytes((kind,)) + data
    return ":" + (raw + bytes((-sum(raw) & 255,))).hex().upper() + "\n"


class ImageTests(unittest.TestCase):
    def read(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "image.ihex"
            path.write_text(text)
            return read_records(path)

    def test_bios_io_window_rejected(self):
        for address in (0xDFFF, 0xF400, 0xF7FF, 0x10000):
            with self.subTest(address=address), self.assertRaises(ValueError):
                validate_rom({address: 0})

    def test_vector_overlap_rejected_even_when_bytes_match(self):
        records = self.read(ihex(0xFFF0, b"\xFE\x00") +
                            ihex(0xFFF1, b"\x00") + ihex(0, b"", 1))
        with self.assertRaisesRegex(ValueError, "overlapping"):
            image_bytes(records)

    def test_bad_checksum_rejected(self):
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.read(":01E000001100\n:00000001FF\n")

    def test_unterminated_image_rejected(self):
        with self.assertRaisesRegex(ValueError, "termination"):
            self.read(ihex(0xE000, b"\x39"))

    def test_data_after_termination_rejected(self):
        with self.assertRaisesRegex(ValueError, "after termination"):
            self.read(ihex(0, b"", 1) + ihex(0xE000, b"\x39"))

    def test_valid_sparse_image(self):
        image = image_bytes(self.read(ihex(0xE000, b"\x39") +
                                      ihex(0xFFFF, b"\x00") + ihex(0, b"", 1)))
        validate_rom(image)
        self.assertEqual(image, {0xE000: 0x39, 0xFFFF: 0})

    def test_srec_checksums_and_addresses(self):
        # One RTS byte at $0400, followed by S9 entry at $0400.
        self.assertEqual(image_bytes(self.read("S104040039BE\nS9030400F8\n")),
                         {0x0400: 0x39})


class ModuleTests(unittest.TestCase):
    def test_packager_entry_overlay_and_overlap(self):
        tool = Path(__file__).resolve().parents[1] / "tools" / "pack_module.py"
        with tempfile.TemporaryDirectory() as directory:
            image, bridge, output = (Path(directory) / name for name in ("c.ihex", "bridge.ihex", "app.mlp"))
            image.write_text(ihex(0x0420, b"\x39") + ihex(0, b"", 1))
            bridge.write_text(ihex(0x0400, b"\xBD\x04\x20\x39") + ihex(0, b"", 1))
            command = [sys.executable, str(tool), str(image), str(output), "--overlay", str(bridge),
                       "--kind", "application"]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(unpack_module(output.read_bytes())[4], b"\xBD\x04\x20\x39" + bytes(28) + b"\x39")
            output.unlink()
            bridge.write_text(ihex(0x0400, b"\x39") + ihex(0x0420, b"\x39") + ihex(0, b"", 1))
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("overlapping", result.stderr)
            self.assertFalse(output.exists())

    def test_packager_cli_sparse_image_and_wrong_region(self):
        tool = Path(__file__).resolve().parents[1] / "tools" / "pack_module.py"
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "app.ihex"
            output = Path(directory) / "app.mlp"
            image.write_text(ihex(0x0400, b"\x12") + ihex(0x0402, b"\x39") +
                             ihex(0, b"", 1))
            result = subprocess.run([sys.executable, str(tool), str(image), str(output),
                                     "--kind", "application", "--entry", "0x0402",
                                     "--memory-size", "32"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(unpack_module(output.read_bytes()),
                             (1, 0x0400, 2, 32, b"\x12\x00\x39"))
            output.unlink()
            image.write_text(ihex(0x0400, b"\x39") + ihex(0xD800, b"\x00") +
                             ihex(0, b"", 1))
            result = subprocess.run([sys.executable, str(tool), str(image), str(output),
                                     "--kind", "application"], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_big_endian_header_and_bss(self):
        blob = pack_module(b"\x12\x39", 1, entry=1, memory_size=1024)
        self.assertEqual(blob[:16], bytes.fromhex("4D4C5031000100010400000100020400"))
        self.assertEqual(unpack_module(blob), (1, 0x0400, 1, 1024, b"\x12\x39"))

    def test_corrupt_or_truncated_payload_rejected(self):
        blob = pack_module(b"\x12\x39", 0)
        for bad in (blob[:-1], blob + b"\x00", blob[:-1] + b"\x38", blob[:19]):
            with self.subTest(blob=bad), self.assertRaises(ValueError):
                unpack_module(bad)

    def test_entry_must_be_initialized(self):
        for entry in (-1, 1, 100):
            with self.subTest(entry=entry), self.assertRaises(ValueError):
                pack_module(b"\x39", 1, entry=entry, memory_size=200)

    def test_reserved_memory_cannot_be_overwritten(self):
        for kind, size in ((0, 0x8001), (1, 0x3C01)):
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                pack_module(b"\x39", kind, memory_size=size)
        self.assertEqual(unpack_module(pack_module(b"\x39", 0, memory_size=0x8000))[3],
                         0x8000)

    def test_unknown_abi_kind_or_load_rejected(self):
        blob = pack_module(b"\x39", 1)
        for offset, value in ((4, 2), (6, 2), (8, 0xD400)):
            bad = bytearray(blob)
            struct.pack_into(">H", bad, offset, value)
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                unpack_module(bad)


if __name__ == "__main__":
    unittest.main()
