# S00–S02 contracts, ABI v1

This preserves the original embedded-harness contract. Production extensions,
including scheduling, the changed runtime metadata/stack reservations and calls
9–44, are defined in [runtime.md](runtime.md). The harness still runs separately.

This file freezes the initial development subset. Numerical definitions come
from `include/abi.json`, generated into assembly/C declarations with
`python3 mlos/tools/gen_abi.py`. Internal addressed placement comes from
`include/layout.inc`; fixed development ROM slots come from `include/rom.inc`.
Later stages must version incompatible changes and extend the contract index.

## Public native SWI

Remain in native HD6309 mode, MD=$01. The OS owns mode control; applications
must not change MD. A=call ID (0–255), X=optional parameter-block pointer.
D=result, C clear on success; D=negative `SYS_E*`, C set on failure. E,F,DP,X,Y,
U,V and S are preserved. Consequently W is preserved and Q's D half changes.
CC preserves pre-call H,N,Z,V,I,F; C reports the result. The full-frame E bit
is set by hardware entry and remains set after RTI. No other flags encode a
result. Unknown call numbers return ENOSYS.

All words below are unsigned 16-bit, most significant byte first; byte fields
have no alignment requirement. Parameters reside in the calling process's
live application windows. The core copies the entire parameter block before
performing an operation. Invalid parameter ranges return EFAULT; no parameter
block is retained or modified. Output buffers have separately specified effects.
S00–S02 calls are synchronous and never sleep; there is one diagnostic process.

| ID/name | Parameter bytes at X | Success D / effect |
| --- | --- | --- |
| 0 `SYS_PROBE` | none, X ignored | 1 (ABI version) |
| 1 `SYS_WRITE` | source word at 0, count word at 2 | count, 0–256 diagnostic bytes on UART A |
| 2 `SYS_BANK_ALLOC` | none | opaque bank token; contents unspecified |
| 3 `SYS_BANK_FREE` | token word at 0 | 0; revoke all resource mappings before reuse |
| 4 `SYS_BANK_MAP` | token word at 0, window byte at 2 | 0; replace eligible vacant/resource window |
| 5 `SYS_BANK_UNMAP` | window byte at 0 | 0; discard parking and uncommitted role |
| 6 `SYS_MEMORY_INFO` | destination word at 0 | 0; copy 4 accounting bytes |
| 7 `SYS_COPY` | source word at 0, destination word at 2, count word at 4 | count, 0–256 bytes with snapshot/memmove semantics |
| 8 `SYS_ENTRY_TEST` | none | $6309 after explicit nested privileged SWI |

`MEMORY_INFO` output bytes are total physical frames, whole reserved frames,
free physical frames and PID1-owned frames. Initially these are 32,3,28,1:
the 29 admissible frames include the application's initial resident frame.
`ENTRY_TEST` and `COPY` are the bounded development test surface, not substitutes
for later IPC, heap or asynchronous device APIs.

For WRITE/COPY, a zero count succeeds without dereferencing payload pointers,
including $FFFF; the parameter block itself must still be valid. Counts above
256 return EINVAL. Nonzero ranges must fit wholly within $0000–$BFFF without
16-bit wrap and every touched window must have a live, owned, nonreserved
physical frame. Common RAM, ROM, I/O and discard mappings fail with EFAULT.
Window crossings use the saved process maps, including application window 0
after it has been replaced by the core. Both COPY ranges validate before any
payload mutation; overlapping copies use a 256-byte common snapshot. The
kernel restores its temporary MMU2 mapping on every copy return.

WRITE copies its full source before output. EFAULT/EINVAL produce no serial
output. EIO indicates the bounded UART poll failed; bytes already transmitted
remain transmitted. Diagnostic polling can delay IRQs; S04/S07 must introduce
the scheduling/transport rules before treating it as a general log/TTY API.

Error values are ENOSYS=-1, EINVAL=-2, ENOMEM=-3, EHANDLE=-4, ESTALE=-5,
EOWNER=-6, EBUSY=-7, EFAULT=-8, EIO=-9, EOVERFLOW=-10. Invalid slot encodings
return EHANDLE. A previously issued token with mismatched generation or no
live object returns ESTALE. A live token for another owner returns EOWNER.
Mapping/releasing a resident frame or releasing a referenced/pinned object
returns EBUSY. Rejected mapping/free operations leave state unchanged.

## Frames, roles and identities

Installed RAM is exactly 32 physical frames of 16 KiB. Frame 0 belongs to the
core, frame 1 to common RAM (including its otherwise invisible upper half),
and frame 2 to shared discard. These have owner $FFFF/reserved state. No
allocation may return them. Frame 3 initially backs PID1's resident window 0.
Windows 1/2 start uncommitted and parked on discard. The initial loader/layout
constraints are explicit fixtures; executable declarations arrive in S05.

Each frame has an 8-byte common record: owner word at 0, flags at 2, reference
count at 3, pin count at 4, bytes 5–7 reserved zero. Flags are RESERVED=1,
RESIDENT=2 and PROVISIONAL=4. Allocation of 1–29 frames first claims provisional
records, then publishes the entire batch and updates free accounting. Exhaustion
or the test failure injector reverses all provisional owner/flag changes.
The initial application already occupies one admissible frame; a 29-frame
request in this fixture therefore fails without consuming the remaining 28.

