# Runtime contracts, ABI 1

This extends the [S00–S02 entry contract](contracts.md). Constants are maintained
in `include/abi.json`, generated into `syscalls.inc`, `syscalls.h` and the
parameter-size dispatch table. `tools/gen_abi.py --check` detects drift. Public
C wrappers live in `sdk/`; internal addressed definitions are in
`include/layout.inc` and `runtime/state.inc`.

## Native calls and process lifetime

SWI uses A=number and X=parameter pointer. Multi-byte fields are big endian.
D is the result; C clear means success, C set means a negative `SYS_E*` code.
E/F/DP/X/Y/U/V/S and the other saved condition bits survive. Handles can have
bit 15 set: C/defined error values determine failure, not a signed comparison.
`kerror()` recognizes the reserved -1 through -25 error range.

The core copies parameters and validates/copies payloads against the recorded
application maps. It never retains borrowed application pointers across waits.
One native thread belongs to each process. READY/RUNNING/SLEEP/WAIT, unpublished
LOADING, SUSPENDED, DYING and ZOMBIE are explicit states. Init is PID 1; PID
identities are not reused before reboot. Init adopts orphans. A dying process
settles accepted requests before releasing pinned storage, revokes mappings
before freeing frames, then becomes reapable. Init/core faults halt; application
traps terminate only the application and its applicable job/service dependents.

Ticks are monotonic modulo 2^32. Relative sleeps are at most 0x7fffffff ticks;
wait deadlines use modular comparisons, with zero selecting no deadline.
`SYS_TICKS` copies a four-byte snapshot. The timer preload and quantum are
build-configurable in `include/scheduling.inc`; ordered class phases in
`include/schedule_phases.inc` default to 4:2:1 with round-robin within classes.
Five ticks expire a quantum. Yield/block/exit advance dispatch; empty classes
are skipped. Only the syscall/IRQ return safe point switches process context.
Privileged nested timer IRQs update ticks without switching a live core stack.

## Images and bootstrap

All images are fixed linked; relocations are unsupported. Checksums are unsigned
byte sums modulo 2^32, for integrity/error detection rather than authentication.

`mlos.bin` starts with a 20-byte `MLK1` header:

| Offset | Field |
| --- | --- |
| 0 | Four bytes `MLK1` |
| 4,6,8 | Version u16=1, kind u16=0, logical load u16=0 |
| 10,12,14 | Entry u16 within initialized payload, payload bytes u16, memory bytes u16=16384 |
| 16 | Payload checksum u32 |

ROM validates IDENTIFY capacity, MLPT/MLFS 1.1.0, partition 0, 512-byte blocks,
metadata/file/extent bounds and the payload checksum before executing the core.
The root scan is limited to 64 sectors, a 47-byte name and one direct extent.
The kernel payload must fit one frame; only its declared bytes are loaded.
Failure emits bounded serial diagnostics and halts. Core entry receives X=CD00,
whose `BI01` record identifies 32 physical frames, sector shift 9, format 1 and
validated device/partition/root geometry. `include/images.inc` defines offsets.
CE00–CFFF is the boot sector buffer.

The retained provider loads immutable root `.mlx`/`.mld` images only; no PATH,
subdirectory executables or runtime replacement. The filesystem service refuses
writes/namespace changes to these names and `/mlos.bin`. This breaks the initial
service dependency cycle and remains the executable source after ordinary file
operations move to the runtime service. Root lookup/header reads and sector
refills are bounded synchronous ROM PIO; payload copying and BSS clearing
continue in spans bounded by `MLOS_LOADER_QUOTA` (128 bytes by default), sector
and logical-window boundaries. The checksum is unchanged; banks map once per
span. Loading never suspends a kernel stack.

`MLX1` application header is 32 bytes followed by 1–6 eight-byte segment records:

| Offset | Field |
| --- | --- |
| 0,4,6 | `MLX1`, version u16=1, total header bytes u16=32+8*n |
| 8,10,12 | Entry u16, stack top u16, stack reservation u16 (default 1024) |
| 14,15,16,17 | Resident mask byte (1/3/7), resource mask byte, segment count byte, flags byte=0 |
| 18,20,22 | Argument reservation u16=128, initialized payload bytes u16, reserved u16=0 |
| 24,28,30 | Whole-file checksum u32 with this field zero, syscall ABI u16=1, reserved u16=0 |

