# MLFS BIOS extension and CF-loaded Tetris

## Summary

The game is feasible with the existing VDC, joystick, and speaker hardware. The agreed approach is to build and verify a full runtime MLFS extension in 6309 assembly first, then build the game logic in C.

The BIOS will load `/biosfs.mlp` and `/tetris.mlp` from MLFS partition 0. Filesystem operations run from RAM, leaving ROM responsible for startup, hardware services, and bootstrap loading. Card formatting remains with the existing host tools.

## BIOS, loading, and interfaces

- Repair the existing ROM layout: the assembled image currently emits 209 bytes into `$F400–$F7FF` and overlaps three vector-table bytes. Preserve existing utilities, relocate font/data into available upper ROM, and add build checks for address overlap and reserved regions.
- Preserve existing BIOS jump-table indices. Add a separate versioned register-ABI service table at `$F880`, covering the hardware primitives needed by RAM modules: CF reads/writes, serial, joystick, VDC access, and IRQ-handler installation.
- Implement a compact read-only bootstrap reader in ROM using the existing 512-byte storage buffer. Validate MLPT/MLFS versions, superblock checksum, partition bounds, and a named root-directory file stored in one contiguous extent. Support all existing block sizes, 512 bytes through 64 KB.
- Define a 20-byte, big-endian module header: `MLP1` magic; six 16-bit fields for ABI version, module kind, load address, entry offset, payload size, and memory size; then a 32-bit additive payload checksum. Validate the complete load before execution and zero the uninitialized memory tail.
- Reserve `$4000–$BFFF` for the filesystem extension and `$0400–$3FFF` for the game or diagnostic program. Protect BIOS buffers, driver state, and stack; enforce these limits during packaging and loading.
- Module entry receives BIOS and filesystem service-table pointers in `X` and `Y`. Assembly entry bridges preserve the BIOS calling context and provide a clean return path.
- Add BIOS menu entries for Tetris, the MLFS console, and filesystem diagnostics. Load the extension on first use; invalidate it after the destructive RAM test.
- Guard the existing raw-sector MLOS boot path so it cannot execute an MLPT sector as code. Leave MLOS application loading outside this project.

## Assembly filesystem extension

- Implement partition mounting, directory listing, file reads/writes, creation, deletion, renaming/moving, directory creation/removal, and allocation statistics. Preserve MLFS 1.1.0 disk compatibility and existing host APIs.
- Use fixed 512-byte sector buffers and explicit structure offsets. Stream filesystem blocks rather than allocating whole blocks; retain 32-bit file offsets and checked LBA28 addressing.
- Expose a versioned RAM service table with shared assembly definitions and C wrappers. Requests carry paths, buffers, 16-bit transfer counts, and 32-bit offsets; return a signed status and transferred count.
- Support automatic file growth while retaining one contiguous extent: extend into adjacent free blocks, otherwise allocate a larger run, copy existing contents, update the directory entry, and release the old run. Zero gaps created by writes beyond EOF.
- Reject unsupported fragmented/indirect layouts explicitly. Report allocation failure when no sufficiently large contiguous run exists.
- Add bounded CF sector writes with completion/error checks. Roll back new allocations on recoverable failures; retain MLFS’s existing non-journaled storage model.
- Provide a serial console for mount, list, read/write, create, remove, rename, and statistics. Provide a CF-loaded diagnostic program that tests operations on a separate test partition.
- Supply a reproducible disk-image builder using the host MLFS library, including the extension, game, diagnostics, and save-file allocation.

## Game

