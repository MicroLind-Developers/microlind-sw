# S03–S09 implementation and evidence

Recorded 18 October 2026 against the three documents in `plans/`. This extends
the [S00–S02 foundation report](stages.md). The implemented software profile
reaches the CF-booted C1 serial workflow in both simulator engines. K1 physical
qualification remains open: no GAL fit, board execution or physical timing/CF
measurement is claimed. Simulator software bring-up while that gate is pending
is explicitly allowed by the staged plan.

## Requirement → implementation → evidence

| Stage/work packages | Implementation | Actual-target evidence |
| --- | --- | --- |
| S02 regression | `src/memory.asm`, `src/copy.asm`, native ROM entry and generated ABI | Original allocation exhaustion/rollback, mapping, range/atomic-copy, generation retirement, nested entry, stack/register/map sentinels and CMOC client pass in both engines |
| S03.1–6 validated boot | `bios/mlos/{boot,storage,loader}.asm`, `include/images.inc`, `tools/images.py`, deterministic `tests/runtime/mkimage.c` using production host MLFS | CF cold boot; 13 corrupt/missing/truncated/version/size/extent/checksum cases reject before kernel execution in each engine |
| S03.7 bootstrap choice | Restricted immutable root-image ROM provider, retained after filesystem startup | Real init/services/commands/modules load from CF; no sector-zero jump stub or embedded runtime payload |
| S04.1–5 process/context/time/weighted scheduling | `runtime/{process,scheduler,calls}.asm`, scheduling configuration | Non-yielding three-class workload, native E/F/DP/Y/U/V/S/map sentinels, yield/context switch and lower-class progress over 210 ticks |
| S04.6–8 teardown/traps/admission | DYING/pinned cleanup, parent reaping/orphan adoption, unpublished LOADING | Kill/wait, application trap with surviving init, physical exhaustion, malformed load and rollback retain correct frame accounting |
| S05 images/startup/heap | `tools/pack_app.py`, transactional sliced loader, `runtime/{heap,arguments}.asm`, SDK CRT/shim/heap | Assembly one-bank, CMOC one/two-bank and filesystem three-bank programs; argv with quoted spaces, BSS, exit status; 20000-byte spanning allocation survives dispatch and releases two empty frames; bad layout/checksum/exhaustion reject |
| S06 channels/services/waits/lifetime | `runtime/{ipc,services,wait}.asm` | 37-byte messages and 53-byte streams, ring wrap, EMSGSIZE without consumption, producer-close drain/EOF, consumer-close EPIPE, cross-process check/arm/wake, named echo connection and endpoint teardown |
| S07 module format/loading/instance state | `runtime/modules.asm`, `tools/pack_module.py`, `modules/delay.asm` | Bad checksum unwinds unpublished code; one accepted code frame shared by two independently charged instances; failed second bind rolls back; callbacks produce distinct delayed completions |
| S07 asynchronous requests/device ownership | `runtime/driver.asm`, built-in CF/TTY adapters and mocks | Exclusive claim, real CF read/write/collect, pending mocks, cancellation, pinned ownership, controller timeout/quarantine; a replacement owner is refused before reset |
| S07 controller boundary | `runtime/backplane.asm`, versioned two-controller records with unassigned default offsets | RAM-backed target register mocks verify reset-disabled masks, non-clearing normalized bits0–5, independent instances, range/version rejection in both engines; active physical IRQ route remains disabled |
| S08 worker model/protocol/mounts | `services/filesystem.c`, `services/mlfs/{worker,validate}.asm`, shared `mlfs/target/` algorithms | Two CFs with independent workers; injected 1500000-cycle controller wait while healthy-drive metadata completes and all 32 frames are admitted |
| S08 files/locks/cwd/growth | Frontend owned descriptors, per-volume generations, SDK namespace | Create/read/write/copy/rename/delete/directories, forced file relocation/growth, shared readers/exclusive writer, namespace/cwd BUSY, busy-unmount, relative paths and inherited cwd |
| S08 integrity/recovery | Mount ownership/bitmap validator, dirty sequencing, `mlfs/tools/check_image.py` | Consistent dirty target volume is readable and refuses output with EROFS; drive removal isolates failure, explicit recovery creates fresh identities, stale descriptor/cwd fails; host tests cover bitmap repair and crosslink refusal |
| S08 service loss/virtual files | Kernel mount metadata and SDK `/proc` snapshots | Frontend trap withdraws workers; `/proc` listing/read/cwd, process/memory/mount diagnostics and console remain usable |
| S09 init/TTY/shell/commands | `programs/{console_init,shell,command}.c`, `runtime/tty.asm`, `sdk/{mlos,terminal,fs}.c` | Green LED and serial banner before RAM clearing, stage/activity feedback stopping at console handoff, cold boot prompt, argv/BSS/heap CMOC command, quoted literal `>`, adjacent `<`/`>` redirection, file workflow, raw arrow key, Ctrl-C during sleep and accepted file work, stdout drain before prompt, independent UART B logs |
| S09 selected failures | Init/service/job scope cleanup and shell restart policy | First shell exit restarts; second reaches bounded emergency diagnostics; filesystem death preserves diagnostics |

