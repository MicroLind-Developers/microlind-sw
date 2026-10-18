# S09 command responsiveness analysis

This is the original S09 baseline, measured 2026-10-18 before optimization.
See [implemented improvements and comparison](performance-improvements.md) for
the current build. Ordinary command startup and
filesystem round trips dominate the delay. Typing is responsive when the shell
is waiting for input, but a tiny command still needs about **4.29 seconds** and
a 4 KiB `cat` needs about **20.6 seconds** at the configured 3 MHz.

This change adds a host profiler and baseline evidence. It makes no runtime
performance changes. The next useful work is a focused performance checkpoint
before adding more shell functionality.

## Measured user experience

Times below are **simulated seconds at 3 MHz**, from injecting Enter after the
command line has already been echoed. First result excludes Enter's CR/LF;
next prompt includes command completion and terminal restoration. A dash means
the command intentionally produces no result text. Three sequential samples
were taken on each simulator engine.

| Command | First result (s) | Next prompt median (s) | Prompt min–max (s) | Microcycle median (s) |
| --- | ---: | ---: | ---: | ---: |
| Enter on an empty line | — | 0.148 | 0.137–0.148 | 0.148 |
| `cd /` (builtin) | — | 0.370 | 0.370–0.372 | 0.370 |
| `no-such-command` | 0.109 | 0.238 | 0.235–0.238 | 0.238 |
| `echo ping` | 4.130 | 4.286 | 4.286–4.287 | 4.286 |
| `pwd` | 4.268 | 4.431 | 4.431–4.431 | 4.431 |
| `mem` | 4.128 | 4.287 | 4.285–4.287 | 4.287 |
| `cat /proc/memory` | 4.227 | 4.415 | 4.415–4.415 | 4.415 |
| `cat /perf-small` (128 B) | 5.871 | 6.964 | 6.964–6.965 | 6.964 |
| `cat /perf-large` (4096 B) | 5.896 | 20.613 | 20.400–20.697 | 20.613 |
| `ls /` | 4.141 | 16.018 | 16.006–16.020 | 15.935 |
| `echo ping > /perf-out` | — | 9.865 | 9.859–12.911 | 9.859 |
| `cp /perf-large /perf-copy` | — | 49.206 | 48.794–54.328 | 49.195 |
| `yield` | — | 5.138 | 5.138–5.138 | 5.138 |

Character echo was **12.781 ms** and complete backspace
feedback **9.083 ms**, each sampled once on each engine.
For the first `echo ping` trial, Enter's first acknowledgement byte appeared at
**18.305 ms**, but the first command result arrived at
**4130.445 ms**. Early echo therefore does not imply the
command is about to run.

`ls /` lists 32 installed/fixture root entries plus the virtual mount entries.
Redirection and copy create a new destination in sample 0; subsequent samples
truncate and overwrite it. Their distributions mix these two workloads:
redirection first creation took **12.911 s**, and
copy first creation **54.328 s**. These are not cache
warmup measurements. Every command reloads its executable on every sample.

`yield` is also an external command, so its 5.14 s result includes loading,
startup and the command's 100 explicit yields; it does not measure the
latency of a single `SYS_YIELD`.

## Where the four seconds go

These are disjoint elapsed phases of the first `echo ping` sample, summing to
**4286.039 ms**. They include all other processes, interrupts and
kernel work occurring during each interval.

| Interval | Duration (ms) |
| --- | ---: |
| Enter handling, parse, spawn request | 46.035 |
| Spawn preflight and image loading | 4002.532 |
| Publish, foreground handoff, first child instruction | 6.715 |
| CRT and standard I/O setup | 67.992 |
| Command body and standard I/O close | 23.926 |
| Exit, reap, terminal restore, cwd query, prompt | 138.839 |

The spawn/loading interval is **93.4%**
of total latency. The child's own command body is short; even the entire time
executing unprivileged command instructions is only **8.963 ms**.