Each segment has u16 address/initialized length/BSS length/payload offset.
Segments must be ordered, disjoint, resident, below C000 and clear of stack plus
argv. Entry must be initialized. BSS clears before publication. Resident backing
need not be physically adjacent. Preflight admits all frames transactionally;
failures/cancellation unwind unpublished allocations. Resource windows cannot
alias declared resident windows.

D=argc and X=argv at application entry. At most eight arguments fit the 128-byte
snapshot (18 bytes of pointers and at most 110 bytes of NUL-terminated strings).
CMOC startup at 0400 enters its CRT at 0420, passes arguments to the SDK-renamed
program main, closes redirected streams and exits with the low eight status
bits. Application-private runtime cells begin at 0300.

Heap allocations exclude code/data/BSS, stack/argv and resource windows. They
can span adjacent logical windows; empty eligible heap-only frames are unmapped
and reclaimed once object/reference/pin counts allow it. Live pointers never
move. SDK malloc/calloc/realloc/free use a two-byte size prefix; failure returns
null. Extra resource mappings require owned generational handles.

## IPC and waits

SPSC streams and messages use kernel-owned physical backing, accessible even to
three-resident-bank applications. Default capacity is 512; admitted capacities
are 1–16352 bytes. Each channel currently charges a whole 16 KiB frame, plus a
32-byte metadata record; message channels allow 16 queued message lengths.
A syscall transfers at most 512 bytes, copied in chunks of at most 256.
Streams permit partial progress. Message send is atomic; undersized receive
reports required size with EMSGSIZE and leaves the message queued. Zero-length
transfers are no-ops. Full/empty nonblocking operations return EAGAIN.

Producer close/death retains queued data without a drain timeout; the consumer
sees EOF after draining it. Consumer death discards retained storage and writers
see EPIPE. Generation/type/owner validation applies to every operation. Kernel
handles have low bytes 1–64 and generation 1–255; exhausted generation slots
retire instead of wrapping. References/pins prevent premature reuse.

Named services use 1–6 byte names. Connect creates two private one-way channels
and four endpoints transactionally. A listener holds at most four pending
connections. Accept authenticates the full listener identity; `SYS_PEER` exposes
the accepted peer PID. WAIT_ANY copies 1–8 tokens and atomically checks/arms sleep
with an optional absolute deadline. Closure and completion are readiness events.
Service death closes endpoints; reconnect is always explicit.

Idle listeners/clients/workers use `WAIT_ANY`. Readiness mutations mark a bounded
wake pass; timer-only passes still check finite deadlines. Driver progress skips
when no request is pending, and TTY channel scans skip when no output/cleanup
work is pending. The configured 1 kHz timer and 4:2:1 scheduling remain unchanged.

## Drivers, modules and requests

Device instances 0/1 are the built-in CF PIO state machine at F418/F640;
instances 2/3 are deterministic mocks. CF1 is explicitly/manual bound and polled.
Only the device/controller adapters own register locations; modules do not
manipulate a backplane-global pending/mask register. `runtime/backplane.asm`
provides two version-1 eight-byte bindings: version byte, enable-shadow byte,
pending-address word, mask-address word, upstream-route byte and reserved byte.
Both default to zero/unassigned addresses. Init resets configured masks to zero;
pending reads are non-clearing and AND the software enable mask and 3F. Mask
writes remove reserved bits. Only masked core dispatch may use these calls;
card causes require card-specific ACK followed by pending recheck. Target tests
use RAM-backed register mocks for independent controllers/version rejection.
Physical offsets and upstream routing remain unassigned, so active expansion
IRQ dispatch is disabled until S15 qualification supplies that hardware contract.

Raw devices have one exclusive service owner. Character console reads/writes
use the bounded TTY adapter; its control calls cover mode/foreground/geometry.
The initial loadable module capability is block I/O only; unsupported capability
bits reject. This is not a general character/control module or DMA ABI.

