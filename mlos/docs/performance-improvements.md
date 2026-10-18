# S09 performance improvements

Implemented and measured 18 October 2026. The full acceptance suite passes on
both simulator engines. At the same 3 MHz clock, median `echo` completion fell
from 4.286 s to **0.350 s**; 4 KiB `cat` fell from 20.613 s
to **2.959 s**. APIs, file formats, ownership,
preemption and resource admission remain in place. A new additive input-wait
syscall preserves the existing nonblocking input contract.

## Comparison

These are simulated CPU times, using the same full ordered suite, three samples
per command per engine. Enter is injected after the typed line has been echoed.
Command rows measure Enter to complete next prompt. This is an end-to-end
comparison of the two builds, including smaller binaries and filesystem cache
reuse; individual optimization gains are not additive.

| Action | Original median (ms) | Optimized median (ms) | Reduction | Speedup |
| --- | ---: | ---: | ---: | ---: |
| Character echo¹ | 12.781 | 3.149 | 75.4% | 4.06× |
| Backspace¹ | 9.083 | 2.782 | 69.4% | 3.27× |
| Blank Enter → prompt | 147.568 | 11.514 | 92.2% | 12.82× |
| `cd /` | 369.710 | 77.166 | 79.1% | 4.79× |
| Missing command | 237.585 | 51.668 | 78.3% | 4.60× |
| `echo ping` | 4286.039 | 349.614 | 91.8% | 12.26× |
| `pwd` | 4430.697 | 346.572 | 92.2% | 12.78× |
| `mem` | 4286.893 | 351.416 | 91.8% | 12.20× |
| `cat /proc/memory` | 4415.268 | 378.479 | 91.4% | 11.67× |
| `cat` 128 B | 6964.484 | 750.210 | 89.2% | 9.28× |
| `cat` 4096 B | 20613.246 | 2958.758 | 85.6% | 6.97× |
| `ls /` | 16017.914 | 3737.854 | 76.7% | 4.29× |
| Redirect `echo` to file | 9864.602 | 2029.642 | 79.4% | 4.86× |
| Copy 4096 B | 49206.056 | 13702.183 | 72.2% | 3.59× |
| `yield` (100 yields) | 5137.537 | 633.975 | 87.7% | 8.10× |
| Running Ctrl-C | 157.107 | 24.324 | 84.5% | 6.46× |
| Loading Ctrl-C² | 4122.181 | 13.467 | 99.7% | 306.10× |

¹ Typing/backspace each have one sample per engine; these rows are observations,
not distribution estimates. Instruction/microcycle key-echo timings differ by
about 0.83 ms because of interrupt phase. Both engines agree on the command gains.

² Loading Ctrl-C now aborts its unpublished transaction before application
entry, releases the PCB/frames and prints `^C`. The original build ran the command
before acknowledging Ctrl-C. Both tests inject the interrupt 250 ms after loader
admission; cancellation itself is measured from that injection. This is an
intentional correction to the cancellation gap, with a different successful
outcome from the old behavior.

First `echo` result is a median **327.621 ms** after
Enter, versus **4130.445 ms** originally. First 4 KiB
`cat` data appears at **567.604 ms**, versus
**5896.126 ms**. Creation costs remain separate:
first redirection **2.419 s**; first copy
**15.206 s**. Later samples truncate/overwrite their
existing destinations. The frozen results retain min/max and both engines.

## Changes and preserved contracts

- **Sleep until useful work.** Shell/SDK input uses additive call 45
  `SYS_TTY_WAIT`; `SYS_GETC` still returns EAGAIN without blocking. The frontend
  waits on listeners/client/worker endpoints and preserves bounded retry during
  explicit mount/discovery. SDK send retries wait on endpoint readiness, with a bounded sleep fallback
  when partial space cannot fit an atomic message.
