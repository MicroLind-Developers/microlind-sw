# MLOS implementation guidelines — working draft

Revision 0.1 — 17 October 2026

## Status and authority

This draft records Eric's implementation directions and proposes additional rules for review. It accompanies MLOS Architecture Baseline revision 0.44 and MLOS Staged Implementation Plan version 1.0. Those source documents were checked for relevant implementation and interface constraints; they have not been edited.

**Directions supplied by Eric in this discussion**

1. Implement as much as practical in reusable assembly code.
2. Provide a broad set of useful syscalls and usable application-development APIs.
3. Document every assembly function with its name/short description, input registers, output registers and clobbered registers.

The assembly preference governs future implementation choices. It refines the earlier assembly/CMOC implementation split: reusable assembly is the default for OS functionality; CMOC application support remains required. C use can be justified per component; existing algorithmic code need not be rewritten before its behavior is understood and tested.

Everything below beyond those directions and existing architectural constraints is a **proposed implementation guideline**. Examples are documentation patterns, not assigned syscall numbers or frozen function signatures.

## G01. Assembly first; reuse at a defined boundary

Prefer small assembly modules with clear dependencies and callable interfaces. Keep reusable algorithms independent of kernel internals, scheduling policy and device addresses wherever practical.

Separate:
- Portable-within-MLOS algorithms: memory/string operations, parsing, queues, conversions and format validation.
- Kernel mechanisms: scheduling, frame ownership, handles, waits and safe application-memory access.
- Hardware backends: ROM/GAL/MMU transitions, UART, CF, graphics and input transport.
- Service/client protocols: filesystem, TTY and window-manager operations.
- Application policy and presentation.

“Reusable” means one maintained implementation/interface where appropriate. It does not require every helper to become a syscall, every routine to live in ROM, or a dynamic shared-library loader in the first release. Build placement must declare ROM/core/module/application dependencies and residency.

Fix a bug in the shared module rather than maintaining copied variants in each application. Prefer ordinary subroutines for reusable behavior; use macros for declarations or genuinely justified instruction expansion, with code-size effects understood.

## G02. Broad public APIs with deliberate syscall placement

Expose useful capability through three complementary paths:

| API placement | Purpose | Examples |
| --- | --- | --- |
| Kernel syscall | Kernel-owned state, resource admission, privilege and synchronization | Spawn/exit/wait, frame/bank management, IPC, waits/time, descriptor/request primitives |
| Service client library | Convenient access to separately running MLOS services | Filesystem requests, GUI windows/drawing/events, terminal operations |
| Application library | Local computation with no kernel ownership requirement | Strings, memory copies, parsers, conversions, higher-level helpers |

A service library may use syscalls internally. File/descriptor entry points can dispatch to a service while maintaining one documented application API. Decide placement from ownership, cost and architecture; do not force one trap per convenience function.

Both assembly and CMOC applications should use the same underlying capabilities. Supply assembly include files, callable wrappers and C headers/adapters. Keep compiler-specific argument marshalling at the boundary and avoid duplicating implementation logic.

A supported public operation requires documentation, an example and an appropriate verification case. A growing syscall count alone is not an API quality measure.

## G03. Mandatory function headers

Every callable assembly entry, including interrupt/trap entry points and driver callbacks, needs a contract. Local branch labels do not each need a function header. Aliased entry points must link to the applicable shared contract and document any differences.

Use a consistent template, writing “none” or “not applicable” where needed:

```asm
; Function:       <module_routine_name>
; Description:    <purpose and observable effect>
; Visibility:     <public API / internal / driver callback / IRQ entry>
; Inputs:         <registers, pointed-to objects, lengths, units, input flags>
; Outputs:        <registers and modified memory, separately for success/error>
; Clobbers:       <scratch registers; specify relevant register aliases>
; Preserves:      <registers promised unchanged>
; Flags:          <input/output CC bits, error carry, other defined/undefined bits>
; Errors:         <codes, partial results, and state after failure>
; Preconditions:  <valid ranges, overlap/alignment rules, required object state>
; Context:        <process/kernel/IRQ; privilege and lock requirements>
; Memory/banks:   <required maps/DP; user-pointer handling; mapping on return>
; Ownership:      <borrow/copy/transfer; pointer validity and retained references>
; Blocking:       <may sleep/yield/call out; cancellation behavior>
; Reentrancy:     <reentrant / instance state / serialized; required protection>
; Stack:          <direct usage or bound; callback/IRQ/callee contributions>
; Side effects:   <I/O, allocation, shared state, scheduling, callbacks>
; Cost:           <bound/complexity; measured cycles where timing-critical>
```

