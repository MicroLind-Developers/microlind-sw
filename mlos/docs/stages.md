# S00–S02 implementation and evidence

Historical foundation report. For the implemented CF runtime, current budgets
and S03–S09 evidence, see [runtime-stages.md](runtime-stages.md). Statements below
about pending later stages describe the original S00–S02 snapshot only.

Recorded 17 October 2026. Software base implemented and exercised in the local
simulator; S01 physical GAL delivery/qualification remains open. This is not a
K1 completion report: CF loading and scheduling are S03/S04. No board execution,
GAL fit, or physical timing measurement is claimed.

## Requirements-to-interface-to-test index

| Requirement/work package | Implementation/interface | Evidence |
| --- | --- | --- |
| S00.1 target tools/options, installed 512 KiB | toolchain.lock.json, check_tools.py, provenance.py | pinned LWTOOLS/CMOC check; exact revisions/tree hashes/binary hash retained |
| S00.2 source boundaries | README placement table, bios/mlos versus mlos/src | independent development ROM/core/app images; existing MLFS reused |
| S00.3 build/run/debug, symbols/maps/capture | Makefile/CMakeLists, check_image.py, smoke.py | generated symbols/listings/maps/budget, bounded CLI marker, target tests |
| S00.4 hardware profile | docs/hardware.md, hardware.cfg | stage-3 schematic/architecture inventory; simulator gate/timer fixtures |
| S00.5 contract inventory | contracts.md and table below | generated assembly/C ABI consistency checked |
| S00.6 budgets, evidence owners | layout.inc, budget.json, hardware.md | build bounds; hardware/GAL unknowns assigned to physical qualification |
| S00.7 disposable CF fixtures | fixtures.py + tests/make_fixture.c + production mlfs.c | two independent encodes compared byte-for-byte, malformed variants and hashes |
| S01.1 native frame/DP/mode/stacks | bios/mlos/entry.asm, contracts.md | assembly and runner D/C/E/F/DP/X/Y/U/V/S/map sentinels in both engines |
| S01.2 reset/IRQ/trap/NMI/FIRQ/SWI variants | ROM vector table, emergency handler | stackless reset; timer IRQ; short FIRQ; SWI2/3/trap stops; 100 repeated NMIs; reset from unknown maps |
| S01.3 reason/continuation/nested records | four common LIFO records, fixed ROM continuation PCs | explicit nested SWI; IRQ in app, privileged core and active syscall; depth overflow |
| S01.4 fixed ROM stack/map transition | rom_swi/rom_return | application window0 parameters and restored return frame; common stack guards |
| S01.5 simulator latch/I/O-write gate | simulator Bus, CPU vector signals, builder | six gate/timer tests; all 1024 I/O addresses, normal reads/RAM, deferred/fast/detail cycles |
| S01.6 GAL equations/routing/fit | **OPEN physical work**, hardware.md | inspected routing constraints; board procedure provided; no fitted artifact/result |
| S01.7 shared timer/UART control | bios/mlos/uart.asm, simulator mode7 timer | combined masks/ACR bits retained; timer read ack leaves RX pending; rational tick checks |
| S01.8 entry failures/sentinels | assembly selftest, tests/runner.cpp | invalid copies/maps, nesting overflow, emergency stops and guards |
| S02.1 addressed core/common metadata | layout.inc, maps.txt | build size/map checks and runtime sentinel checks |
| S02.2 whole-frame 0/1/2 reservation | memory_init, frame_alloc_many | reserved owner records, 28-resource exhaustion after initial app allocation |
| S02.3 owner/provisional/rollback/roles | frame and process records | injected failure after two allocations, real exhaustion rollback, foreign-owner denial |
| S02.4 validated mapping/discard parking | bank_map/unmap/free | live resident remap denied; mapped-bank release parks before reuse |
| S02.5 bounded translated copies | user_range/copy_in/out | boundaries at 0000/3FFE/3FFF/4000/7FFF/8000/BFFF/C000/FFFF, 0–256 lengths, source/dest/parameter errors, overlap |
| S02.6 first numbered syscalls | abi.json -> syscalls.inc/syscalls.h | all nine calls exercised by assembly/host target tests and CMOC 0.1.98 client |
| S02.7 opaque identity/ref/pin scheme | 32 generational handle records | invalid/stale/foreign identity, held ref/pin free denial, generation255 retirement |
| S02.8 accounting/metadata budgets | SYS_MEMORY_INFO, check_image.py | byte-accurate output, reclaimed free count, common exposed/physical and ROM overlay counted separately |

The diagnostic has one process/thread context placeholder; no process
scheduler or general image loader exists yet. Every assembly routine's comments
declare its inputs, outputs, clobbers and relevant shared module context.

## Initial resource budget

