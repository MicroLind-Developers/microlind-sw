# MLOS: CF-booted serial system (S00–S09)

MLOS now boots from MLFS and runs a preemptive HD6309 native-mode kernel,
assembly and CMOC programs, IPC, asynchronous device requests, filesystem
services and a serial shell on the 512 KiB target. The original S00–S02 embedded
harness remains a separate regression image. The previous prototype is in
`spikes/old_mlos/`.

The software is exercised with both simulator engines. Physical GAL fit,
privilege-gate wiring and board timing/CF qualification remain open. See the
[stage evidence](docs/runtime-stages.md) for the supported profile and remaining
hardware dependencies; this is not a completed physical K1 qualification.

## Build and test

LWTOOLS 4.24 and CMOC 0.1.98 are pinned in
[toolchain.lock.json](toolchain.lock.json). Host tooling needs Python 3, C/C++20
and CMake. Rebuild the accompanying simulator changes before running tests:

```sh
cmake -S ../microlind-sim -B /tmp/mlos-sim-build -DMICROLIND_BUILD_GUI=OFF
cmake --build /tmp/mlos-sim-build -j4
make -C mlos all SIMULATOR=/tmp/mlos-sim-build/microlind-sim-cli
make -C mlos acceptance SIMULATOR=/tmp/mlos-sim-build/microlind-sim-cli
```

An existing GoogleTest checkout can be supplied using
`-DFETCHCONTENT_SOURCE_DIR_GOOGLETEST=/absolute/path/to/googletest` when network
access is unavailable. `SIMULATOR` must point to the CLI in its CMake build
directory, beside `libmicrolind-sim.a` and `libmicrolind-sim-app.a`.

`all` builds both images and checks their budgets. `acceptance` runs the original
entry/memory/CMOC checks, runtime contracts, corrupt-boot matrix, full console
workflow and host image/repair tests. Individual targets are `test`,
`runtime-test`, `boot-test`, `console-test`, `image-test`, `runtime-check` and
`session-test` (the GUI session loader/realtime backend).
Use `BUILD=/tmp/another-build` for an independent build. Acceptance runs its
suites sequentially because they generate shared runner headers/configuration;
do not run separate test commands against the same BUILD concurrently.

Command latency has a separate opt-in benchmark:

```sh
make -C mlos response-profile BUILD=/tmp/mlos-perf-build \
  SIMULATOR=/tmp/mlos-sim-build/microlind-sim-cli
```

It measures UART input, first output, loading, execution and prompt return on
both engines, using disposable CF copies. Results and instruction profiles go
under `BUILD/response-profile/`. See the
[command responsiveness analysis](docs/command-responsiveness.md) for the S09
baseline, limits and recommended optimization order. The
[implemented improvements](docs/performance-improvements.md) compare the optimized
release with that baseline. The benchmark is separate
from acceptance and does not change runtime code.

Root Make targets forward `mlos`, `mlos-test`, `mlos-runtime` and
`mlos-acceptance`. CMake integration is available without historical prototype
paths:

```sh
cmake -S . -B /tmp/mlos-sw-build -DMICROLIND_MLOS_ONLY=ON \
  -DMLOS_SIMULATOR=/tmp/mlos-sim-build/microlind-sim-cli
cmake --build /tmp/mlos-sw-build --target mlos-acceptance
```

## Run the console

`build/boot.ihex` is the production ROM; `build/console.img` is a disposable,
formatted CF image containing the kernel, init, filesystem services, shell,
commands and example driver. `build/runtime.cfg` selects 3 MHz, 512 KiB and
that CF image. The ROM expects partition 0, MLFS 1.1.0 with 512-byte blocks and
root `mlos.bin`; it does not execute a sector-zero jump stub.