The console test uses real target code and simulator CF/serial devices. It does
not replace OS operations with a host filesystem mock. Only deterministic
latency/media removal and explicit application traps are injected by the runner.
The host offline validator is independently checked against the pristine CF.

## K1/C1 budget and timing record

`runtime-budget.json` is regenerated and enforced, rather than relying on this
snapshot. The final artifact set records:

| Resource | Reservation/observed amount |
| --- | --- |
| Installed RAM | 524288 bytes / 32 frames |
| Whole core/common/discard reservation | 3 frames / 49152 bytes |
| Admissible pool, before service/process/channel allocations | 29 frames / 475136 bytes |
| Runtime core code/data | 14187 / 14336 bytes before fixed handle table |
| Banked handles/channels | 512 bytes at 3800; 640 bytes at 3A00 |
| ROM populated / usable | 2625 / 7168 bytes; 1024-byte I/O hole excluded from 8192 address bytes |
| Common logical/physical reservation | 8192 / 16384 bytes |
| Kernel/emergency usable stacks | 1022 / 254 bytes, separate canaries |
| Observed kernel modified stack span | 41 / 1022 bytes in runtime and console suites |
| Fixed capacities | 8 processes, 64 kernel handles, 20 channel records, 32 heap records, 8 requests, 4 devices, 4 module code records |
| Request storage | One dynamically charged/pinned 16 KiB frame for eight 512-byte buffers |
| Channel/instance storage | Whole 16 KiB frame per data channel and per module instance; permanent accepted module code also charged |
| Fully admitted two-drive concurrency fixture | All 32 frames occupied, zero free; foreground healthy drive still progresses |

The stack fill starts after boot calls unwind and before enabling the timer.
These spans are observations, not worst-case stack proofs. The initial shell,
frontend and command reserve 2048-byte stacks; other packaged programs default
to 1024. There is no promise to admit more concurrent work at the zero-free-frame
fixture: ordinary admission fails cleanly. GUI-stage resource fit will require
its own budget and may require packing smaller channel buffers more efficiently.

At the selected 3 MHz simulator CPU and 3.6864 MHz UART crystal, preload 115 gives
3686400/(32*115) = 1001.739130 ticks/sec. Five ticks nominally span 4.991319 ms.
Time APIs use ticks, not exact milliseconds. Runtime GETPID SWI/RTI measures
856 simulator cycles; the fixture's yield/context switch measures 2221. The
three non-yielding classes produced approximately 71355/21888/11001 application
instruction samples across 210 ticks. Those are progress samples including
program differences, not an exact CPU-share ratio proof. The original harness
records probe/nested cycles 687/1199 and 24 modified kernel-stack bytes.
Physical cycle audit and interrupt-latency measurement remain open.

Boot feedback selects the green power LED after 24 modeled cycles and sends the
first UART A byte after 334 cycles, both before common RAM clearing. Stage/image
labels and a timer-driven dot pulse keep the longer startup visible; the shell
session ends boot output before its banner/prompt. Rejection/panic selects red.
See [the boot timing report](boot-process.md) for the current 7.3-second profile,
transcript and reproducible measurements. Feedback adds four common-address
bytes and no physical frames or init stream channels; the fully admitted
two-drive fixture still progresses with zero free frames.

