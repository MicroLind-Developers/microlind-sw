#!/usr/bin/env python3
"""Check that the simulator's SEX instruction sign-extends B into A."""
import argparse
from pathlib import Path
from check_rom import read_symbols
from test_simulator import SimulatorTests


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, type=Path)
    parser.add_argument("--rom", required=True, type=Path)
    parser.add_argument("--symbols", required=True, type=Path)
    parser.add_argument("--assembler", default="lwasm")
    args = parser.parse_args()
    test = SimulatorTests()
    test.simulator = args.simulator.resolve(strict=True)
    test.rom = args.rom.resolve(strict=True)
    test.symbols = read_symbols(args.symbols)
    test.assembler = args.assembler
    test.setUp()
    try:
        output = test.run_cli(test.probe("sex_probe.asm"), "run 100\npeek 0x0300 4")
        actual = test.memory(output, 0x0300)
        expected = bytes.fromhex("0073FF80")
        print(f"SEX expected {expected.hex().upper()}, observed {actual.hex().upper()}")
        return 0 if actual == expected else 1
    finally:
        test.doCleanups()


if __name__ == "__main__":
    raise SystemExit(main())