In the GUI, use **File → Load Session** to open `build/mlos.session`. It selects
the matching ROM, CF image, HD6309 and 3 MHz model/pacing settings together.
Then choose **True Run**. Alternatively, select HD6309, load this ROM and
`build/runtime.cfg`, reset, then choose
**True clock: 3 MHz** and **True Run** in the Control panel. Regular **Run** is
throttled by **Operations/min** (default 600, only ten instructions/second).
At that default, the initial 8192-byte RAM clear alone takes about 41 minutes;
PC cycles through `rboot_clear` while X advances from C000 to E000. The green
power LED and early serial banner are already visible before clearing begins.
The configured CPU clock does not override debugger throttling.
The GUI's True clock setting controls host pacing; it does not change the CPU
model's `[CPU] CLOCK_HZ`. MLOS requires the configured 3 MHz model for its current
timer/entry budget. An old session with an implicit 1 MHz model can stall at
`Loading init.mlx...` with endless dots even when True clock says 3 MHz. Reload
the corrected hardware configuration/session; Reset alone keeps the loaded model.
See [the complete boot process and measured phase timings](docs/boot-process.md)
for reset-to-prompt behavior; this build needs approximately 7.3 simulated seconds
at 3 MHz before the first prompt.

Boot reports the current stage and installed image on UART A, with periodic dots
during long loads and filesystem validation. Feedback stops before the shell
prompt. ROM boot rejection or a core panic turns the power LED red.

```sh
/tmp/mlos-sim-build/microlind-sim-cli --6309 --ihex \
  --rom mlos/build/boot.ihex --config mlos/build/runtime.cfg
```

Use the simulator's serial terminal for interactive input. In the CLI, `run`
advances execution and `serin` injects bytes; it does not append Enter. The shell
accepts CR or LF. UART A carries the interactive console; UART B carries logs
through a separate simulator callback. CLI/debugger commands and shell commands
are different input paths.

Example shell workflow:

```text
help
ps
mem
mkdir work
cd work
echo 'hello world' > note
cat note
cp note copy
ls
cat /proc/memory
cd /
loadmod delay.mld
```

Commands also include `pwd`, `rm`, `rmdir`, `mv`, `sleep`, `yield`, `mounts`,
`recover`, `unmount` and `key`. Builtins are `cd`, `exit`, `loadmod` and
`bindmod`. Single/double quotes and `<`/`>` redirection work. Foreground Ctrl-C
returns input to the shell after safe cancellation. Pipes, background command
syntax, append, expansion and GUI startup are later-stage features.

A second polled CF can be explicitly configured at F640–F647 using a `[CF2]`
section; `recover /disk1` starts its worker. The console acceptance suite
constructs two disposable images/configuration and exercises this path. This
address is a manual simulator binding, not a qualified expansion-card contract.

## Source and artifact boundaries

| Location | Responsibility |
| --- | --- |
| `bios/mlos/` | Fixed ROM entry/return, reset, vectors, UART/timer, CF boot and restricted immutable-image provider |
| `mlos/src/` | Shared entry ABI, safe copies, frame ownership/handles, original harness |
| `mlos/runtime/` | Scheduler/processes, heap, IPC/waits, driver requests/modules, TTY and namespace metadata |
| `mlos/services/` | Unprivileged filesystem frontend and per-drive workers |
| `mlos/programs/`, `mlos/modules/` | Init, shell, commands, diagnostic programs and trusted example module |
| `mlos/sdk/`, `mlos/include/` | CMOC startup/runtime, filesystem/terminal clients, generated ABI and layouts |
| `mlfs/target/` | Shared target filesystem algorithms, also included by the legacy BIOS filesystem module |
| `mlfs/lib/`, `mlfs/tools/` | Production host filesystem library and offline validation/repair |
| `mlos/tests/`, `mlos/tools/` | Actual-target runners, deterministic CF construction, packers, budgets and provenance |

The legacy menu BIOS remains an independent build. Runtime services are outside
the 8 KiB ROM. Ordinary file access goes through the filesystem service; the
restricted ROM reader remains solely for installed executable/module images.
Those filenames are immutable while running and require offline installation.

Each BUILD retains symbols/listings, `budget.json`, `runtime-budget.json`,
`provenance.json`, pristine images, disposable test images and suite logs.
`provenance.json` records tool versions/options, three repository revisions and
source hashes, simulator binary hash and target image hashes. Host fixtures use
deterministic metadata. `console.img` is pristine; tests modify copies.

The [runtime contracts](docs/runtime.md) freeze image/driver/filesystem/TTY
formats and resource limits. The [original entry contracts](docs/contracts.md),
[original S00–S02 evidence](docs/stages.md) and
[hardware profile](docs/hardware.md) retain the foundation and physical checklist.
The three documents in `plans/` remain the architectural authority.