`MLD1` has a 32-byte header: magic at 0, then u16 version=1, header bytes=32,
ABI=1, origin=4000, code bytes, BSS bytes, bind/poll/stop offsets and capability=1
at offsets 4 through 22; checksum u32 at 24, reserved u32=0 at 28. The checksum
covers header (zero checksum) and payload. Code+BSS fits one frame and callback
offsets must lie in initialized code. Only init/registered shell may load.
Loading is transactional and sliced like applications; accepted code remains
until reset. Up to four code images share independently admitted instance state
frames. Callbacks map code at 4000 and state at 8000, with Y=8000, U=device,
X=request or zero, D=low tick count. D/C returns completion/status. Callbacks are
serialized, masked, bounded, non-reentrant and may not call SWI/sleep. A trusted
CPU fault follows the core-fault policy. `modules/delay.asm` demonstrates the ABI.

Eight 512-byte requests share one charged/pinned OS frame. Submission snapshots
writes; collection revalidates read destinations. Every token binds its owner,
device generation and buffer. Per-controller progress issues commands, waits for
DRQ, moves at most `MLOS_IO_QUOTA` PIO bytes per controller per turn (128 by
default, using native `TFM`), and settles final status. A slow drive
does not suspend another controller. Default deadline is 1000 ticks. Cancel
stops queued work or drains already accepted PIO safely before ECANCELLED.
Cancellation does not promise disk rollback; accepted writes are never replayed.
Device close waits for references; module STOP failure or a real controller
timeout quarantines the instance until reset. A timed-out controller is never
silently reassigned while its bus activity might remain live. Safe media removal
can be explicitly recovered after old work has settled.

The worker's 8192-byte validation bitmap at 1000–2FFF becomes a 16-sector
read-through cache only after validation completes. The cache is private to that
worker/device; every request's first read reaches actual media, even on a cache
hit. Every write attempt and I/O error invalidates all entries. Recovery uses a
fresh worker and empty cache. The 133 additional live metadata bytes fit below
0400 in existing resident backing; no additional frame is admitted. Cached data
is never used for deferred writes or for skipping volume validation.

## Filesystem protocol and integrity

One frontend serves two volumes and three concurrent client connections. Each
volume has a private three-bank worker, so waiting on one controller leaves the
other drive dispatchable. The shared target filesystem algorithms reside in
`mlfs/target/`; workers wrap them with asynchronous block calls and yielding
waits. Legacy BIOS wrappers include the same algorithm sources.

The initial target supports MLPT/MLFS 1.1.0, partition 0, 512-byte blocks,
at most 65535 blocks, direct single extents, eight directory levels, 47-byte names
and 63-byte canonical paths plus NUL. Larger blocks and indirect/multi-extent
files reject rather than being interpreted. Growth can relocate an extent and
preserves existing file bytes. Root uses drive0; `/disk1` uses drive1; `/proc`
is reserved and provided independently by the SDK/kernel metadata.

Messages are exactly 400 bytes, big endian:

| Offset | Content |
| --- | --- |
| 0,1 | Operation byte, flags byte |
| 2,4,6 | Result i16, actual u16, requested u16 |
| 8,12,14 | Offset/cursor u32, file token u16, protocol version u16=1 |
| 16,80,144 | First path[64], second path[64], data[256] |

`sdk/fs.h` names operations 0–20. Ordinary reads/writes require descriptors;
clients cannot bypass locks using path read/write/truncate messages. Sixteen
file records use low-byte tokens 81–90 hexadecimal, with retired non-wrapping
8-bit generations. Each token binds the accepted client PID/connection and
volume generation. Open allows shared readers or one exclusive writer. Create
and truncate require write permission. Namespace edits conflict with open files
and referenced cwd subtrees. Offset is u32; transfer <=256 bytes per RPC. A
known partial prefix advances position and is reported before a volume goes
offline; unknown write completion is not replayed. Closing stale descriptors is
allowed for cleanup. Unmount is BUSY while cwd/files/inflight work reference it.

Before publication a worker validates checksum, metadata geometry, reachable
ownership, names, directory depth, extent bounds, duplicate names/crosslinks and
allocation bitmap. Superblock byte 8 is state 0=clean/1=dirty; other values reject.
A consistent dirty volume mounts read-only; mutations return EROFS. Mutations
write a dirty superblock/checksum first and clear dirty only after their known
safe completion. Uncertain I/O/rollback leaves dirty/read-only or offline.
PIO command completion is the selected persistence boundary: there is no ATA
FLUSH/FUA or claim about a physical device's volatile write cache.

`mlfs/tools/check_image.py IMAGE` validates offline images. `--repair` rebuilds
only a structurally proven bitmap and clears dirty using atomic replacement;
structural damage/crosslinks refuse repair. Work on an offline image, never the
simulator's active backing file. Host `mlfs_mount` has no read-only mode and
rejects dirty/unknown state (-13), requiring explicit validation/repair first.

