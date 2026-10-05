#!/usr/bin/env python3
"""Run the packaged assembly filesystem against production host MLFS images."""
import argparse
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import unittest

from check_rom import read_symbols
from image_formats import image_bytes, read_records
from test_simulator import BIOS, SimulatorTests


class FilesystemTests(SimulatorTests):
    filesystem = None
    cmoc = None
    diagnostic = None

    def setUp(self):
        super().setUp()
        self.content = bytes((i * 29 + i // 256 + 7) & 255 for i in range(0x23011))

    def filesystem_fixture(self, log2=9, diagnostic_blocks=32, *, diagnostic=False):
        data = self.directory / "data.bin"
        data.write_bytes(self.content)
        slot = 0 if diagnostic else 5
        command = [str(self.fixture_builder), str(self.disk), str(log2),
                   str(self.filesystem), str(slot), str(data), str(diagnostic_blocks)]
        if diagnostic:
            command.append(str(self.diagnostic))
        result = subprocess.run(command, capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.original = self.disk.read_bytes()
        self.log2 = log2
        self.root = 512 + int.from_bytes(self.original[533:537], "big") * (1 << log2)
        self.data_entry = self.root + (slot + 1) * 128
        self.partition1 = int.from_bytes(self.original[33:37], "big") * 512

    def fs_probe(self, service, path="/data.bin", count=1024, offset=0, partition=0,
                 buffer=0x1000, request=0x0400, extra=None, service_address=None,
                 fault_write=0, fault_after=False):
        ram = {a: 0 for a in range(0x0310, 0x0320)}
        ram[0x0330] = 0
        blob = struct.pack(">HHHIH", 0x0500, buffer, count, offset, 0xCA55)
        ram.update({request + i: byte for i, byte in enumerate(blob)})
        ram.update({0x0500 + i: byte for i, byte in enumerate(path.encode() + b"\0")})
        ram.update({a: 0xCC for a in range(0x0FFF, 0x1801)})
        ram.update(extra or {})
        return self.probe("filesystem_api.asm", {"TEST_SERVICE": service_address or 0x4018 + service * 3,
                          "TEST_REQUEST": request, "TEST_PARTITION": partition,
                          "TEST_FAULT_WRITE": fault_write, "TEST_FAULT_AFTER": int(fault_after)},
                          entry=0xC000, extra_ram=ram)

    def fs_execute(self, image, status=0, *, command_extra="", count=0, buffer=0x1000,
                   request=0x0400, mutates=False, instructions=300000, read_only=False):
        output = self.run_cli(image, f"run {instructions}\nregs\npeek 0x0300 16\npeek 0x0310 4\n"
                              f"peek {request} 12\npeek {buffer - 1} 1\npeek {buffer} {max(count, 1)}\n"
                              + command_extra, read_only=read_only)
        result = self.memory(output, 0x0300)
        self.assertEqual(result[15], 0xA5, output)
        self.assertEqual(int.from_bytes(result[:2], "big", signed=True), status, output)
        self.assertEqual(result[2] & 1, int(status < 0), output)
        self.assertEqual(result[4:13], request.to_bytes(2, "big") +
                         bytes.fromhex("13572468E00012"), output)
        if not mutates:
            self.assertEqual(self.disk.read_bytes(), self.original)
        return output

    def mutate(self, service, path, *, payload=b"", offset=0, destination=None,
               status=0, partition=1, instructions=350000, **options):
        extra = {0x1000 + i: byte for i, byte in enumerate(payload)}
        if destination is not None:
            extra.update({0x1000 + i: byte for i, byte in enumerate(destination.encode() + b"\0")})
        image = self.fs_probe(service, path, len(payload), offset, partition, extra=extra, **options)
        output = self.fs_execute(image, status, mutates=True, instructions=instructions)
        updated = self.disk.read_bytes()
        if partition == 1:
            self.assertEqual(updated[:self.partition1], self.original[:self.partition1])
        if status == 0 and service == 5:
            self.assertEqual(int.from_bytes(self.memory(output, 0x0400)[10:12], "big"), len(payload))
        self.original = updated
        return output

    def host_inspect(self, path="/", partition=1, *, read=False):
        exported = self.directory / "export.bin"
        arguments = [str(self.inspector), str(self.disk), str(partition), path]
        if read:
            arguments.append(str(exported))
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = result.stdout.splitlines()
        stats = tuple(int(value) for value in lines[0].split())
        if read:
            return stats, exported.read_bytes()
        entries = {}
        for line in lines[1:]:
            flags, size, start, length, name = line.split(" ", 4)
            entries[name] = tuple(int(value) for value in (flags, size, start, length))
        return stats, entries

    def test_fs_write_growth_and_gaps_all_block_sizes(self):
        payload = bytes((i * 19 + 3) & 255 for i in range(1000))
        for log2 in range(9, 17):
            with self.subTest(log2=log2):
                self.filesystem_fixture(log2)
                before, entries = self.host_inspect()
                start = entries["other.txt"][2]
                self.mutate(5, "/other.txt", payload=payload, offset=513)
                after, data = self.host_inspect("/other.txt", read=True)
                self.assertEqual(data, b"partition1" + bytes(503) + payload)
                _, entries = self.host_inspect()
                capacity = (1513 + (1 << log2) - 1) >> log2
                self.assertEqual(entries["other.txt"][2:], (start, capacity))
                self.assertEqual(after[0] - before[0], capacity - 1)

    def test_fs_relocation_preserves_contents_and_releases_old_run(self):
        self.filesystem_fixture()
        _, entries = self.host_inspect()
        old_start = entries["other.txt"][2]
        self.mutate(6, "/blocker")
        before, _ = self.host_inspect()
        payload = bytes(range(256)) * 4
        self.mutate(5, "/other.txt", payload=payload, offset=511)
        after, data = self.host_inspect("/other.txt", read=True)
        self.assertEqual(data, b"partition1" + bytes(501) + payload)
        _, entries = self.host_inspect()
        self.assertNotEqual(entries["other.txt"][2], old_start)
        self.assertEqual(entries["other.txt"][3], 3)
        self.assertEqual(after[0] - before[0], 2)
        self.mutate(6, "/reused")
        _, entries = self.host_inspect()
        self.assertEqual(entries["reused"][2], old_start)

    def test_fs_create_nested_remove_and_stats(self):
        self.filesystem_fixture()
        before, _ = self.host_inspect()
        self.mutate(8, "/play/")
        self.mutate(6, "/play/save.dat", offset=2)
        after, entries = self.host_inspect("/play")
        self.assertEqual(entries["save.dat"][0:2], (2, 0))
        self.assertEqual(entries["save.dat"][3], 2)
        self.assertEqual(after[0] - before[0], 3)
        self.mutate(5, "/play/save.dat", payload=b"saved!", offset=511)
        _, data = self.host_inspect("/play/save.dat", read=True)
        self.assertEqual(data, bytes(511) + b"saved!")
        self.mutate(9, "/play", status=-14)
        self.mutate(7, "/play/save.dat")
        self.mutate(9, "/play/")
        after, entries = self.host_inspect()
        self.assertEqual(after, before)
        self.assertEqual(set(entries), {"other.txt"})

    def test_fs_rename_move_and_directory_cycles(self):
        self.filesystem_fixture()
        self.mutate(8, "/a")
        self.mutate(8, "/b")
        self.mutate(6, "/a/file")
        self.mutate(5, "/a/file", payload=b"keep me")
        self.mutate(10, "/a/file", destination="/a/new")
        self.mutate(10, "/a/new", destination="/a/new")
        self.mutate(10, "/a/new", destination="/b/moved")
        self.mutate(10, "/a", destination="/b/a")
        _, data = self.host_inspect("/b/moved", read=True)
        self.assertEqual(data, b"keep me")
        unchanged = self.original
        for path, destination, error in (("/b", "/b/a/loop", -2),
                                         ("/b/moved", "/other.txt", -12),
                                         ("/b/moved", "/missing/file", -5),
                                         ("/b/moved", "/new/", -6)):
            self.mutate(10, path, destination=destination, status=error)
            self.assertEqual(self.original, unchanged)
        self.mutate(9, "/b/a")
        self.mutate(7, "/b/moved")
        self.mutate(9, "/b")

    def test_fs_mutation_errors_leave_image_unchanged(self):
        self.filesystem_fixture()
        original = self.original
        for service, path, error in ((6, "/other.txt", -12), (6, "/missing/file", -5),
                                      (6, "/other.txt/child", -6), (7, "/", -2),
                                      (9, "/other.txt", -6), (5, "/", -7),
                                      (8, "/..", -2), (6, "/" + "n" * 48, -10)):
            self.mutate(service, path, status=error)
            self.assertEqual(self.original, original)
        self.mutate(5, "/other.txt", payload=b"x", offset=0xFFFFFFFF, status=-11)
        self.assertEqual(self.original, original)
        self.mutate(5, "/other.txt", offset=0xFFFFFFFF)
        self.assertEqual(self.original, original)

    def test_fs_out_of_space_and_fragmented_runs(self):
        self.filesystem_fixture()
        bitmap = self.partition1 + (1 << self.log2)
        disk = bytearray(self.original)
        disk[bitmap:bitmap + 4] = b"\xFF" * 4
        self.disk.write_bytes(disk)
        self.original = bytes(disk)
        self.mutate(5, "/other.txt", payload=b"x", offset=512, status=-13)
        self.assertEqual(self.original, bytes(disk))
        for block in (5, 7, 9, 11, 13):
            disk[bitmap + block // 8] &= ~(1 << (block % 8))
        self.disk.write_bytes(disk)
        self.original = bytes(disk)
        self.mutate(6, "/too-big", offset=2, status=-13)
        self.assertEqual(self.original, bytes(disk))

    def test_fs_bitmap_sector_boundary(self):
        self.filesystem_fixture(diagnostic_blocks=5000)
        bitmap = self.partition1 + 512
        disk = bytearray(self.original)
        for block in range(4095):
            disk[bitmap + block // 8] |= 1 << (block % 8)
        self.disk.write_bytes(disk)
        self.original = bytes(disk)
        before, _ = self.host_inspect()
        self.mutate(6, "/boundary", offset=3, instructions=2000000)
        after, entries = self.host_inspect()
        self.assertEqual(entries["boundary"][2:], (4095, 3))
        self.assertEqual(after[0] - before[0], 3)
        self.mutate(7, "/boundary")
        after, _ = self.host_inspect()
        self.assertEqual(after, before)

    def test_fs_allocation_rollback_and_lost_completion(self):
        for after in (False, True):
            for write in (1, 2, 3):
                with self.subTest(after=after, write=write):
                    self.filesystem_fixture()
                    before, _ = self.host_inspect()
                    self.mutate(6, "/fault", status=-1, fault_write=write, fault_after=after)
                    stats, entries = self.host_inspect()
                    published = after and write == 3
                    self.assertEqual("fault" in entries, published)
                    self.assertEqual(stats[0] - before[0], int(published))
                    if not published:
                        self.assertEqual(stats, before)

    def test_fs_partial_writes_and_32bit_offsets(self):
        self.filesystem_fixture()
        payload = b"changed" * 100
        self.mutate(5, "/docs/sub/data.bin", partition=0, payload=payload, offset=0x10005)
        _, data = self.host_inspect("/docs/sub/data.bin", partition=0, read=True)
        self.assertEqual(data, self.content[:0x10005] + payload + self.content[0x10005 + len(payload):])
        self.filesystem_fixture()
        payload = bytes([0xAB]) * 1024
        output = self.mutate(5, "/data.bin", partition=0, payload=payload, status=-1, fault_write=2)
        self.assertEqual(self.memory(output, 0x0400)[10:12], b"\x02\0")
        _, data = self.host_inspect("/data.bin", partition=0, read=True)
        self.assertEqual(data, payload[:512] + self.content[512:])

    def test_fs_growth_publication_errors_keep_referenced_blocks(self):
        for after in (False, True):
            self.filesystem_fixture()
            before, _ = self.host_inspect()
            self.mutate(5, "/other.txt", payload=b"new", offset=512,
                        status=-1, fault_write=3, fault_after=after)
            stats, entries = self.host_inspect()
            self.assertEqual(entries["other.txt"][3], 2 if after else 1)
            self.assertEqual(stats[0] - before[0], int(after))
            _, data = self.host_inspect("/other.txt", read=True)
            self.assertEqual(data, b"partition1")

    def test_fs_move_error_rollbacks_and_lost_completion(self):
        for after in (False, True):
            for write in (1, 2):
                self.filesystem_fixture()
                self.mutate(8, "/dest")
                before, _ = self.host_inspect()
                self.mutate(10, "/other.txt", destination="/dest/moved", status=-1,
                            fault_write=write, fault_after=after)
                stats, root = self.host_inspect()
                _, children = self.host_inspect("/dest")
                moved = after and write == 2
                self.assertEqual("other.txt" in root, not moved)
                self.assertEqual("moved" in children, moved)
                self.assertEqual(stats, before)
                _, data = self.host_inspect("/dest/moved" if moved else "/other.txt", read=True)
                self.assertEqual(data, b"partition1")

    def test_fs_full_directory_rename_and_read_only_errors(self):
        self.filesystem_fixture()
        for i in range(7):
            self.mutate(6, "/file" + str(i))
        before = self.original
        self.mutate(6, "/full", status=-13)
        self.assertEqual(self.original, before)
        self.mutate(10, "/other.txt", destination="/renamed")
        _, entries = self.host_inspect()
        self.assertEqual(len(entries), 8)
        self.assertIn("renamed", entries)
        self.filesystem_fixture()
        self.fs_execute(self.fs_probe(5, "/other.txt", 1, partition=1), -1, read_only=True)

    def test_fs_read_all_block_sizes_and_nested_paths(self):
        for log2 in range(9, 17):
            with self.subTest(log2=log2):
                self.filesystem_fixture(log2)
                image = self.fs_probe(3, "/docs/sub/data.bin", 1024, 0x10005)
                output = self.fs_execute(image, count=1024, command_extra="peek 0x1400 1\n")
                self.assertEqual(self.memory(output, 0x1000, 1024), self.content[0x10005:0x10405])
                self.assertEqual(self.memory(output, 0x0400)[10:12], b"\x04\0")
                self.assertEqual(self.memory(output, 0x0FFF), b"\xCC")
                self.assertEqual(self.memory(output, 0x1400), b"\xCC")

    def test_fs_read_sector_boundaries_and_eof(self):
        self.filesystem_fixture()
        for offset, count in ((0, 0), (0, 1), (511, 3), (512, 512), (65535, 1000),
                              (len(self.content) - 3, 1000), (len(self.content), 1),
                              (0xFFFFFFFF, 1)):
            with self.subTest(offset=offset, count=count):
                image = self.fs_probe(3, count=count, offset=offset)
                output = self.fs_execute(image, count=count)
                expected = self.content[offset:offset + count]
                done = int.from_bytes(self.memory(output, 0x0400)[10:12], "big")
                self.assertEqual(done, len(expected))
                if expected:
                    self.assertEqual(self.memory(output, 0x1000, len(expected)), expected)

    def test_fs_stat_and_listing(self):
        self.filesystem_fixture()
        for path in ("/data.bin", "docs/sub/data.bin"):
            with self.subTest(path=path):
                output = self.fs_execute(self.fs_probe(1, path, 128), count=128)
                entry = self.memory(output, 0x1000, 128)
                self.assertEqual(int.from_bytes(entry[2:6], "big"), len(self.content))
                self.assertEqual(entry[16:25], b"data.bin\0")
        for path, cursor, name, next_cursor in (("/", 6, b"data.bin\0", 7),
                                                ("/docs", 0, b"sub\0", 1),
                                                ("/docs/sub", 0, b"data.bin\0", 1)):
            with self.subTest(path=path, cursor=cursor):
                output = self.fs_execute(self.fs_probe(2, path, 128, cursor), count=128)
                entry = self.memory(output, 0x1000, 128)
                self.assertEqual(entry[16:16 + len(name)], name)
                request = self.memory(output, 0x0400)
                self.assertEqual(int.from_bytes(request[6:10], "big"), next_cursor)
                self.assertEqual(request[10:12], b"\0\1")
        output = self.fs_execute(self.fs_probe(2, "/docs/sub", 128, 1), count=128)
        self.assertEqual(self.memory(output, 0x0400)[10:12], b"\0\0")

    def test_fs_partition_mount_and_allocation_stats(self):
        for log2 in (9, 16):
            self.filesystem_fixture(log2)
            for partition in (0, 1):
                with self.subTest(log2=log2, partition=partition):
                    output = self.fs_execute(self.fs_probe(4, partition=partition), request=0x0400)
                    base = 512 if partition == 0 else self.partition1
                    blocks = int.from_bytes(self.original[base + 9:base + 13], "big")
                    bitmap = base + int.from_bytes(self.original[base + 13:base + 17], "big") * (1 << log2)
                    used = sum(bool(self.original[bitmap + i // 8] & (1 << (i % 8))) for i in range(blocks))
                    self.assertEqual(self.memory(output, 0x0400)[:8], struct.pack(">II", used, blocks - used))
            output = self.fs_execute(self.fs_probe(3, "/other.txt", 10, partition=1), count=10)
            self.assertEqual(self.memory(output, 0x1000), b"partition1")

    def test_fs_path_and_buffer_errors(self):
        self.filesystem_fixture()
        for path, error in (("/missing", -5), ("/data.bin/child", -6), ("/docs", -7),
                            ("/docs/sub/absent", -5), ("/" + "a" * 48, -10),
                            ("/docs/../data.bin", -2)):
            with self.subTest(path=path):
                self.fs_execute(self.fs_probe(3, path), error)
        for buffer, count in ((0xB600, 128), (0xD920, 128), (0x3FFF, 2), (0xFFF0, 32)):
            with self.subTest(buffer=buffer):
                self.fs_execute(self.fs_probe(3, buffer=buffer, count=count), -2,
                                buffer=buffer, count=0)
        self.fs_execute(self.fs_probe(1, count=127), -2)
        self.fs_execute(self.fs_probe(3, partition=2), -3)
        self.fs_execute(self.fs_probe(3, "/data.bin/"), -6)
        self.fs_execute(self.fs_probe(3, request=0xD920), -2, request=0xD920)

    def test_fs_partial_read_reports_io_failure(self):
        self.filesystem_fixture()
        data_block = int.from_bytes(self.original[self.data_entry + 64:self.data_entry + 68], "big")
        data_sector = 512 + data_block * (1 << self.log2)
        self.original = self.original[:data_sector + 512]
        self.disk.write_bytes(self.original)
        output = self.fs_execute(self.fs_probe(3), -1, count=1024)
        self.assertEqual(self.memory(output, 0x0400)[10:12], b"\x02\0")
        self.assertEqual(self.memory(output, 0x1000, 512), self.content[:512])
        self.assertEqual(self.memory(output, 0x1200, 512), b"\xCC" * 512)

    def test_fs_cmoc_stack_requests_and_wrappers(self):
        if not self.cmoc:
            self.skipTest("CMOC is unavailable")
        self.filesystem_fixture()
        shim = self.directory / "shim.o"
        result = subprocess.run([self.assembler, "-f", "obj", "-o", str(shim),
                                 str(BIOS / "modules/filesystem/filesystem_c_shim.asm")],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        program = self.directory / "c.srec"
        result = subprocess.run([str(self.cmoc), "--void-target", "--srec", "--org=0400",
                                 "--limit=4000", "--no-relocate", "-I" + str(BIOS / "include"),
                                 "-o", str(program), str(BIOS / "tests/simulator/filesystem_c.c"),
                                 str(shim)], cwd=self.directory, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        ram = image_bytes(read_records(program))
        ram[0x0320] = 0
        image = self.fs_probe(0, extra=ram, service_address=0xC100)
        output = self.fs_execute(image, command_extra="peek 0x0320 16\n")
        self.assertEqual(self.memory(output, 0x0320)[0], 0xA5, output)

    def test_fs_invalid_file_extent(self):
        self.filesystem_fixture()
        good = self.original
        for offset, change, error in ((14, b"\x02", -8), (96, b"\0\0\0\x01", -8),
                                     (64, bytes(4), -4), (68, bytes(4), -4),
                                     (68, b"\xFF" * 4, -4), (2, b"\xFF" * 4, -4)):
            with self.subTest(offset=offset):
                disk = bytearray(good)
                start = self.data_entry + offset
                disk[start:start + len(change)] = change
                self.original = bytes(disk)
                self.disk.write_bytes(self.original)
                self.fs_execute(self.fs_probe(3), error)

    def test_fs_bad_partition_metadata_invalidates_mount(self):
        self.filesystem_fixture()
        good = self.original
        for offset in (0, 4, 7, 45):
            with self.subTest(offset=offset):
                disk = bytearray(good)
                disk[self.partition1 + offset] ^= 0x80
                self.original = bytes(disk)
                self.disk.write_bytes(self.original)
                output = self.fs_execute(self.fs_probe(3, "/other.txt", partition=1), -3)
                self.assertEqual(self.memory(output, 0x0310)[2:4], b"\xFF\xFC")

    def test_fs_console_from_bios_menu(self):
        self.filesystem_fixture()
        commands = "run 3000000\nserin 7\r\nrun 300000\nserin l /docs\r\n"
        commands += "run 200000\nserin i\r\nrun 100000\nserin q\r\nrun 100000\nregs"
        output = self.run_cli(self.rom, commands, banked=True)
        serial = bytes(int(byte, 16) for byte in re.findall(r"\[SERIAL TX\].*?0x([0-9a-f]{2})", output))
        self.assertIn(b"MLFS console", serial)
        self.assertIn(b"d sub 00000000", serial)
        self.assertIn(b"Used blocks: ", serial)
        self.assertTrue(serial.endswith(b"\r>"), serial[-100:])
        self.assertIn("DP=00", output)
        self.assertEqual(self.disk.read_bytes(), self.original)

    def test_fs_cf_loaded_diagnostic_and_repeated_return(self):
        if not self.diagnostic:
            self.skipTest("CF diagnostic module was not supplied")
        self.filesystem_fixture(diagnostic=True)
        before, _ = self.host_inspect()
        commands = "run 3000000\nserin 7\r\nrun 300000\n"
        commands += "serin m 1\r\nrun 80000\n"
        for _ in range(2):
            commands += "serin t\r\nrun 500000\n"
        commands += "peek 0xB603 1\nserin q\r\nrun 100000\nregs\n"
        output = self.run_cli(self.rom, commands, banked=True, timeout=60)
        serial = bytes(int(byte, 16) for byte in re.findall(r"\[SERIAL TX\].*?0x([0-9a-f]{2})", output))
        self.assertEqual(serial.count(b"FS diagnostic PASS (allocation balanced)"), 2, serial[-2000:])
        self.assertNotIn(b"FS diagnostic FAIL", serial)
        self.assertTrue(serial.endswith(b"\r>"), serial[-200:])
        self.assertIn("DP=00", output)
        self.assertEqual(self.memory(output, 0xB603), b"\x01")
        after, entries = self.host_inspect()
        self.assertEqual(after, before)
        self.assertEqual(set(entries), {"other.txt"})
        self.assertEqual(self.disk.read_bytes()[:self.partition1], self.original[:self.partition1])

    def test_fs_console_mutation_commands(self):
        self.filesystem_fixture()
        before, _ = self.host_inspect()
        commands = "run 3000000\nserin 7\r\nrun 300000\n"
        for command in ("m 1", "d /console", "n /console/file", "w /console/file hello",
                        "a /console/file world", "v /console/file /console/moved", "c /console/moved",
                        "u /console/moved", "r /console", "q"):
            commands += "serin " + command + "\r\nrun 80000\n"
        output = self.run_cli(self.rom, commands + "regs", banked=True, timeout=60)
        serial = bytes(int(byte, 16) for byte in re.findall(r"\[SERIAL TX\].*?0x([0-9a-f]{2})", output))
        self.assertIn(b"helloworld", serial)
        self.assertNotIn(b"Error:", serial)
        self.assertTrue(serial.endswith(b"\r>"), serial[-200:])
        after, entries = self.host_inspect()
        self.assertEqual(after, before)
        self.assertEqual(set(entries), {"other.txt"})
        self.assertEqual(self.disk.read_bytes()[:self.partition1], self.original[:self.partition1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, type=Path)
    parser.add_argument("--rom", required=True, type=Path)
    parser.add_argument("--symbols", required=True, type=Path)
    parser.add_argument("--filesystem", required=True, type=Path)
    parser.add_argument("--diagnostic", type=Path)
    parser.add_argument("--assembler", default="lwasm")
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--test", help="Run one named test_fs_* method")
    parser.add_argument("--cmoc", default="cmoc", help="Optional CMOC compiler for C ABI checks")
    args = parser.parse_args()
    FilesystemTests.simulator = args.simulator.resolve(strict=True)
    FilesystemTests.rom = args.rom.resolve(strict=True)
    FilesystemTests.symbols = read_symbols(args.symbols)
    FilesystemTests.filesystem = args.filesystem.resolve(strict=True)
    FilesystemTests.diagnostic = args.diagnostic.resolve(strict=True) if args.diagnostic else None
    FilesystemTests.assembler = args.assembler
    FilesystemTests.cmoc = shutil.which(args.cmoc)
    with tempfile.TemporaryDirectory(prefix="microlind-fs-fixtures-") as directory:
        builder = Path(directory) / "make_mlfs_fixture"
        result = subprocess.run([args.cc, "-std=c99", "-Wall", "-Wextra", "-Werror",
                                 "-I", str(BIOS.parent / "mlfs/lib/include"),
                                 str(BIOS / "tests/simulator/make_mlfs_fixture.c"),
                                 str(BIOS.parent / "mlfs/lib/src/mlfs.c"), "-o", str(builder)],
                                capture_output=True, text=True, timeout=30)
        if result.returncode:
            parser.error("could not build host MLFS fixtures: " + result.stderr)
        FilesystemTests.fixture_builder = builder
        inspector = Path(directory) / "inspect_mlfs"
        result = subprocess.run([args.cc, "-std=c99", "-Wall", "-Wextra", "-Werror",
                                 "-I", str(BIOS.parent / "mlfs/lib/include"),
                                 str(BIOS / "tests/simulator/inspect_mlfs.c"),
                                 str(BIOS.parent / "mlfs/lib/src/mlfs.c"), "-o", str(inspector)],
                                capture_output=True, text=True, timeout=30)
        if result.returncode:
            parser.error("could not build host MLFS inspector: " + result.stderr)
        FilesystemTests.inspector = inspector
        loader = unittest.TestLoader()
        loader.testMethodPrefix = "test_fs_"
        suite = (unittest.TestSuite([FilesystemTests(args.test)]) if args.test else
                 loader.loadTestsFromTestCase(FilesystemTests))
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
