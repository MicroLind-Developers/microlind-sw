#!/usr/bin/env python3
"""Execute CMOC game checks through the actual BIOS and MLFS module loader."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from check_rom import read_symbols
from test_simulator import BIOS, SimulatorTests


class TetrisTests(SimulatorTests):
    filesystem = None
    rules = None
    io_tests = None
    game = None
    game_symbols = None
    diagnostic = None
    session_helper = None
    inspector = None

    def session(self, commands, **configuration):
        if not self.session_helper:
            self.skipTest("GUI backend libraries unavailable; CLI rules tests still run")
        result = subprocess.run([str(self.session_helper), str(self.rom),
                                 str(self.config(banked=True, **configuration))],
                                input=commands, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return {item["tag"]: item for item in map(json.loads, result.stdout.splitlines())}

    def game_fixture(self):
        if not self.game or not self.game_symbols:
            self.skipTest("game and link map not supplied")
        sample = self.directory / "sample.bin"
        sample.write_bytes(b"Tetris integration fixture")
        subprocess.run([str(self.fixture_builder), str(self.disk), "9", str(self.filesystem),
                        "0", str(sample), "32", str(self.diagnostic or ""), str(self.game)],
                       check=True, capture_output=True, timeout=30)

    def inspect_save(self):
        path = self.directory / "save.bin"
        result = subprocess.run([str(self.inspector), str(self.disk), "0", "/tetris.dat", str(path)],
                                check=True, capture_output=True, text=True, timeout=10)
        return path.read_bytes(), tuple(map(int, result.stdout.split()))

    def mem(self, tag, symbol, count):
        return f"memory {tag} {self.game_symbols[symbol]:x} {count:x}\n"

    @staticmethod
    def send(text):
        return f"send {(text + '\r').encode().hex()}\n"

    @staticmethod
    def value(snapshot):
        return bytes.fromhex(snapshot["memory"])

    def portable_suite(self, module, banner):
        sample = self.directory / "sample.bin"
        sample.write_bytes(b"Tetris rules test fixture")
        subprocess.run([str(self.fixture_builder), str(self.disk), "9",
                        str(self.filesystem), "0", str(sample), "32", str(module)],
                       check=True, capture_output=True, timeout=30)
        original = self.disk.read_bytes()
        commands = "run 3000000\nserin 7\r\nrun 350000\nserin t\r\n"
        commands += "run 6000000\nserin q\r\nrun 100000\nregs\n"
        if self.session_helper:
            snapshots = self.session("run 20000000\nsend 370d\nrun 3000000\nsend 740d\n"
                                     "run 60000000\nsend 710d\nrun 1000000\nsnapshot done\n")
            serial = bytes.fromhex(snapshots["done"]["serial"])
            self.assertEqual(snapshots["done"]["dp"], 0)
        else:
            output = self.run_cli(self.rom, commands, banked=True, timeout=180)
            serial = bytes(int(v, 16) for v in
                           re.findall(r"\[SERIAL TX\].*?0x([0-9a-f]{2})", output))
            self.assertIn("DP=00", output)
        self.assertIn(banner + b" PASS", serial, serial[-2000:])
        self.assertNotIn(banner + b" FAIL", serial)
        self.assertTrue(serial.endswith(b"\r>"), serial[-200:])
        self.assertEqual(self.disk.read_bytes(), original)

    def test_tetris_rules_on_target(self):
        self.portable_suite(self.rules, b"Tetris rules")

    def test_tetris_input_and_saves_on_target(self):
        if not self.io_tests:
            self.skipTest("I/O suite not supplied")
        self.portable_suite(self.io_tests, b"Tetris I/O")

    def test_tetris_game_controls_display_and_restore(self):
        self.game_fixture()
        script = "run 2000000\nsnapshot boot\nmemory vector_before d920 2\nfill dc00 200 a5\n"
        script += self.send("8") + "run 4000000\nsnapshot playing\n"
        script += self.mem("start", "_game", 228) + self.mem("ticks1", "_tg_ticks", 2)
        script += self.send("p\r\n") + "run 400000\nsnapshot paused\n"
        script += self.send("p") + "run 500000\njoy 4\nrun 250000\njoy 0\n"
        script += self.mem("left", "_game", 228)
        script += "joy 17\nrun 1200000\nsnapshot chord\nrun 500000\nsnapshot held\n"
        script += "joy 0\nrun 100000\n" + self.send("pn") + "run 400000\n"
        script += self.send(" ") + "run 300000\n" + self.mem("dropped", "_game", 228)
        script += self.send("m") + "run 400000\nsnapshot muted\n"
        script += self.mem("ticks2", "_tg_ticks", 2)
        tick = self.game_symbols["_tg_ticks"]
        script += f"poke {tick:x} ff\npoke {tick+1:x} ff\nrun 120000\n"
        script += self.mem("wrapped", "_tg_ticks", 2)
        script += self.send("q") + "run 700000\nsnapshot exited\nmemory vector_after d920 2\n"
        script += "memory canary dc00 200\n"
        snapshots = self.session(script)
        playing = snapshots["playing"]
        self.assertIn(b"Tetris ready.", bytes.fromhex(playing["serial"]))
        chars = bytes.fromhex(playing["chars"])
        self.assertEqual(chars[3:19], b"MICROLIND TETRIS")
        self.assertEqual(bytes.fromhex(playing["glyph"]), b"\xff" * 8 + bytes(8))
        self.assertEqual(sum(chars[(y + 2) * 80 + x] == 127 for y in range(20) for x in range(4, 24)), 8)  # Four active cells, two columns each.
        self.assertTrue(playing["acr"] & 0x80)
        self.assertGreater(playing["edges"], 0)
        self.assertIn(b"PAUSED", bytes.fromhex(snapshots["paused"]["chars"]))
        self.assertFalse(snapshots["paused"]["acr"] & 0x80)
        self.assertLess(int.from_bytes(self.value(snapshots["left"])[210:212], "big", signed=True),
                        int.from_bytes(self.value(snapshots["start"])[210:212], "big", signed=True))
        for tag in ("chord", "held"):
            self.assertIn(b"> Resume", bytes.fromhex(snapshots[tag]["chars"]))
        dropped = self.value(snapshots["dropped"])
        self.assertGreater(int.from_bytes(dropped[200:204], "big"), 0)
        self.assertEqual(sum(v != 0 for v in dropped[:200]), 4)
        self.assertFalse(snapshots["muted"]["acr"] & 0x80)
        self.assertGreater(int.from_bytes(self.value(snapshots["ticks2"]), "big"),
                           int.from_bytes(self.value(snapshots["ticks1"]), "big"))
        self.assertLess(int.from_bytes(self.value(snapshots["wrapped"]), "big"), 10)
        self.assertEqual(self.value(snapshots["canary"]), b"\xa5" * 512)
        for key in ("glyph", "cursor", "color", "acr", "ddrb", "orb", "ier", "t1_latch", "dp"):
            self.assertEqual(snapshots["exited"][key], snapshots["boot"][key], key)
        self.assertEqual(self.value(snapshots["vector_before"]), self.value(snapshots["vector_after"]))
        self.assertTrue(bytes.fromhex(snapshots["exited"]["serial"]).endswith(b"\r>"))

    def test_tetris_persistence_and_corrupt_record_recovery(self):
        self.game_fixture()
        _, before = self.inspect_save()
        commands = "run 2000000\n" + self.send("8") + "run 4000000\n"
        snapshots = self.session(commands + self.send(" mq") + "run 1500000\nsnapshot done\n")
        self.assertIn(b"Tetris exited.", bytes.fromhex(snapshots["done"]["serial"]))
        saved, after = self.inspect_save()
        self.assertEqual(before, after)
        self.assertEqual(len(saved), 1024)
        for offset in (0, 512):
            self.assertEqual(saved[offset:offset + 4], b"TET1")
            self.assertEqual(sum(saved[offset:offset + 60]), int.from_bytes(saved[offset + 60:offset + 64], "big"))
        self.assertEqual(saved[5], 0)
        self.assertGreater(int.from_bytes(saved[524:528], "big"), 0)
        loaded = self.session(commands + self.mem("loaded", "_saved", 27) +
                              self.send("q") + "run 700000\nsnapshot done\n")
        state = self.value(loaded["loaded"])
        self.assertEqual(state[24:27], bytes((0, 1, 1)))
        self.assertGreater(int.from_bytes(state[:4], "big"), 0)
        # Locate the file via the host library, then damage only the newest sector.
        disk = bytearray(self.disk.read_bytes())
        location = disk.find(saved)
        self.assertGreater(location, 512)
        disk[location + 512] ^= 1
        self.disk.write_bytes(disk)
        recovered = self.session(commands + self.mem("loaded", "_saved", 27) +
                                 self.send("q") + "run 700000\nsnapshot done\n")
        self.assertEqual(self.value(recovered["loaded"])[24:27], bytes((0, 0, 1)))
        disk[location] ^= 1
        self.disk.write_bytes(disk)
        defaults = self.session(commands + self.mem("loaded", "_saved", 27) +
                                self.send("q") + "run 700000\nsnapshot done\n")
        self.assertEqual(self.value(defaults["loaded"]), bytes(24) + bytes((1, 1, 0)))

    def test_tetris_read_only_save_failure_is_recoverable(self):
        self.game_fixture()
        original = self.disk.read_bytes()
        script = "run 2000000\n" + self.send("8") + "run 4000000\n"
        script += self.send("m") + "run 8000000\nsnapshot error\n"
        script += self.send("q") + "run 8000000\nsnapshot done\n"
        result = self.session(script, read_only=True)
        self.assertIn(b"Save failed", bytes.fromhex(result["error"]["chars"]))
        self.assertIn(b"Tetris save failed", bytes.fromhex(result["done"]["serial"]))
        self.assertTrue(bytes.fromhex(result["done"]["serial"]).endswith(b"\r>"))
        self.assertEqual(self.disk.read_bytes(), original)

    def test_tetris_missing_vdc_returns_without_claiming_hardware(self):
        self.game_fixture()
        original = self.disk.read_bytes()
        result = self.session("run 2000000\nsnapshot boot\n" + self.send("8") +
                              "run 3000000\nsnapshot done\n", video=False)
        serial = bytes.fromhex(result["done"]["serial"])
        self.assertIn(b"Tetris requires", serial)
        self.assertTrue(serial.endswith(b"\r>"))
        for key in ("acr", "ddrb", "orb", "ier", "dp"):
            self.assertEqual(result["boot"][key], result["done"][key])
        self.assertEqual(self.disk.read_bytes(), original)

    def test_tetris_missing_save_is_created(self):
        self.game_fixture()
        _, before = self.inspect_save()
        script = "run 2000000\n" + self.send("7") + "run 1000000\n"
        script += self.send("u /tetris.dat\rq") + "run 700000\n"
        script += self.send("8") + "run 4000000\n" + self.send("mq")
        script += "run 1200000\nsnapshot done\n"
        result = self.session(script)
        self.assertIn(b"Tetris exited.", bytes.fromhex(result["done"]["serial"]))
        saved, after = self.inspect_save()
        self.assertEqual(before, after)
        self.assertEqual(len(saved), 576)
        self.assertEqual(saved[:6], b"TET1\x01\x00")

    def test_tetris_busy_timers_are_not_taken_over(self):
        self.game_fixture()
        original = self.disk.read_bytes()
        for setting in ("poke f42e e0\n", "poke f42b c0\n"):
            result = self.session("run 2000000\n" + setting + "snapshot before\n" +
                                  self.send("8") + "run 3000000\nsnapshot done\n")
            serial = bytes.fromhex(result["done"]["serial"])
            self.assertIn(b"Tetris requires", serial)
            self.assertTrue(serial.endswith(b"\r>"))
            for key in ("acr", "ddrb", "orb", "ier", "t1_latch", "dp"):
                self.assertEqual(result["before"][key], result["done"][key])
            self.assertEqual(self.disk.read_bytes(), original)

    def test_tetris_console_restores_selected_partition(self):
        self.game_fixture()
        script = "run 2000000\n" + self.send("7") + "run 1000000\n"
        script += self.send("m1\rg\r") + "run 4000000\n" + self.send("q") + "run 700000\n"
        script += "memory partition b603 1\n" + self.send("t\rt\rq") + "run 20000000\nsnapshot done\n"
        result = self.session(script)
        self.assertEqual(self.value(result["partition"]), b"\x01")
        serial = bytes.fromhex(result["done"]["serial"])
        self.assertIn(b"Tetris exited.", serial)
        self.assertEqual(serial.count(b"FS diagnostic PASS (allocation balanced)"), 2)
        self.assertTrue(serial.endswith(b"\r>"))

    def test_tetris_image_builder_all_block_sizes_and_large_sample(self):
        self.game_fixture()
        sample = self.directory / "sample.bin"
        for log2 in range(9, 17):
            with self.subTest(block_size=1 << log2):
                sample.write_bytes(b"X" * (1048576 if log2 == 9 else 32))
                subprocess.run([str(self.fixture_builder), str(self.disk), str(log2),
                                str(self.filesystem), "0", str(sample), "32",
                                str(self.diagnostic or ""), str(self.game)],
                               check=True, capture_output=True, timeout=30)
                for name, expected in (("biosfs.mlp", self.filesystem), ("tetris.mlp", self.game)):
                    result = self.directory / name
                    subprocess.run([str(self.inspector), str(self.disk), "0", name, str(result)],
                                   check=True, capture_output=True, timeout=10)
                    self.assertEqual(result.read_bytes(), expected.read_bytes())
                saved, _ = self.inspect_save()
                self.assertEqual(saved, bytes(1024))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, type=Path)
    parser.add_argument("--rom", required=True, type=Path)
    parser.add_argument("--symbols", required=True, type=Path)
    parser.add_argument("--filesystem", required=True, type=Path)
    parser.add_argument("--rules", required=True, type=Path)
    parser.add_argument("--io-tests", type=Path)
    parser.add_argument("--game", type=Path)
    parser.add_argument("--game-map", type=Path)
    parser.add_argument("--diagnostic", type=Path)
    parser.add_argument("--cc", default="cc")
    args = parser.parse_args()
    TetrisTests.simulator = args.simulator.resolve()
    TetrisTests.rom = args.rom.resolve()
    TetrisTests.symbols = read_symbols(args.symbols)
    TetrisTests.filesystem = args.filesystem.resolve()
    TetrisTests.rules = args.rules.resolve()
    TetrisTests.io_tests = args.io_tests.resolve() if args.io_tests else None
    TetrisTests.game = args.game.resolve() if args.game else None
    TetrisTests.diagnostic = args.diagnostic.resolve() if args.diagnostic else None
    if args.game_map:
        TetrisTests.game_symbols = dict((name, int(value, 16)) for name, value in
            re.findall(r"^Symbol: (\w+) \([^\n]*\) = ([0-9A-Fa-f]+)$", args.game_map.read_text(), re.M))
    with tempfile.TemporaryDirectory(prefix="microlind-tetris-tools-") as directory:
        builder = Path(directory) / "make_mlfs_fixture"
        subprocess.run([args.cc, "-std=c99", "-Wall", "-Wextra", "-Werror",
                        "-I", str(BIOS.parent / "mlfs/lib/include"),
                        str(BIOS / "tests/simulator/make_mlfs_fixture.c"),
                        str(BIOS.parent / "mlfs/lib/src/mlfs.c"), "-o", str(builder)],
                       check=True, timeout=30)
        TetrisTests.fixture_builder = builder
        inspector = Path(directory) / "inspect_mlfs"
        subprocess.run([args.cc, "-std=c99", "-Wall", "-Wextra", "-Werror",
                        "-I", str(BIOS.parent / "mlfs/lib/include"),
                        str(BIOS / "tests/simulator/inspect_mlfs.c"),
                        str(BIOS.parent / "mlfs/lib/src/mlfs.c"), "-o", str(inspector)],
                       check=True, timeout=30)
        TetrisTests.inspector = inspector
        sim_root = args.simulator.resolve().parent.parent
        libraries = [sim_root / "build/libmicrolind-sim-app.a", sim_root / "build/libmicrolind-sim.a"]
        cxx = shutil.which("c++")
        if cxx and all(path.is_file() for path in libraries) and (sim_root / "include").is_dir():
            helper = Path(directory) / "tetris_session"
            subprocess.run([cxx, "-std=c++20", "-O2", "-Wall", "-Wextra", "-Werror",
                            "-I", str(sim_root / "include"), str(BIOS / "tests/simulator/tetris_session.cpp"),
                            *map(str, libraries), "-o", str(helper)], check=True, timeout=60)
            TetrisTests.session_helper = helper
        suite = unittest.TestSuite(TetrisTests(name) for name in dir(TetrisTests)
                                   if name.startswith("test_tetris_"))
        return not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful()


if __name__ == "__main__":
    raise SystemExit(main())