## Reproduce acceptance

```sh
make -C mlos acceptance BUILD=/tmp/mlos-final \
  SIMULATOR=/tmp/mlos-sim-build/microlind-sim-cli
ctest --test-dir /tmp/mlos-sim-build --output-on-failure
cmake -S mlfs -B /tmp/mlos-mlfs-build
cmake --build /tmp/mlos-mlfs-build -j4
ctest --test-dir /tmp/mlos-mlfs-build --output-on-failure
make -C bios test
```

The MLOS acceptance includes both engines, the 13-case-per-engine boot rejection
matrix and nine host image tests. The MLFS host CTest suite passes all five tests
(including its commander backend); writable host mounts now refuse dirty and
unknown superblock state. Legacy BIOS host tests pass all 14 cases, and its
filesystem module still builds against the shared target sources. Independent
Make and root CMake builds generate matching ROM/kernel/CF bytes. Provenance
retains revisions, dirty/source hashes, tools and simulator/artifact SHA-256.
Suite logs live in each BUILD directory.

The generated `mlos.session` is also booted through the GUI's actual session
loader and realtime backend. Its test checks both configured CPU-model and pacing
clocks are 3 MHz before requiring the prompt. A 1 MHz model reproduces an init
timer-starvation stall despite a 3 MHz GUI pacing selection; the base hardware
profile now explicitly sets 3 MHz, and generated configurations share it.

The accompanying simulator CTest suite passes 222/223 tests. The existing
`BoardLogicTest.MatchesConfiguredHardwareMapForRepresentativeAddresses` fails
because `examples/hw.cfg` lacks the expected LOGIC section; the pre-change
simulator binary reproduces that failure. All added MLOS gate/timer/config/
serial/storage/CPU regression tests pass. Runtime bring-up also found and fixed
microcycle TFR/EXG-to-PC ordering: PC must advance past the postbyte before the
register transfer, rather than incrementing an already replaced target PC.

## Explicit qualification limits

- Physical K1 still needs the [hardware checklist](hardware.md), fitted GAL
  artifacts, real CF/timer integration, gate/status routing and timing evidence.
- The initial module ABI implements trusted polled block callbacks; console
  character/control operations use the built-in TTY adapter. General loadable
  character modules, DMA, real expansion IRQ offsets/routing and actual-card
  rates are not inferred. The disabled normalized controller adapter is ready
  for the final hardware binding; actual-card qualification is S15.
- Runtime filesystems support the declared 512-byte/single-direct-extent profile,
  not 4 KiB blocks or indirect extents. A consistent interrupted dirty volume is
  read-only; unproven structure is unavailable. Explicit offline repair does
  not reconstruct lost file contents or promise power-loss atomic writes.
- PIO completion is the selected write boundary. Physical write-cache/flush
  behavior is unqualified; there is no journaling, FUA or ATA FLUSH guarantee.
- Installed executable/module names are immutable root files and loaded through
  the restricted boot provider. Runtime executable replacement, relocations and
  arbitrary executable search paths are outside this first format.
- There is no general RAM isolation: the physical privilege gate blocks I/O
  writes, while ordinary/common RAM remains writable under the motherboard
  design. MLOS mapping/ownership correctness does not make hostile code safe.
- Desktop/PS2/video/window work starts at S10 onward. The serial terminal uses
  the shared key/control profile; a GUI cell model is not included here.

## S09 performance checkpoint

[Measured improvements](performance-improvements.md) retain C1 functionality and
resource admission. Acceptance includes binary IPC wrap/span cases, finite waits
without IPC mutations, initialized/BSS loads across logical bank boundaries,
existing native context/map/stack contracts and the complete two-drive console
workflow. Pending foreground-load cancellation is additionally verified to free
its PCB/frames before application entry. The frozen responsiveness benchmark
compares both engines against the original S09 baseline.