- Compile portable C game logic with CMOC; use assembly for module entry, BIOS bridges, rendering, timers, and speaker playback.
- Implement a 10×20 board, seven tetrominoes, clockwise rotation without wall kicks, collision, immediate locking, line clearing, next-piece preview, score, increasing speed, and game over. Use a seeded seven-piece bag for reproducible tests.
- Default scoring: 40/100/300/1200 × level for clearing 1/2/3/4 lines; soft drop earns one point per row and hard drop two. Start at level 1, advance every ten lines, and reduce gravity from 800 ms to an 80 ms minimum.
- Render colored solid blocks using one uploaded glyph and two text columns per board cell. Show score, level, lines, next piece, and numeric high scores alongside the board. Redraw changed cells and restore display state on exit.
- Use joystick 1: left/right move, down soft-drops, button rotates, and an up tap hard-drops. Recognize hard drop on up release so holding up+button for 500 ms can open the pause menu without dropping.
- Provide Resume, New Game, Sound, and Exit in the pause menu. Apply edge detection and horizontal repeat: immediate movement, then 200 ms delay and 60 ms repeat.
- Use VIA Timer 1 for nonblocking PB7 tones and Timer 2 for a rearmed 100 Hz IRQ tick. Advance an original single-voice melody and effects in a short assembly handler; effects temporarily interrupt the melody. This timer split follows the [VIA datasheet](https://www.westerndesigncenter.com/wdc/documentation/w65c22.pdf).
- Save five numeric high scores and the sound setting in `/tetris.dat`, using two alternating checksummed records. Missing or corrupt saves use defaults; save failures remain recoverable.

## Validation and acceptance

- Build BIOS, extension, game, and diagnostics through standalone Make/CMake entry points. Check module bounds, ABI versions, checksums, stack usage, and ROM address allocation.
- Test bootstrap loading with missing files, invalid metadata, bad checksums, oversized modules, and CF failures.
- Use `../microlind-sim/build/microlind-sim-cli` for automated execution of the actual BIOS and RAM-module assembly against disposable disk images. Retain physical board checks for the real peripheral timing and CF interface.
- Verify assembly filesystem operations on your board before beginning gameplay implementation. Use host-generated fixtures for every supported block size, then inspect target-modified images with the existing host library.
- Cover adjacent growth, relocation growth, exhausted space, partial-sector writes, zero-filled gaps, nested directories, rename conflicts, and empty/nonempty directory removal.
- Host-test the same C gameplay logic for rotations, collisions, drops, consecutive line clears, scoring, progression, and top-out.
- On the complete board, verify joystick repeat/chords, responsive gameplay during music, display updates, persistence across restart, and repeated game/console entry and exit.
- Hardware assumptions are the current 2 MHz VIA clock, working VDC text mode, joystick port 1, and byte-wide LBA28 CF interface. Hardware milestones require successful board results; assembly and host tests alone do not establish peripheral correctness.

## Next stages

The board checkpoint remains required: on continuation, the user confirmed that
the hardware checks have not yet been run and asked to keep this checkpoint.
Follow [the board acceptance guide](filesystem_board_acceptance.md) for the
build/image commands, terminal sequence, and pending result table. Prepare all
eight block-size images before the hardware session; preparation does not mark
the board milestone complete.

After successful board validation, implement the game in these increments:

1. **Portable rules and tests.** Add `bios/modules/tetris/` with a C board and
   piece model, deterministic seven-piece bag, movement/rotation, immediate
   locking, line compaction, scoring, level progression, and gravity interval.
   Compile the same rules with the host C compiler and CMOC. Test wall/floor
   collisions, rejected rotations, consecutive clears, drop points, and spawn
   top-out before attaching hardware.
2. **Loaded application and display.** Add a context-preserving assembly entry
   bridge, validate the BIOS/filesystem descriptor versions and entry counts,
   and package `/tetris.mlp` within `$0400–$3FFF`. Add Make/CMake targets and
   include the game in the development image. Render the board in the existing
   80×25 VDC mode with direct character/attribute writes, one saved/uploaded
   solid glyph, a next-piece preview, and status text. Cache rendered cells to
   limit writes; restore the glyph and modified display configuration on exit.
   Verify launch, display writes, failure return, and repeated entry with the
   simulator. Keep application state and render caches out of BIOS/FS buffers.
3. **Tick and controls.** Install an RTI-ending module handler using the existing
   IRQ service and use Timer 2 for the 100 Hz tick. Save the old IRQ handler,
   IRQ filter, interrupt masks, and affected VIA configuration before enabling
   the tick, and restore them on every exit path. Read the tick atomically and
   test counter wraparound. Keep collision, drawing, and filesystem calls in
   the main loop. Apply the existing joystick service's pressed-bit mask to
   movement repeat, rotation edges, soft drop, hard drop on up release, and the
   500 ms up+button pause chord; suppress a drop after a recognized pause chord.
   Add pause-menu selection and host tests for the input state machine.
4. **Nonblocking sound.** Drive Timer 1/PB7 independently of the Timer 2 tick.
   Use precomputed tone reloads and a short original melody; advance durations
   and effects from the IRQ without C calls or BIOS blocking beeps. Silence
   and restore the port/timer configuration on exit. Verify tick progress during
   melody/effects and sound-off behavior in the simulator, then timing on-board.
5. **Persistence and complete integration.** Encode two fixed-size save records
   explicitly, with version, sequence, five 32-bit scores, sound setting, and
   checksum. Read both and select the newest valid record; write only the other
   slot and check the transferred count. Keep the earlier valid record usable
   after an interrupted save. Add corrupt/missing/truncated-save and write-error
   tests through the actual filesystem wrappers. Finish the BIOS launch/menu
   path while checking the remaining ROM space, then run the complete physical
   game acceptance checks listed above.

Use fixed allocations and small stack frames throughout: the application has
15 KB of RAM and shares the BIOS's 1 KB stack with filesystem calls and IRQ
frames. Check the CMOC link map and generated assembly as each increment grows.
Use the requested input/output/clobbers comment headers for new assembly
routines. Each increment must build and pass its relevant checks before the
next increment starts.

## Implementation progress

Started on branch `fix-filesystem_tetris`.

- [x] Repair ROM layout and add assembly assertions plus image validation.
- [x] Make the standalone Make and CMake builds use one image layout.
- [x] Add versioned register services, nonblocking serial input, and IRQ installation.
- [x] Add bounded CF writes and post-transfer status checks.
- [x] Prevent the legacy raw boot entry from executing an MLPT sector.
- [x] Define and package MLP1 modules with host regression tests.
- [x] Add CLI simulator integration tests for startup, CF reads/writes and failures, the MLPT guard, VDC access, serial polling, and VIA timer IRQ dispatch.
- [x] Implement the read-only MLFS bootstrap reader and module launcher.
- [x] Build/package the assembly filesystem extension with mount, nested-path stat/list/read, and allocation statistics.
- [x] Add shared assembly/C interfaces, CMOC bridges, a serial console, and a host-library development image builder.
- [x] Add filesystem writes, growth, creation/deletion, rename/move, mkdir/rmdir, and mutation diagnostics.
- [x] Prepare the board acceptance guide and eight block-size CF images with an artifact checksum manifest.
- [ ] Verify CF and filesystem operations on the board before game implementation.
- [ ] Implement and validate the C game, rendering, music, and persistence.

The foundation and read-only bootstrap loader have been assembled,
host-validated, and executed in the HD6309 simulator. `make -C bios test-sim`
uses private ROM/RAM fixtures and temporary CF images, including checking
target-written sectors on the host. Boot fixtures are produced by the existing
host MLFS library. The loader supports all eight block sizes, one contiguous
root-file extent, and the host formatter's bitmap/root/data ordering. Menu
option 7 launches the built `/biosfs.mlp` serial console. Runtime
services handle nested directories, 32-bit file offsets, EOF/sector boundaries,
partial-read failures, and allocation counts using a fixed sector buffer. Their
CMOC bridges have been executed with real stack-allocated C requests/buffers.
The development image builder includes a separate diagnostics partition.
The extension now appends six mutation services without changing earlier
indices. They use a separate bitmap-sector cache, verify old allocation bits,
grow adjacent extents or relocate/copy/publish/free, zero gaps, and retain
confirmed partial-write counts. Directory slots have fixed initial capacity.
The console exposes mutations and loads `/fsdiag.mlp` with `t`; this real CMOC
module exercises partition 1 and checks allocation balance after cleanup.
Simulator checks use production host-library reads of modified images and
inject failed writes before/after media completion, including metadata readback.
MLFS remains non-journaled; interrupted operations may require allocation
repair. The diagnostic refuses an existing `/fsdiag` namespace.
The simulator's corrected `SEX` behavior has been verified with a freshly
built CLI and the saved positive/negative sign-extension probe. The C ABI
diagnostic now uses ordinary C comparisons without the emulator workaround.
Menu text was compacted to fit the loader in ROM while retaining the utilities.
No BIOS has been flashed and no physical CF device has been read or written
during this work. The next milestone is physical board validation: use the
built BIOS/development image, select menu 7, run `t` twice, confirm both
`FS diagnostic PASS (allocation balanced)` messages, then `q` back to BIOS.
Physical board validation still precedes gameplay implementation.

The prepared `bios/build/board-acceptance/` bundle contains `bios.ihex`,
`biosfs.mlp`, `fsdiag.mlp`, eight `cf-<block-bytes>.img` fixtures, an explicit
serial-only simulator config, and `SHA256SUMS`. Both partitions and all bundled module/sample file contents have
been read back with the production host MLFS library. All artifact
hashes and the copied ROM layout pass validation. The user confirmed that
physical checks are still pending; no gameplay code has been started.

A reported simulator menu-entry problem exposed a serial input edge case:
after CRLF input, the remaining LF became the first byte of the next menu
command and caused an unrecognized selection. Menu input now discards LF.
The GUI's shared session backend reproduces the failure with the original
BIOS and enters the mounted MLFS console with the corrected BIOS, including
with VDC removed. The bundle BIOS and its checksum have been refreshed without
replacing the CF fixtures.

The follow-up `Module load error: 0x02` is independently reproduced by attaching
the sibling simulator's legacy `examples/sim.img` (whose magic is `TPLM`).
Attaching `cf-512.img` succeeds. A tracked acceptance config and a copy in the
bundle explicitly select the intended current image, avoiding an implicit
replacement when changing GUI hardware configs. This is simulator validation;
physical board results remain pending.

After the serial input fix, all 18 BIOS simulator groups pass. A headless run of
the GUI's shared session backend with the explicit serial-only config also
passes option 7, two CF-loaded diagnostic runs, and `q` back to BIOS using a
disposable copy of the acceptance image.
The user has now confirmed that filesystem-console entry works in the simulator
GUI with the corrected setup. Physical board acceptance remains pending.

Current validation passes 14 host tool tests, 18 BIOS simulator groups, and
24 filesystem simulator groups, including the compiled CF-loaded diagnostic
and console mutation commands. The standalone SEX check also passes. Make
and CMake produce identical `biosfs.mlp` and `fsdiag.mlp` packages. The generated
`bios/build/cf.img` includes both modules and the separate diagnostics partition.