- **Bounded bulk loading.** Validate/admit images as before, checksum contiguous
  source runs, map a destination bank once and copy/zero with native `TFM`.
  Spans split at sector and logical-window boundaries. The default image quota
  is 128 bytes per safe point, configurable 1–128. Checksum/layout/stack/argv,
  private loading state, cancellation and rollback remain enforced.
- **Faster native frame copies.** ROM entry, IRQ flattening and return use
  `TFM` after native E/F have been saved. Register/CC/DP/map/stack/privilege and
  nested-entry tests still pass. Fixed ROM service slots retain their addresses.
- **Conditional maintenance.** Empty runnable sets take one PCB pass. Driver
  scans skip without pending requests; cleanup skips without dying processes;
  TTY scans skip without output/close work. IPC readiness changes arm a wake
  scan; finite deadlines are checked even without a mutation. Notifications
  cover channel transfers/close, listener connections, TTY drain and I/O completion.
- **Contiguous copied IPC and bounded TTY output.** Ring spans use `TFM` and split
  at wrap; validated copies remain kernel-mediated. Public 512-byte IPC limits,
  message atomicity, short-buffer behavior and EOF/drain semantics remain. TTY
  drains up to 16 bytes per channel visit/16 total, rotating the cursor for fairness.
- **Direct cwd snapshots.** The SDK obtains cwd text and frontend/volume
  generation from existing kernel APIs. It still rejects unavailable/stale
  cwd and preserves `/proc` behavior. Prompt generation needs no filesystem RPC.
- **Worker-owned read-through cache.** After validation, reuse the 8192-byte
  reached bitmap as 16 sector buffers. Cache metadata is 133 bytes in existing
  private backing below 0400. Device/volume identity is implicit in the worker's
  exclusive claim and lifetime. The first read of every request reaches actual
  media, including hits. Every write attempt/error invalidates all entries;
  recovery starts a fresh worker/cache. No deferred writes or validation bypass.
- **Faster bounded CF PIO.** Native `TFM` replaces the per-byte dispatch loop;
  the default quota is 128 bytes/controller/pass. It divides 512 and is capped at
  256. The 128-byte transfer needs fewer instruction cycles than the original
  64-byte loop. Requests still snapshot writes, collect reads, settle accepted
  work before reuse and retain the same cancellation/timeout policy.
- **Smaller common commands.** `echo`, `pwd`, `ls`, `cat`, `cp` and `mem` compile
  selected branches of the same source. SDK/startup/standard streams/redirection,
  command names/arguments and resident/stack declarations are unchanged. The
  full command image retains diagnostics and less frequent commands.

These changes follow [architecture §§2, 3, 6, 7](../../plans/MLOS_Architecture_Draft.md) and
[guidelines G04/G06/G07/G09/G11](../../plans/MLOS_Implementation_Guidelines.md):
blocked processes sleep; copies remain bounded and owned; publication is
transactional; services stay outside the core. No new physical frame is reserved.
Existing syscall numbers/parameter layouts and on-disk MLFS/MLX/MLD encodings
are unchanged. The existing 1 kHz timer, five-tick quantum and 4:2:1 class phases
are unchanged.

## What remains expensive

| First `echo` sample: elapsed from Enter | Optimized (ms) |
| --- | ---: |
| Enter acknowledgement | 7.161 |
| Spawn syscall | 11.388 |
| Image loaded | 302.013 |
| Child entry | 306.326 |
| Application main | 324.644 |
| First command output | 327.621 |
| Child exit | 332.413 |
| Complete next prompt | 349.614 |

The first `echo` trial makes **25 syscalls**, versus 549
originally, and takes **96 active loader visits** versus 501.
The smaller image installs **10,632 initialized bytes** and
**12,358 total bytes including BSS/argv**, versus 14,415/16,141.
ROM reads fall from 33 to 25. It still validates and loads afresh.

A one-second settled idle window now has **zero syscalls** and
**25.1% `SYNC` wait time**, versus 319
syscalls and zero wait time in the original window. The remaining timer/ROM/core
work still consumes about 75% of idle cycles at 1 kHz. The timer delivered
1002 ticks in that window. This is progress, not a low-overhead
idle implementation.