The shared command image is **14,471 bytes**, with 14,415 initialized payload
bytes and 1,598 BSS bytes. A separate 128-byte argv snapshot is installed
when loading completes. `echo`, `pwd`, `cat`, `cp` and the other common commands
all install that same executable under different names. The loader performs
**16,141 single-byte stores**, including those 128 argv bytes, through
`image_store` and calls
`image_byte` **14,415 times**. The profiler observed **501 active-loader visits** out of
**538** total `loader_progress` visits in this trial. The configured quota is
at most 32 image data/BSS bytes per safe point; the final argument installation
is additional work in the last visit.

Source attribution is **self time**, not inclusive call time. It gives a second
view of the same sample and must not be added to the elapsed phase table.
Unprivileged code is attributed to its process, including linked SDK code,
rather than to individual C source files:

| Executing source/domain | Self time (ms) |
| --- | ---: |
| `core/process.asm` | 1483.381 |
| `rom/entry.asm` | 958.034 |
| `core/scheduler.asm` | 574.239 |
| `core/tty.asm` | 328.748 |
| `core/driver.asm` | 187.022 |
| Filesystem process (including SDK) | 161.378 |
| `core/copy.asm` | 107.312 |
| `core/ipc.asm` | 105.220 |
| `core/wait.asm` | 98.712 |
| `core/memory.asm` | 68.773 |
| `core/services.asm` | 35.361 |
| `rom/compactflash.asm` | 20.295 |

`image_byte` alone accounts for 644.337 ms of core instruction time, and
`image_store` for 441.187 ms. Together they consume about 1.09 seconds before
counting loader loop control, validation, safe-point work or entry/return.
`image_store` recalculates the bank and writes MMU2 for every byte.

The ROM CF sector routines account for only **20.295 ms**,
about **0.47%** of the
`echo` trial, across 33 sector reads. That is executing time in
those ROM routines, not a separate physical media latency measurement.
The current simulator responds without injected CF delays. Optimizing the raw
PIO transfer alone cannot remove a multi-second command launch.

Source: [process loader](../runtime/process.asm),
[scheduler safe points](../runtime/scheduler.asm),
[ROM entry and return](../../bios/mlos/entry.asm).

## Polling consumes the idle budget

In a one-second settled idle window, the profiler observed **zero cycles waiting
in `SYNC`**. About **52.7%**
of cycles executed core instructions and
**39.3%** ROM instructions.
There were **319 syscalls**, including 64
`SYS_GETC`, 128 `SYS_SLEEP`, and repeated frontend receive/accept attempts.
This is an idle-shell observation with the filesystem service online, not a
measurement of an application spinning in a busy loop.

The [shell](../programs/shell.c) polls `SYS_GETC` and sleeps one delivered tick
on `EAGAIN`. The [filesystem frontend](../services/filesystem.c) likewise scans
clients and sleeps one tick each pass. During `echo`, the frontend alone makes
**521 of 549 syscalls**
even though that command body never reads a file. Entry bridges, scheduler scans,
TTY scans, driver progress and wait scans repeatedly run around this activity.

For `echo`, the pre-instruction I-mask was set during
**93.5%** of measured cycles. The longest
observed contiguous masked interval was **17.462 ms**.
The trial delivered **1884 timer ticks in 4.286 s**,
versus the timer's nominal approximately 1 kHz. The timer model uses a pending
bit, so multiple expirations can coalesce while IRQs are masked. Kernel `TICKS`
counts serviced interrupts, rather than reconstructing all elapsed periods.
This also makes tick-based sleeps/deadlines diverge from elapsed simulated time
under load. Mask measurements are instruction-granularity observations; they
are not a physical board interrupt-latency qualification.

Source attribution for `rom/entry.asm` includes both syscall and IRQ bridges.
It must not be described as pure interrupt overhead. The separately reported
`irq_entry` domain contains the CPU's IRQ entry step, excluding the subsequent
ROM/core handling.