| Item | Amount |
| --- | --- |
| Installed physical RAM | 524288 bytes, 32 frames |
| Whole reserved core/common/discard | 49152 bytes, 3 frames |
| Admissible pool, including initial application | 475136 bytes, 29 frames (464 KiB) |
| Initial application | 16384 bytes, frame3 |
| Remaining free after diagnostics | 458752 bytes, 28 frames |
| Assembled bank0 core including development selftests | 1766 bytes / 16384 |
| Populated ROM including embedded core/application | 3126 bytes / 7168 usable ROM bytes |
| I/O hole in the 8192-byte ROM address range | 1024 bytes |
| Common address extent reserved through emergency stack | 4608 / 8192 exposed bytes |
| Common frame physical reservation | 16384 bytes, including invisible upper half |
| Entry/frame/handle records | 128 / 256 / 256 bytes |
| Copied parameter/payload buffers | 16 / 256 bytes |
| Kernel/emergency stack usable reservations | 2046 / 510 bytes |

The common extent includes internal holes/headroom; it is not a claim that every
byte in that extent currently contains live metadata. Budgets and addressed
maps are regenerated and enforced for each build. Future process/queue/device
metadata and banked buffers must be charged against the same physical pool.

## Validation record

- The CLI harness prints `MLOS S00-S02 PASS\r\n`, returns to the native application
  with maps `03 02 02 01`, F405 bit7 clear, depth0 and intact stack guards.
- Target tests pass in instruction and microcycle execution, including the CMOC
  client, real allocation exhaustion, full-range atomic copy checks, privileged
  nesting, timer IRQs and bounded failure paths. See `build/contracts.log`.
- Filled-stack observations in the syscall/copy/exhaustion suite: 24 kernel
  bytes and 16 application-entry bytes. These observations exclude CMOC's own
  application call chain and boot selftests, and are not worst-case proofs.
- Simulator-cycle measurements are printed in `contracts.log`. They count the
  complete SWI/RTI sequence: 1105 cycles for probe and 2035 for the nested-test
  call at this build.
  The existing simulator builder uses 1 MHz; target CPU/mode timing still needs
  an HD6309 audit and physical measurement.
- Simulator CTest suite: 218/219 pass, including all six newly added gate/timer
  tests. `BoardLogicTest.MatchesConfiguredHardwareMapForRepresentativeAddresses`
  fails because examples/hw.cfg lacks the expected LOGIC section. The original
  pre-change simulator binary reproduces the same `cfg->logic.present` failure
  from its repository directory. No unrelated fixture was changed to hide it.
- `make -C mlos test SIMULATOR=/tmp/mlos-sim-build/microlind-sim-cli` is the
  software acceptance command. Root/standalone CMake and independent clean
  output directories exercise the same checks; image/fixture hashes establish
  reproducibility. Logs and exact provenance stay in each build directory.

## Contract inventory and next consumers

| Interface | Status/owner or evidence source | Next consumer |
| --- | --- | --- |
| Native frame, bridge reasons, stacks/maps | S01 contracts.md, simulator CPU/source tests; physical audit still open | S04 scheduler/traps |
| Hardware gate/status, actual GAL pins/fit/timing | simulator behavior defined; physical owner: board/GAL work per hardware.md | board K1 |
| MMU reset/readback and installed memory | fixed 512 KiB software profile; physical owner: board qualification | S03 boot information |
| Kernel image header, integrity, boot-info record | pending S03; architecture §§10/14 | ROM CF loader |
| CF boot-partition/root traversal and early provider | pending S03; current MLFS host library/format is authority | S05 startup |
| Syscall IDs/errors/layouts and C bridge | v1 subset in abi.json; tested CMOC 0.1.98 | later syscall subsets |
| Bank handles/ref/pin identity and window roles | S02 representation/reuse frozen for subset | S04 cleanup/S05 heap/S06 IPC |
| Process/thread/exit/trap records and time ABI | initial PID/map placeholder only; pending S04 | scheduling/preemption |
| Application/module images and CMOC runtime | temporary fixed-linked client only; pending S05 | assembly/CMOC loaders |
| IPC/waits/service and descriptor/request identities | pending S06/S07; preserve generation/type/ref principles | services/drivers |
| MLFS filesystem namespace/protocol/recovery | existing host implementation; target integration pending S08 | shell/filesystem service |
| GUI/window/TTY protocol | pending S09/S12; architecture remains policy authority | desktop applications |

The six ROM jump slots are development internals, separate from the existing
menu BIOS jump table. Their offsets and absolute-JMP encoding are checked; S03
must define the production boot/ROM-to-core interface before other images rely
on it. The architecture/planning documents are preserved unchanged.

The subsequent [S09 performance checkpoint](performance-improvements.md) replaces
ROM frame-copy loops with native TFM while preserving these entry contracts.
The same foundation suite now observes687 probe cycles and1199 nested-test
cycles; the earlier timings above remain the original foundation measurements.