Window roles are UNCOMMITTED=0, RESIDENT=1 and RESOURCE=2. Resident windows
hold stable code/data/stack/ordinary pointers and reject public remapping.
Mapping a bank handle claims an uncommitted/resource window as RESOURCE.
Unmap/free withdraws resource mappings, sets discard, and returns those windows
to UNCOMMITTED before making a physical frame free. S05 will add executable
layout constraints and empty-heap reclamation; there is no ordinary heap yet.

Bank handles are 16-bit opaque tokens: generation in the high byte and a
1-based table slot in the low byte (1–32). Neither component names a physical
frame. Slots track owner word at 0, generation at 2, physical frame at 3,
liveness at 4, refs at 5, pins at 6, retired flag at 7. Generation starts at 1,
increases only on publication and never wraps. A slot exhausted at generation
255 retires permanently; ENOMEM is normal when no slot can be admitted, and
its provisional frame is rolled back. Future object classes must add explicit
type/namespace validation before accepting these tokens as another kind.

Internal `handle_ref/unref` and `handle_pin/unpin` validate identity and owner,
reject 8-bit counter overflow/underflow, and prevent free while held. Pins keep
the bank from reuse; references keep identity alive. S02 has no asynchronous
pending operations or deferred close. Both frame counts and object counts are
checked before free, leaving room for later frame users outside bank handles.

The CMOC `_mlos_call` adapter takes a promoted 16-bit call number and a pointer
as two stack words. It rejects a number above 255 and preserves X around SWI.
`mlos_put_u16` builds byte-array parameters without compiler packing assumptions.
A bank token may have its sign bit set: cast a successful allocation result to
`unsigned int`; do not classify every negative-looking token as an error.
The defined error values cannot collide with a valid 1–32 token slot. The
fixture exercises all nine calls through CMOC 0.1.98; general CRT/loading,
exit and libc integration remain S05.

## Native entry and nested bridges

The full native hardware frame is exactly 14 bytes at the post-entry S:

| Offset | Bytes |
| --- | --- |
| 0 | CC |
| 1,2 | A,B (D result slot) |
| 3,4 | E,F |
| 5 | DP |
| 6–7,8–9,10–11,12–13 | X,Y,U,PC, respectively |

V is not hardware stacked; ROM saves it separately. MD is fixed by the ABI,
not restored from an application-controlled frame. FIRQ uses the short
CC/PC frame because MD bit1 is zero. It remains masked/unused and its valid
ROM default is RTI. SWI2/SWI3 and instruction/math trap entries bridge to a
bounded diagnostic stop for S01/S02; application termination comes in S04.
The simulator's existing illegal-instruction trap does not stack a full target
trap frame: its stop test proves the bridge/unlock/diagnostic behavior only.

There are four 32-byte common entry records at C020. Bytes 0–13 hold the copied
hardware frame; 14–15 the original frame S; 16–17 software-saved V; 18–20 the
pre-entry MMU0–2 values; 21 the reason; 22 the captured previous privilege;
23–31 are reserved. Depth increments only after admission and decrements before
RTI. Ordinary SWI from core mappings or an unrecognized nested SWI stops with
reason $32. Depth overflow stops with $35.

An application SWI copies the native frame while its mappings still exist,
then switches to the common kernel stack before replacing MMU0 with frame 0.
DP becomes zero inside the core. Return executes in ROM, restores the latest
recorded process maps, copies the result frame back into the restored
application address space, restores original S/V, relocks F405, then RTIs.

IRQ does not unlock. The ROM IRQ stub saves A, reads/masks F405 **before** SWI,
keeps that bit on its own stack, checks UART ISR bit3, and read-acknowledges
UART_STOP. Only then does it execute the dedicated plain SWI. Saved PC must
match `rom_irq_cont`; the reason/prior-privilege record comes from that exact
bridge continuation, not from the newly unlocked F405 value. Unknown IRQ
sources take the diagnostic trap bridge. No UART RX/TX interrupts are normally
enabled in the harness; their shared-mask preservation is independently tested.

The nested-test bridge has its own exact `rom_nested_cont` continuation and
requires established privilege. Privileged IRQ/nested entry keeps the current
common stack; an outer application IRQ switches stacks before mapping core.
Nested return restores exact interrupted mappings (including a temporary
MMU2 copy mapping), frame/S/V and captured permission. It never relocks an
interrupted privileged transaction. A write after nested return is tested.
Transactions stay IRQ/FIRQ masked; no scheduler runs in S02.

Unexpected NMI unlocks and uses a dedicated emergency stack. The first entry
records a reason, attempts one bounded UART marker and stops for reset. A
repeat resets the emergency stack and stops without printing recursively.
CPU stacking precedes the ROM handler, so an invalid interrupted S/common map
can prevent diagnostics. This is the staged plan's reserved-NMI default; it
adds no debugger/resumable-NMI API. Panic codes: $21 selftest failure, $31 trap
bridge, $32 unexpected kernel SWI, $34 NMI and $35 depth overflow.