## Filesystem and prompt costs continue after loading

Even a blank line needs a median **147.568 ms** to redisplay
the prompt. The shell calls `fs_getcwd` at every prompt. Outside `/proc`, that
uses `SYS_CWD` followed by a copied filesystem RPC; the request and response are
both fixed 400-byte packets. In the first blank-line trial, `ipc.asm` alone
accounts for **57.827 ms**.

The filesystem client/frontend/worker path repeats these round trips for open,
read, write, metadata and close. Application data requests are at most 256 bytes;
the worker submits 512-byte block requests through the asynchronous driver.
For the first 4 KiB `cat`, the profiler counted
**3,270 total syscalls** and
**160 I/O submissions**, including metadata and
EOF/open/close handling. The child reaches application main at
**4.149 s**, yet the next prompt
does not appear until **20.400 s**.

In that sample, `ipc.asm` costs 2.576 s, scheduler code 2.880 s, and TTY code
1.913 s of self time; only 70 ms executes in the unprivileged worker. The IPC
ring transfer loops over individual bytes and recomputes ring positions and
capacity checks, while validated user copies already use `TFM`.

TTY output also drains at most four bytes per channel visit, within a 16-byte
output budget. For bulk `cat`, that adds repeated full safe-point work. The
UART model makes TX ready immediately; these measurements do not include a
physical serial line's baud-rate limit. A baud-rate increase alone does not
address the measured software costs.

Source: [filesystem SDK](../sdk/fs.c), [frontend](../services/filesystem.c),
[worker](../services/mlfs/worker.asm), [IPC ring copies](../runtime/ipc.asm),
[TTY budgets](../runtime/tty.asm).

## Cancellation differs during loading

After `sleep 5000` has reached its long sleep, Ctrl-C takes a median
**157.107 ms** to return a complete prompt; the first error
output appears at **28.587 ms**. Command startup is
excluded from this cancellation interval.

A second test presses Ctrl-C 250 ms after the loader becomes active. The shell
has not transferred foreground ownership yet. The first command output arrives
about **3.824 s after Ctrl-C**, and a
stable prompt after **4.122 s**. The observed
output is:

```text
cancelled
/ > ^C
/ >
```

The command actually ran. Ctrl-C recorded an interruption of the shell's input
line, then the shell consumed it after the child completed. This is a concrete
cancellation gap during pending spawn, in addition to the latency problem.
A foreground launch needs a cancellation identity before the child is runnable.

## Proposed optimization order

1. **Remove idle polling and unnecessary safe-point scans.** Use existing wait
   readiness for frontend listeners/client/worker channels. Add a compatible
   blocking/readiness path for TTY input. Re-evaluate idle maintenance triggers
   while keeping device deadlines, output drain and cancellation live. This
   reduces work both at rest and during every command load. First checkpoint:
   idle reaches `SYNC`, and tick delivery/IRQ mask durations improve.
2. **Load in bounded contiguous chunks.** Validate a destination span, map its
   bank once, copy/zero a bounded run with `TFM`, and checksum using a cursor
   held in registers. Preserve image validation, private loading state,
   ownership, all-or-nothing admission, cancellation and the safe-point bound.
   Initially keep the same 32-byte quota to isolate implementation savings;
   tune the quota only against input/Ctrl-C latency. Removing only the measured
   `image_byte`/`image_store` self time would save at most about 1.09 s from this
   trace; reaching subsecond launch also requires reducing surrounding work.
3. **Give pending foreground launches explicit cancellation.** Ctrl-C during
   loading should abort and unwind the admitted transaction before application
   entry, rather than allowing the command to run and consuming `^C` later.