A module may declare shared defaults, but each routine must reference them and list all exceptions. Keep comments synchronized with code. Explain bank/flag/ordering reasons in code comments rather than narrating every obvious instruction.

Stack numbers must identify what they include. Distinguish direct stack use from worst call-chain/interrupt contribution, and measured observations from proven bounds.

## G04. Distinguish syscall ABI from internal calling conventions

Keep the agreed public SWI direction: A identifies the syscall, X supplies an optional parameter block, D returns result/error, and carry distinguishes success/failure. Preserve the other application registers according to the finalized ABI.

Freeze exact native frames, CC effects, wrappers and entry/return handling before applications depend on them. Error return and result insertion must not be overwritten by restoring saved flags incorrectly.

Internal assembly routines may use efficient documented caller/callee-save conventions. They do not need to save every register merely because a public syscall preserves it. Publish module defaults and exceptions; document overlapping HD6309 register effects consistently.

Every entry needing DP, mappings or interrupt-state assumptions must declare them. A normal return restores temporary state unless its documented purpose changes that state. Restore the caller's prior interrupt-mask state rather than unconditionally enabling interrupts.

## G05. One authoritative interface definition

Maintain syscall IDs, errors, flags, structures, offsets, protocol commands and format versions in authoritative definitions. Generate assembly/C declarations where practical and validate any remaining cross-language layout assumptions.

Do not expose compiler-native structure packing as a binary ABI. Specify integer width, signedness, byte order, units, alignment, reserved fields and structure size explicitly. Preserve existing MLFS/on-disk encodings when defining wrappers around them.

Version public interfaces and executable/module/protocol formats. Unsupported calls/features/versions return defined errors. Binary compatibility across arbitrary MLOS releases is not promised, but a released version's declared contract must be internally consistent.

Use named constants and module-prefixed exported symbols; keep private labels local. Hardware addresses belong in the relevant backend definitions.

## G06. Predictable failure and buffer semantics

Use a common error vocabulary. Distinguish resource exhaustion, invalid/stale handles, BUSY, EOF, cancellation, timeout, unsupported operations and device/service failure as appropriate.

For every buffer or string API define:
- Length/capacity units and representable limits.
- Whether a string includes its terminator in the length, and which encoding applies.
- Zero-length/null-pointer behavior.
- Whether overlap is allowed and whether inputs are modified.
- Partial success, retry behavior and output state after failure.
- Whether required size is returned and whether data remains queued.

Check application-facing ranges, integer overflow, ownership and object state at the trusted boundary. Internal routines may use explicit preconditions to avoid redundant validation; do not label unchecked preconditions as recoverable errors.

Acquire resources provisionally and publish objects only after required initialization succeeds. Roll back unpublished resources on failure. Explicitly document persistent side effects, such as already written file bytes or redirection truncation, that are not undone.

## G07. Banked memory and ownership are part of the API

Use opaque validated handles for OS-owned banks, devices, files, channels and requests. Do not expose kernel object pointers or physical bank numbers as ordinary application capabilities.

For pointer-taking routines specify which process/address space owns the pointer, the required maps, and how long the pointer remains valid. Access application memory through the owning process map; a pointer into window 0 is not an ordinary kernel pointer after that window changes.

Declare whether a call copies, borrows or transfers data. An asynchronous request must not silently retain a temporary caller pointer. Follow the selected copied/bounded-buffer design or define an explicit supported reference/pin contract.

Track all live allocation/request references before reclaiming frames, buffers or instances. Withdraw mappings and references before reuse. Empty heap banks are reclaimed under the agreed rules; resource-bank contents are not implicitly released because their bytes happen to be zero.

## G08. Preemption-safe reusable state

Prefer reentrant routines using registers, the caller stack or explicit caller/instance state. “Assembly” does not imply reentrancy.

Do not hide scratch data in shared writable globals. When shared state is necessary, declare ownership, serialization, allowed callers and lifetime. A routine can be process-reentrant without being safe in IRQ context; document those separately.

Keep one driver code image with explicit per-device state. Do not store a mutable global current-card context that can be overwritten by a nested operation.

Identify lock/critical-section ordering. Avoid allocation, service calls, unbounded callbacks or sleeping while holding a lock/critical state whose users need to make progress. Future threads require synchronized process-map/runtime state, but are not silently introduced into the initial release.

## G09. Bound latency and choose blocking deliberately

Blocking calls sleep the process; they must not stall the whole machine. Use async/state-machine progress for slow devices and filesystem work.

Keep interrupt handlers and interrupt-masked sections bounded. Acknowledge/capture minimal work and defer longer processing to an appropriate context. Any necessary hardware polling loop needs a documented finite bound or timeout and a reason it belongs there.