The longest pre-instruction IRQ-masked interval in the representative `echo`
trial is **13.947 ms**; its I-mask is set during
**79.8%** of measured cycles. Longer
preflight/argument/IPC transactions and IRQ bridge costs remain candidates for
further work. The goals for ordinary command startup, blank prompt and Ctrl-C
were met in this sample suite; three samples do not establish worst-case or
percentile latency under every concurrent workload.

Bulk file writes still do conservative metadata/dirty-state work and copied
service round trips. A 4 KiB copy taking 13.7 s remains slow. Further filesystem
continuation/batching work should preserve writer exclusion, dirty recovery and
partial-I/O semantics, and be measured separately. Tick-based time still counts
serviced timer interrupts, so coalescing during masking is not fully eliminated.

## Size and boot effects

Core **14187/14336 bytes**, leaving
**149 bytes** before the handle table; ROM
**2625/7168 bytes**. Common reservation remains 8192 logical
bytes/one 16 KiB physical frame. New maintenance/loader scratch occupies 9 previously
unused bytes within that reservation. Worker cache buffers overlay validation
memory and add no frame. The two-drive acceptance workload still reaches all 32
frames while healthy storage progresses.

`echo.mlx` is **10,688 bytes**,
versus 14,471 bytes for its original shared command image. Full link maps and
all command hashes remain with the build. Cold boot to first prompt is now
**7.270289 s instruction /
7.268581 s microcycle**, versus the
original pristine 30-entry 25.270843/25.305735 s profile. See the
[updated complete boot timing](boot-process.md).

## Validation and runnable image

`make -C mlos acceptance BUILD=/tmp/mlos-perf-after
SIMULATOR=/tmp/mlos-sim-build/microlind-sim-cli` passed:

- Original native syscall/register/map/stack and CMOC contracts on both engines.
- Preemption, ownership, handles, heap, IPC, modules, requests and quarantine.
- New binary stream spans/wrap at 263/511-byte capacities, including 256-byte
  copy splits; initialized data and BSS across 4000/8000 bank boundaries; finite
  wait deadline without IPC mutations.
- Corrupt-boot rejection matrix; nine host image/repair cases.
- Complete console workflow: quoting, redirection, file growth/locks, cwd,
  two-drive progress at zero free frames, dirty/read-only handling, recovery,
  stale handles, background input rejection, running/file cancellation,
  service loss with diagnostics and one shell restart.
- GUI session/realtime backend boot with both CPU/pacing at 3 MHz.

The responsiveness suite additionally passed 96 trials on private disk copies,
with exact file output, persisted copy/redirection contents, stack guards and
pending-launch frame/PCB reclamation checked. The concurrency test now observes
healthy-drive completion while CF 2 is pending instead of sampling a status gap
when text finally prints. The service-fault test wakes the now-sleeping frontend
with real work before injecting the same trap. Boot feedback still pulses;
the test no longer demands an obsolete fixed dot count as validation gets faster.

A separate runnable build is in `mlos/build/performance/`; load
[`mlos.session`](../build/performance/mlos.session) in the GUI and choose True Run.
Its target hashes match the measured build. The existing `mlos/build/console.img`
and its user files were preserved. Reproduce with:

```sh
make -C mlos response-profile BUILD=build/performance \
  SIMULATOR=/tmp/mlos-sim-build/microlind-sim-cli
```

[Optimized measurements](measurements/command-responsiveness-optimized.json)
retain target/tool/simulator hashes, both engines' summaries, representative
cycle/source/syscall profiles, resource budgets and cold-boot timings.
[Original baseline](command-responsiveness.md) retains the pre-optimization data.
All times are simulated at 3 MHz on immediate-response CF/UART models; physical
media/UART timing and GUI host throughput require their own measurements.