4. **Remove avoidable prompt/RPC and copy overhead.** Reuse the kernel's cwd
   snapshot where its mount/generation semantics allow; preserve stale-cwd
   rejection. Copy contiguous ring spans instead of recomputing every byte's
   address. Batch list/stat/data work where possible. Consider packet lengths
   only with an explicit ABI compatibility decision.
5. **Tune TTY drain and command packaging after remeasurement.** Keep fair,
   bounded output progress but avoid excessive rescans for bulk output. Split
   small common commands if link maps demonstrate a useful size reduction;
   SDK standard I/O/redirection still has a cost. Avoid assuming a permanently
   resident shell command cache fits the 512 KiB admission budget: the admitted
   two-drive workload already uses all 32 physical frames.

Suggested acceptance targets for this performance checkpoint, **not measured
results or promises**, are: keep the 3 MHz model; idle key echo remains
under 30 ms; blank prompt under 50 ms; `echo` first output under 500 ms; running
and loading Ctrl-C under 100 ms with correct cleanup. Three samples establish a
baseline, not percentile guarantees. Add repeated and concurrent-load checks
when evaluating those goals. File throughput must be remeasured alongside them
so faster startup does not conceal the much larger `cat`/`cp` body costs.

## Reproduce and inspect

From the software repository, use an independent build so the working GUI disk
is preserved:

```sh
cmake -S ../microlind-sim -B /tmp/mlos-sim-build \
  -DMICROLIND_BUILD_GUI=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/mlos-sim-build --target microlind-sim-cli -j4
make -C mlos response-profile BUILD=/tmp/mlos-perf-build \
  SIMULATOR=/tmp/mlos-sim-build/microlind-sim-cli
```

The CLI must sit beside matching simulator static libraries; rebuild them with
the current simulator headers. For a shorter run after building:

```sh
python3 mlos/tools/response_profile.py --build /tmp/mlos-perf-build \
  --simulator /tmp/mlos-sim-build/microlind-sim-cli \
  --engine instruction --samples 3 --scenario echo \
  --output /tmp/mlos-echo-profile
```

The [host profiler](../tools/response_profile.py) boots the actual ROM and shell,
injects UART bytes, and observes unmodified target instructions. It reuses the
runtime machine wrapper but never calls its target-patching syscall helpers.
It places deterministic 128-byte and 4096-byte files in a private CF copy and
checks read contents, persisted redirection/copy contents, stack guards,
filesystem structure, cycle-accounting totals and the source image's unchanged
SHA-256. The full run contains **48 trials per engine, 96 total**: commands and
cancellation get three samples each; typing/backspace and idle get one each.

Outputs under `BUILD/response-profile/`:

- `results.json`: events, cycle domains, source totals, syscalls, counters,
  summaries, host timings, target hashes, tool versions and simulator library
  hashes.
- `instruction.jsonl` / `microcycle.jsonl`: full raw instruction histograms and
  UART output, plus equivalent engine logs.
- `working.img`, `runtime.cfg`: disposable measurement media/configuration.

The [frozen S09 baseline](measurements/command-responsiveness-s09.json) retains
both engines' summaries and first-trial profiles. Core routine self times are
sums of raw PCs between the named function boundaries recorded in that file.
The command image SHA-256 is
`ccd91e4daeba6eee4fff50a65c7a127497a23ea92d601f3b014a031bc6f06146`;
all artifact and simulator library hashes are in the baseline.

Instruction/microcycle median differences were at most **83.371 ms** across
these scenarios. They agree on the bottlenecks; bus-phase timing can change
interrupt interleavings. This is a single-drive, shallow-directory baseline,
without injected CF latency, GUI rendering or physical UART/CF timing.
The host profiler ran faster than modeled real time with Release simulator
libraries, but its host seconds include profiling overhead and do not establish
GUI throughput. At 3 MHz True Run, simulated seconds approximate wall time only
when the host keeps pace. Regular Run's debugger throttle, mismatched model
clock, or a slow GUI build can add a separate delay; see the
[run instructions](../README.md#run-the-console).
