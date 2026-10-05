# CF-loaded Tetris

The game runs as `/tetris.mlp`, compiled with CMOC, using the BIOS register ABI
and the assembly MLFS extension. It needs an initialized VDC, joystick port 1
(or serial controls), and the VIA timers. Physical board validation is pending;
the user has authorized continuing with host and simulator validation.

## Build and launch

From the repository root:

```sh
make -C bios
python3 bios/tools/make_boot_image.py \
    --filesystem bios/build/biosfs.mlp \
    --diagnostic bios/build/fsdiag.mlp \
    --game bios/build/tetris.mlp \
    --output bios/build/tetris-dev.img
```

The builder refuses an existing image unless you explicitly add `--force`.
Replacing the image resets its saved scores and sound setting.

In the simulator GUI, select **HD6309**, load
[`bios/tests/simulator/tetris.cfg`](../../tests/simulator/tetris.cfg) as the
hardware config, then load `bios/build/bios.ihex`. This config includes the
VDC and explicitly mounts `bios/build/tetris-dev.img`; paths resolve relative
to the config. Select BIOS menu **8**, then Enter. The game can also be launched
with **7**, Enter, followed by filesystem-console command **g**, Enter.

CLI launch uses the same files:

```sh
printf 'run 3000000\nserin 8\r\nrun 1000000\nserin q\r\nrun 1000000\nexit\n' | \
../microlind-sim/build/microlind-sim-cli --6309 --ihex \
    --rom bios/build/bios.ihex --config bios/tests/simulator/tetris.cfg
```

This boots, launches, and exits the game. The explicit `\r` injects Enter into
the BIOS serial input. The GUI serial console provides Enter directly. BIOS
and filesystem commands require Enter; game controls respond to individual
characters.

## Controls

| Action | Joystick 1 | Serial |
|---|---|---|
| Move | Left / right | A / D |
| Soft drop | Down | S |
| Rotate clockwise | Button | W |
| Hard drop | Release Up | Space |
| Pause / resume | Hold Up + button for 500 ms; select Resume | P |
| New game | Pause menu | N |
| Toggle sound | Pause menu | M |
| Exit | Pause menu | Q |

Left/right repeat after 200 ms, then every 60 ms. Down repeats every 60 ms.
A recognized pause chord consumes the Up release. Release the chord before
using Up/Down and button in the menu. In the paused menu, serial W/S select
an item and Space chooses it. Letter controls accept either case; CR/LF are
ignored during gameplay. The GUI joystick mapping must drive VIA port A bits
0–4: Up, Down, Left, Right, Button; do not type into the serial input field
while using GUI joystick keys.

The board is 10×20, with a seven-piece bag, clockwise rotation without wall
kicks, immediate locking, next-piece preview, and increasing gravity speed.
Line clears score 40/100/300/1200 × the current level. Soft/hard drops earn
one/two points per row. Every ten lines advances a level; gravity starts at
800 ms and reaches an 80 ms minimum at level 10. Scores saturate at 32 bits.
The five best scores are recorded on game over, New Game, and Exit.

## Display, sound, and storage

The renderer uses the existing 80×25 text mode, two colored text columns per
cell, and a temporarily uploaded solid glyph at character 127. It caches board
cells, numbers, preview, and menu state. Exit restores that glyph, cursor and
color configuration, the prior IRQ hook and masks, and the affected VIA port
configuration and Timer 1 reload latch before returning to BIOS or the filesystem console. Console
launch also restores the previously selected partition. The BIOS menu is
redrawn on return.

Timer 2 provides a rearmed nominal 100 Hz tick at the board's assumed 2 MHz
VIA clock. Timer 1 drives PB7 tones for an original melody and short effects.
The assembly IRQ handler does no C, filesystem, or display work. Game entry
refuses an absent VDC, incompatible descriptors, enabled Timer 1/2 IRQs, or existing Timer 1 free-running/PB7 operation.

`/tetris.dat` on partition 0 has two 64-byte records at offsets **0** and
**512**, in separate physical CF sectors. The development image preallocates
and initializes a 1,024-byte file. If absent, the application allocates two
filesystem blocks and initializes 576 bytes before its first record write.
Each record contains `TET1`, version 1, the sound setting, a wrapping 32-bit
sequence, five descending 32-bit scores, reserved zeros, and an additive
32-bit checksum of its first 60 bytes. All integers are explicitly big-endian.

Load chooses the newest valid complete record. Missing, truncated, or corrupt
records fall back to the remaining valid record or zero scores with sound on.
Save writes the other sector and verifies all 64 bytes by reading them back
before changing the active slot. A failed save displays `Save failed`, retains
session scores, and allows continued play or exit. MLFS is non-journaled;
this scheme does not establish filesystem or CF power-loss atomicity.

## Validation

```sh
make -C bios test-tetris
make -C bios test test-sim test-fs
cmake -S bios -B bios/build/cmake \
    -DSIMULATOR_EXECUTABLE=/absolute/path/to/microlind-sim-cli
cmake --build bios/build/cmake -j2
ctest --test-dir bios/build/cmake --output-on-failure
```

The portable tests perform 942 rules checks and 1,033 input/save checks with
both the host compiler and CMOC on the HD6309. Full integration covers actual
VDC drawing, joystick pins, timer/audio progress, pause handling, hard drop,
tick wraparound, stack canaries, context restoration, persistence after a
restart, corrupt/missing records, and read-only CF failures. Tests always use
disposable disk copies. When sibling GUI backend headers/static libraries and
a C++20 compiler are available, the runner builds a fast headless driver for
these integration checks. Otherwise it uses the CLI for the two portable
target suites and reports the seven GUI backend scenarios as skipped.

Validate the filesystem on the board using
[`plans/filesystem_board_acceptance.md`](../../../plans/filesystem_board_acceptance.md),
then check the game's display geometry, actual timer/pitch, joystick repeat and
pause chord, responsive play during music, persistence across restart, and
repeated game/console entry and exit. These physical results remain pending.