Chunk long copies, rendering and storage operations where latency requires it. Do not hold hardware privilege/mapping transactions half-finished across arbitrary waits.

GUI clients must consume events during file work through the agreed completion/wait model. A modal dialog does not justify holding a kernel lock or ignoring redraw/completion traffic.

## G10. Hardware access stays in owned backends

Ordinary managed applications use OS/service APIs for both reads and writes. Unrestricted hardware reads do not transfer input-draining/acknowledgement ownership to arbitrary applications.

Centralize shared device-register state, including UART/timer masks and controls. Keep privilege entry/MMU transactions in reviewed routines.

Graphics requests go through the WM/backend ownership arrangement. Hardware-independent GUI calls must not expose VDC-specific registers. Keep future graphics capabilities extensible without building unneeded V9958 support now.

Keep trusted kernel-driver faults distinct from recoverable device errors. No claim of driver memory isolation or general RAM protection is made.

## G11. Measure size, stack and speed

Retain link maps and report ROM, core, common RAM, process frames, queues and buffers. Enforce established build-time size limits where possible.

Measure timing-critical entry/IRQ/context/render paths. Annotate CPU/mode and other assumptions with cycle claims; an estimate is not a target measurement.

Optimize with evidence. Reuse and small code matter on this system, but avoid excessive register saving, macro expansion or kernel-resident convenience code without evaluating its cost. No hidden unbounded heap/stack growth, queue or log.

Use bounded diagnostics. Normal logging follows the selected nonblocking policy; emergency reporting must not depend on ordinary filesystem/IPC services.

## G12. Verification and application-developer deliverables

Verify meaningful contracts: register preservation/flags, stack balance, map restoration, boundary/zero-length behavior, cross-window access, exhaustion rollback, stale identity, cancellation and interleaving where relevant.

Exercise public APIs through both assembly and CMOC clients. For lifetime/concurrency changes, include failure paths and pending-operation teardown. Do not add tests that merely restate trivial code.

Record simulator and hardware results separately. Build/format fixtures must be reproducible and destructive storage tests use disposable images.

Ship an SDK alongside public functionality:
- Assembly include files and CMOC headers/wrappers.
- A function/syscall reference with flags, errors, context, ownership and blocking behavior.
- Minimal assembly and C applications.
- Examples for files, IPC, banked resources, GUI event loops and async I/O as those features arrive.
- Image/build tools, supported versions and feature/limit descriptions.

## Proposed API coverage checklist

This identifies useful families, not a mandatory syscall for every item:

| Family | Initial public capabilities |
| --- | --- |
| System | Version/features, defined diagnostics and status queries |
| Processes | Spawn, exit, wait, controlled termination, yield, sleep/time |
| Memory | Ordinary allocation integration, resource banks/maps, resource-limit queries |
| IPC/services | Channel create/connect/accept, stream/message I/O, wait-any, close/readiness |
| Files/namespace | Open/read/write/seek/close, directory operations, cwd, mounts and status |
| Terminal | Standard I/O, line/raw control, geometry and foreground rules |
| Async I/O | Submit, wait/readiness, collect and cancel |
| GUI | Windows, events, drawing, resize, close, modality and geometry |
| Devices | Service-owned claims and documented class operations; trusted driver interfaces |
| Utilities | Local reusable memory/string/parser/conversion helpers |

Process status can be offered through the selected /proc/provider interfaces. GUI/file operations may be service APIs behind SDK wrappers. Future threads/colour/relocation remain separate versioned additions.

## Stage integration

- S00: establish naming, header template, authoritative definitions, build maps and SDK layout.
- S01–S04: enforce entry/register/flags/stack/map/latency contracts and hardware evidence.
- S05–S07: apply the same contracts to CMOC wrappers, allocation, IPC, modules and per-instance state.
- S08–S10: finalize file/error/ownership semantics and async lifetime rules.
- S11–S14: maintain hardware-independent GUI/input APIs and runnable application examples.
- S15–S16: qualify concrete drivers and audit code, documentation and tests for consistency.

## Proposed review checklist

Before merging a functional change, check:
1. Its public/internal boundary and implementation language follow the declared policy.
2. Every callable assembly entry has an accurate contract.
3. Flags, stack, DP, maps and interrupt-state effects match the documentation.
4. Ownership, failure rollback, pending I/O and cancellation are safe.
5. Blocking/critical work and memory admission are bounded.
6. Assembly/C interface definitions, wrappers and examples agree.
7. Relevant contract checks pass; size/timing effects are recorded where material.

The highest-priority additions to Eric's initial comment fields are **CC flags, execution context, bank/DP assumptions, ownership/lifetime, blocking/reentrancy and stack use**.

