#!/usr/bin/env python3
"""Create a development MLFS image containing biosfs.mlp and a test partition."""
import argparse
from pathlib import Path
import subprocess
import tempfile

from module_format import unpack_module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--filesystem", required=True, type=Path)
    parser.add_argument("--diagnostic", type=Path, help="Optional fsdiag.mlp acceptance module")
    parser.add_argument("--game", type=Path, help="Optional tetris.mlp game and preallocated save file")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--log2", type=int, choices=range(9, 17), default=9)
    parser.add_argument("--data", type=Path, help="Optional data.bin sample, up to 1 MB")
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--force", action="store_true", help="Replace an existing output image")
    args = parser.parse_args()
    bios = Path(__file__).resolve().parents[1]
    try:
        module = args.filesystem.resolve(strict=True)
        if unpack_module(module.read_bytes())[0] != 0:
            raise ValueError("biosfs.mlp must be a filesystem module")
        diagnostic = args.diagnostic.resolve(strict=True) if args.diagnostic else None
        if diagnostic and unpack_module(diagnostic.read_bytes())[0] != 1:
            raise ValueError("fsdiag.mlp must be an application module")
        game = args.game.resolve(strict=True) if args.game else None
        if game and unpack_module(game.read_bytes())[0] != 1:
            raise ValueError("tetris.mlp must be an application module")
        output = args.output.resolve()
        if output.exists() and not args.force:
            raise ValueError("output already exists; use --force to replace it")
        data = args.data.read_bytes() if args.data else b"Microlind filesystem read test.\r\n"
        if not 0 < len(data) <= 1048576:
            raise ValueError("sample data must contain 1..1048576 bytes")
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".mlfs-image-", dir=output.parent) as directory:
            work = Path(directory)
            builder = work / "builder"
            subprocess.run([args.cc, "-std=c99", "-Wall", "-Wextra", "-Werror",
                            "-I", str(bios.parent / "mlfs/lib/include"),
                            str(bios / "tests/simulator/make_mlfs_fixture.c"),
                            str(bios.parent / "mlfs/lib/src/mlfs.c"), "-o", str(builder)],
                           check=True, timeout=30)
            sample = work / "data.bin"
            sample.write_bytes(data)
            image = work / "cf.img"
            command = [str(builder), str(image), str(args.log2), str(module), "0", str(sample), "32"]
            if diagnostic or game:
                command.append(str(diagnostic) if diagnostic else "")
            if game:
                command.append(str(game))
            subprocess.run(command,
                           check=True, timeout=30)
            image.replace(output)
        print(f"Created {output}: MLFS partition 0 + diagnostics partition 1")
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