Failure offlines only the affected volume, cancels/settles old requests and
invalidates its generation. `recover` starts a fresh worker/generation. Old
handles and cwd never rebind. Relative access with stale cwd returns EIO;
explicit absolute chdir establishes a new reference. Process spawn inherits cwd
and session/job scope from the original parent. Filesystem frontend death
withdraws all its workers and latches failure until reset. `/proc/processes`,
`/proc/memory`, `/proc/mounts`, serial diagnostics and `/proc` cwd remain usable.
Snapshots are copied at open and pin no subjects. A process has one virtual open
snapshot token, low byte C1, with the same generation-retirement rule.

## TTY and shell profile

UART A is interactive; UART B is output-only logging. TTY owns a 256-byte input
FIFO across foreground handoff. A registered shell gives input to one suspended
child before it becomes runnable. Background input returns EOWNER. Per-process
standard stream channels and retained output survive producer exit until the
session provider drains them; parent wait additionally drains stdout before the
next prompt. No drain timeout discards ordinary output.

`SYS_GETC` remains nonblocking. Additive ABI-1 call 45 `SYS_TTY_WAIT` has no
parameters: it returns 0/C0 when input/edit/EOF/interrupt work is available,
otherwise atomically sleeps the foreground caller until readiness. Background
callers return EOWNER/C1. It consumes no input; callers retry GETC after wake.
Shell/SDK input use this wait instead of one-tick polling. Output drains at most
16 bytes per channel visit and 16 bytes total per pass, with a rotating cursor.

A Ctrl-C received during a suspended foreground spawn aborts its unpublished
loader transaction, releases its frames and returns ECANCELLED to the shell,
which prints `^C`. The image never enters application code. Existing running-job
cancellation still returns status 130 and safely settles accepted I/O.

Line mode supports 109 editing bytes plus newline, echo/backspace, CR/LF collapse
and Ctrl-D EOF on an empty line. Raw mode returns available bytes. Ctrl-C kills
the foreground job scope, settles pending file/device work and restores the
shell's mode/input ownership. Typeahead stays with the provider. Logs are eight
records of at most 31 bytes; overflow discards the oldest complete queued record,
counts drops and emits a bounded loss marker while preserving partial output.
Emergency ROM serial is independent and bounded.

The shared decoder has an eight-byte sequence bound and 40-tick escape timeout.
CSI/SS3 arrows, Home/End, Insert/Delete, Page and F1–F12 are decoded. Unknown
sequences are consumed; Latin-1 C1 bytes remain ordinary characters. The initial
monochrome terminal subset is cursor positioning, erase, reverse video and cursor
visibility on an external 80x25 serial terminal. The GUI cell model is deferred.

The lexer preserves quoted whitespace and literal quoted `<`/`>`. Unquoted
redirections become private launch metadata; the child opens input first and
then its exclusive output writer (create/truncate), removes metadata from argv,
and starts main. Failed output setup closes input and exits 126 with a diagnostic.
There is no parent-to-child writer lock transfer. Init waits for service readiness,
starts the shell, restarts it once, then keeps emergency diagnostics available
if it fails again. Init/core failure halts.

During reset the ROM lights the power LED green without a stack, initializes UART
before clearing common RAM and prints stage/image progress on A. Boot-only ROM
helpers append at F821/F824/F827; earlier jump-table entries retain their offsets.
The core enables a bounded, nonblocking pulse at most once per500 delivered ticks
and disables feedback when the first shell registers its TTY session. Four common
bytes at DE10–DE13 hold activity/deadline state; no extra frames or init stdout
channels are admitted. ROM rejection/core panic selects red. See
[boot-process.md](boot-process.md) for observed timings and transcript.

The SDK obtains cwd text from `SYS_CWD` and checks the frontend/volume/generation
snapshot using `SYS_FS_STATE`. It preserves unavailable/stale-cwd failure and
`/proc` behavior without a filesystem RPC for each prompt. Common commands
`echo`, `pwd`, `ls`, `cat`, `cp` and `mem` are compiled separately from guarded
branches of the same maintained source. Names, arguments, redirection and
resident/stack declarations are unchanged; the full image retains diagnostics.
