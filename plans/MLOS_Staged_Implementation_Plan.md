# MLOS staged implementation plan

Version: 1.0 — 16 October 2026  
Source: MLOS Architecture Baseline, revision 0.44, 12 October 2026; source file MLOS_Architecture_Draft.md, observed version 43.

## Purpose and status

Build MLOS through small, testable increments, from a native HD6309 entry harness to a CF-booted console and monochrome desktop. This is a proposed implementation sequence derived from the agreed architecture. Tasks and suggested engineering defaults below are implementation recommendations, not claims that missing contracts have already been approved, coded or validated.

The architecture remains the policy authority. This plan does not change that baseline. No dates, effort estimates, implementation success or hardware test results are implied.

The initial product has one thread per process, preemption, no swapping, MLFS, separate window manager, terminal, file browser and Tetris. Later application multithreading remains necessary for the eventual product and has a separate follow-on stage.

## Release checkpoints

| Checkpoint | Stages | Observable result | Required evidence |
| --- | --- | --- | --- |
| K1: banked kernel | S00–S04 | CF boots a core and two diagnostic processes; preemption, yield and trap cleanup work | Correct registers/maps/stacks, boot rejection cases, timing and memory accounting; simulator and board results separately |
| C1: usable console | S05–S09 after K1 software prerequisites | Init starts a serial shell; commands load from MLFS; files and mounts work while other processes progress | Assembly and CMOC applications, file growth, locking, cancellation, recovery and independent-drive progress |
| G1: monochrome desktop | S10–S14 after C1 | GUI terminal runs the same shell; file browser and Tetris run together; modal windows and fallback work | Responsive event loops, bounded queues/rendering, resource fit and session-failure tests |
| X1: expansion validation | S15 after S07/S08; may overlap desktop work | Selected real expansion cards use shared drivers with separate state and exclusive service ownership | Multiple-instance and IRQ/failure tests on supplied cards; final controller hardware contract |
| R1: reproducible release | S16 after G1 and the declared expansion scope | Installable documented console/desktop release with recoverable failures | Reproducible image, full regression evidence and measured minimum-machine budget |

K1 software bring-up can proceed in the simulator while GAL work is pending. K1's board qualification remains incomplete until its hardware criteria pass. A later software stage may be developed against a tested simulator contract without falsely marking the board gate complete.

## Working rules

- A stage closes when its deliverables and exit checks are recorded. A visible demonstration alone is insufficient.
- Freeze each interface before its consumers depend on it; generate assembly and C definitions from one authoritative description where practical.
- Use a small vertical slice first, then add failure handling within the same stage before declaring it complete.
- Apply bounded admission to frames, handles, requests, queues, buffers and stacks. Exhaustion is a normal error.
- Keep code changes reviewable by work package. Maintain a requirements-to-interface-to-test index.
- Hardware-changing and destructive storage tests use designated test hardware/images. Keep simulator and physical-board evidence distinct.
- Record budgets at K1, C1 and G1. Additional metadata and temporary buffers count against the same 512 KiB machine.
- The driver ABI is trusted kernel code; per-drive failure isolation does not provide driver CPU-fault isolation.
- Keep history out of normative interface definitions. Mark prototypes and temporary boot paths explicitly.

## Dependency overview

| Stage | Principal prerequisites | Can progress independently |
| --- | --- | --- |
| S00 | Architecture baseline | Toolchain, contract inventory and test fixtures |
| S01 | S00 | Simulator/ROM work and physical GAL work are separate tracks |
| S02 | S01 software entry contract | Host-side allocator/model checks |
| S03 | S01/S02 minimal core entry | Host CF image construction and corruption fixtures |
| S04 | S01–S03 | Board timing/gate qualification alongside simulator scheduling |
| S05 | S04 software kernel | Application packer and CMOC startup work |
| S06 | S04/S05 | Service protocol definitions |
| S07 | S04/S06; module format from S05 | Hardware-card specification collection |
| S08 | S05–S07 | Host MLFS validation/repair tools |
| S09 | S05/S06/S08; serial transport from S07 | Shell parser and terminal model |
| S10 | S06/S08/S09 | Asynchronous client example |
| S11 | S02/S06/S07 | VDC and PS/2 work can be separate work packages |
| S12 | S06/S10/S11 | GUI protocol/client model tests |
| S13 | S09/S10/S12 | Shared terminal decoder/model reused |
| S14 | S08/S10/S12/S13 | Browser and Tetris are independent applications |
| S15 | S07/S08 plus supplied hardware contracts | May precede or overlap S10–S14 |
| S16 | S00–S14, plus selected S15 scope | Documentation and release automation accumulate throughout |

## S00 — Reproducible development environment and contract inventory

**Goal:** A developer can build and run a minimal MLOS-target image, and identify the authoritative hardware/interface definitions.

**Work packages**

1. Pin assembler, CMOC, linker, simulator and image-tool versions/options. Record source revisions and the intended 512 KiB target configuration.
2. Establish source/build boundaries for BIOS/ROM, core, services, applications, trusted drivers, shared headers and host image/test tools. Adapt to actual repository layout; this plan does not mandate new repositories.
3. Create build/run/debug commands, map-file generation, symbol outputs and an automated smoke harness with bounded serial capture.
4. Create a normative hardware profile: logical windows, physical-frame count, ROM/I/O overlay, vectors, MMU/gate, UART/timer, CF, VDC and PS/2 assumptions.
5. Inventory interfaces that need exact definitions: native entry/context, boot info, kernel/application/module images, syscalls, handles, descriptors, IPC, driver requests, filesystem and GUI.
6. Create an initial core/common/ROM budget and requirement/test index. Assign an owner or evidence source to each unresolved hardware fact.
7. Define reproducible disposable CF image fixtures. Include pristine and intentionally malformed copies.

**Deliverables:** Pinned build instructions, minimal harness, hardware-profile draft, contract index, initial budget and test-image recipe.

**Exit checks:** A clean environment repeats the build; the harness starts in the simulator and records expected serial output; link maps and image provenance are retained. Unsupported hardware details are visible rather than guessed.

**Architecture coverage:** §§1, 3–5, 10, 12–14.

## S01 — Native ROM entry and privilege-gate harness

**Goal:** Enter and leave a small native-mode kernel context without losing CPU, stack, mappings or privilege state.

**Work packages**

1. Specify exact native HD6309 frames, software saves, DP/mode policy, register/CC results and application/kernel/emergency stack transitions.
2. Specify reset, SWI, IRQ, trap and reserved-NMI paths. Define safe defaults for FIRQ and unsupported SWI variants rather than leaving vector behavior undefined. Select a minimal bounded NMI default; debugger facilities remain deferred.
3. Define the internal SWI bridge reason/continuation protocol and nested-entry records. Do not infer pre-entry privilege from F405 after an unlock event.
4. Implement ROM stubs and a static common-RAM test workspace. Switch stacks before replacing application window 0 and restore mappings from ROM before application return.
5. Model SWI/NMI/reset unlock, F405 relock and bit-7 readback in the simulator. Unprivileged I/O writes are ignored; reads and ordinary RAM writes retain their agreed behavior.
6. Complete stage-3 GAL equations/routing/fit work against installed parts. Resolve vector qualification, reset/NMI coverage, write gating and retained status driving.
7. Audit UART/timer shared control and implement combined mask/control ownership. Verify timer acknowledgement and necessary privileged bridges.
8. Run entry/return tests with register and mapping sentinels, including nested privileged activity and bounded failure diagnostics.

**Deliverables:** Entry/return contract and assembly harness; simulator gate model; GAL source/fit artifacts and board test procedure/results when hardware is available.

**Exit checks:** Simulator traces match the contract. Physical qualification separately proves actual vector unlock, denied writes, reads, RAM writes, map updates, bit-7 masking/readback and relock. Static stack sentinels survive the exercised paths.

**Dependency note:** Simulator-proven entry permits subsequent software development while physical GAL work remains explicitly open. The real-board K1 gate cannot be claimed complete.

**Architecture coverage:** §§3–5, 9, 10.3–10.5, 14.4.

## S02 — Core memory ownership and minimum syscall boundary

**Goal:** The core owns frame allocation and mappings, with a safe application-to-kernel call path.

**Work packages**

1. Finalize addressed core/common maps for the entry harness, current context, stacks, frame records and minimum process metadata.
2. Reserve whole physical frames 0, 1 and 2 for core, common and discard. On 512 KiB, admit only the remaining 29 frames (464 KiB) for all services, applications, drivers, metadata and buffers; never infer installed RAM from maximum expansion capacity.
3. Implement frame allocation/free with ownership checks, provisional allocations and rollback. Add explicit process-map and resident/resource/uncommitted role records.
4. Implement validated map changes and vacant-window parking. Reject reserved frames and unsafe remapping of live resident windows.
5. Implement bounded copy-in/copy-out through recorded application maps, including ranges crossing window boundaries and overflow checks.
6. Publish the first numbered syscall subset, register effects, parameter layouts and errors. Include diagnostic output, basic resource operations and the entry test calls.
7. Introduce a coherent object/handle identity scheme and reference/pin primitives for later pending operations. Decide representation and reuse rules before publishing handles.
8. Add frame accounting and diagnostic reports; identify metadata that must remain common versus separately banked. Budget the exposed 8 KiB common window separately from its reserved 16 KiB physical frame. Account for the 1 KiB I/O overlay within the upper 8 KiB ROM address range, plus vectors and tables.

**Deliverables:** Core/common linker maps, frame/map manager, initial syscall headers for assembly/C and banked-memory copy helpers.

**Exit checks:** Reserved frames never allocate; vacant windows point to discard; invalid maps/copies fail without partial state; injected allocation failures restore accounting; pointers into application window 0 are handled correctly after kernel mapping.

**Architecture coverage:** §§3, 4, 10.5–10.7, 14.1.

## S03 — Validated CF-to-kernel boot

**Goal:** The selected MLFS boot convention loads a valid kernel and rejects invalid images safely.

**Work packages**

1. Freeze kernel-header magic/version/encoding, payload size, entry constraints, integrity algorithm and boot-information record.
2. Implement ROM read-only traversal of MLPT, designated boot partition, supported superblock/root directory and root mlos.bin.
3. Enforce initial 512-byte MLFS blocks, one kernel extent and a core payload fitting bank 0. Read declared payload, not unused extent capacity.
4. Check partition/device/file/extent bounds and arithmetic overflow. Preserve boot stack/common records and safe load-failure diagnostics.
5. Implement host CF formatter/packer/installer support for this convention. Keep the existing sector-zero jump stub out of the selected path.
6. Pass validated hardware/configuration information to the kernel; make the ROM-to-core transition explicit.
7. Define the early-service bootstrap mechanism. Recommended starting implementation: retain a restricted read-only boot provider that loads a fixed manifest of init/filesystem/required images until runtime services take over. Confirm its ROM/core cost; if it does not fit, specify a versioned initial-module bundle instead. Select one mechanism before S05 consumes it.

**Deliverables:** Boot/header ABI, ROM loader, disposable boot image builder and selected bootstrap-provider contract.

**Exit checks:** Cold boot reaches core diagnostics; missing, truncated, wrong-version, corrupt, oversized and out-of-range images never execute; rejection returns to bounded serial BIOS diagnostics. Host tools reproduce the same structural image layout.

**Architecture coverage:** §§3.1, 10, 14.2.

## S04 — Preemptive processes, waits and traps: K1

**Goal:** Two private-bank test processes run under timer scheduling; terminating one leaves the other working.

**Work packages**

1. Implement process/thread records with one thread per process, run/block/dying transitions, saved stacks/maps and an idle path.
2. Add explicit yield, sleep, monotonic time and basic wait transitions. Specify deadline units/wrap and deferred scheduling around short critical updates.
3. Implement the selected XR88C92 timer candidate and measure actual tick rate. Begin with five-tick quanta and configurable 4:2:1 class weights.
4. Implement weighted dispatch with nonzero share for every runnable class and round-robin within classes. Define accounting after yield/block/exit and empty-class behavior.
5. Supply two small diagnostic images without requiring general filesystem services or the shell.
6. Implement exit, wait-for-exit and kernel-managed termination with ordered resource teardown. Use a dying/pending-cleanup state where work still holds references.
7. Log and terminate application traps under the selected initial policy; use bounded emergency serial/halt for core faults.
8. Exercise low memory and failed process publication. Publish a process only after its required resources are ready.

**Deliverables:** Scheduler/context-switch code, timer integration, diagnostic processes, trap/termination path and K1 evidence report.

**Exit checks:** Same logical addresses retain different sentinel data across processes; a non-yielding test process is preempted; yield/block/idle work; lower classes progress; native registers/S/maps survive; trap cleanup releases resources and the survivor continues. Record linked sizes, stack observations, actual tick/quantum and interrupt/context cost.

**K1 acceptance:** Software criteria may pass first in the simulator. K1 board qualification additionally requires S01 physical gate and integrated CF/timer tests. This is mapping correctness, not a claim of general RAM isolation.

**Architecture coverage:** §§2, 3, 9, 10.2–10.5, 14.3.

## S05 — Real executable loading, CMOC runtime and early init

**Goal:** Fixed-linked assembly and CMOC programs load with valid arguments, stacks and memory ownership.

**Work packages**

1. Freeze application-header bytes, ABI version, logical origins, entry, data/BSS, stack, arguments, window roles and size validation.
2. Implement one-, two- and three-resident-bank loading within the total 48 KiB footprint. Physical backing need not be adjacent.
3. Implement argv/startup, CMOC shim, syscall wrappers, exit status and per-process runtime state. Default stack reservation starts at the agreed configurable 1 KiB, subject to measured headroom.
4. Implement heap regions and automatic growth into eligible uncommitted windows. Support ordinary allocations spanning adjacent logical windows.
5. Implement empty heap-frame reclamation with live-object and pending-reference checks, mapping revocation and discard parking before reuse. No live-pointer relocation or swapping.
6. Implement extra resource-bank handles/maps with the declared role restrictions.
7. Implement spawn preflight, provisional resources, wait/exit and controlled inheritance. Establish session/terminal-scope identities that survive intermediate-parent exit; complete their TTY use in S09/S13.
8. Use S03's selected bootstrap provider to load an early init stub and required initial service images. Define the explicit transition to runtime loading and release only bootstrap resources no longer needed.

**Deliverables:** Image packer, loader, CMOC startup/runtime subset, application examples, heap/bank APIs and early-init bootstrap.

**Exit checks:** Assembly and CMOC programs receive correct arguments/exit statuses; BSS clears; malformed layouts reject; a valid spanning allocation survives preemption; physical/logical exhaustion returns failure; empty eligible frames return; pinned/live banks do not. Unsupported relocation formats reject explicitly.

**Architecture coverage:** §§1, 3, 10, 10.5–10.8.

## S06 — IPC, named services and race-free waiting

**Goal:** Processes exchange data and wait for service activity without polling, lost wakeups or leaked endpoints.

**Work packages**

1. Freeze SPSC stream/message calls and structures, payload-capacity accounting, counts and error semantics. Default payload capacity is 512 bytes; other positive capacities remain subject to representability and admission.
2. Implement kernel-owned banked backing and copied access, so a full 48 KiB resident application can use IPC.
3. Implement all-or-nothing message admission, required-size reporting without consumption, stream partial results and explicit nonblocking behavior.
4. Implement atomic readiness/check-register-sleep and wait-any with optional deadlines. Include completion/object closure readiness.
5. Implement named service listeners, connect/accept, private one-way channel pairs, admission failure and cancellation.
6. Implement producer close/death, retained unread data, consumer drain/exit and writer failure. Preserve the agreed no-drain-timeout rule.
7. Complete generation/reference checks and service-instance teardown. Service death notifies clients; reconnection is explicit.
8. Add bounded queue-pressure and wait-race fixtures.

**Deliverables:** IPC/service ABI, channel/wait implementation, echo service and state/lifetime diagrams or tables.

**Exit checks:** No lost wakeups under scheduling interleavings; small receive buffers leave messages queued; producer death preserves drainable data; consumer death releases retained storage safely; arbitrary admitted capacities work; full queues and service disappearance return defined results.

**Architecture coverage:** §§6, 6.2, 10.2.

## S07 — Trusted driver modules and asynchronous device requests

**Goal:** Kernel-controlled hardware has a reusable driver framework with separate per-instance state and bounded progress.

**Work packages**

1. Freeze trusted-module header/import/entry ABI, module-code mapping, callback stacks, instance access and reentrancy rules.
2. Implement boot/console module loading and validation. Retain accepted code until reboot; no runtime unload in the initial scope.
3. Define character/block/control operations, transfer limits, completion/error tokens, cancellation, timeouts and request ownership.
4. Adapt builtin CF and serial support to the runtime interface without making bootstrap depend on a module stored on that same device.
5. Implement shared UART/timer register ownership, bounded RX/TX/IRQ work and independent interactive/log paths.
6. Implement exclusive raw-device service claims and safe owner death: stop submissions, settle/quiesce requests and callbacks, then release ownership.
7. Implement shared driver code with independently allocated instance buffers/state. Use mock or simulator instances to validate the framework before all expansion cards exist.
8. Add the expansion-controller adaptation boundary around provisional pending/mask behavior; confirm real offsets/routing before actual-card qualification.

**Deliverables:** Driver/module ABI and loader, request engine, builtin device adapters, mock multi-instance tests and binding-configuration format.

**Exit checks:** Slow/pending device work allows unrelated process progress; completions target the correct request/instance; second-instance bind failure rolls back; one raw owner is enforced; owner termination cannot free live DMA/PIO/request buffers. Trusted driver CPU faults follow core-fault policy.

**Architecture coverage:** §§4, 10.4, 11.1–11.5.

## S08 — MLFS service, mounts and file integrity

**Goal:** One filesystem service manages several drives, supports ordinary file operations and isolates local storage failures.

**Work packages**

1. Pin supported MLFS/MLPT format versions and existing limits, including partition interpretation and initial 512-byte blocks. Keep the desired up-to-4 KiB extension explicit; do not assume support before it is implemented.
2. Freeze filesystem messages, descriptor/path limits, seek/offset widths, errors and per-drive/volume/file/cache identities.
3. Refactor synchronous filesystem operations into bounded request continuations/state machines, or implement an explicitly supported worker model. A one-thread service must dispatch other drives while one waits.
4. First deliver read-only mount/list/open/read/close through asynchronous block requests; then add create/write/truncate/file growth and selected rename/delete/directory operations.
5. Implement shared readers, exclusive writers and BUSY conflicts, including namespace changes affecting live references.
6. Implement mounted absolute/relative path dispatch, per-process cwd, inherited directory references and read-only /proc snapshots independent of MLFS availability.
7. Implement extent growth, bounded cache/buffers and metadata sequencing. Define clean/dirty representation, device flush assumptions and validate-before-writable-mount.
8. Build offline/image validation and explicit repair tools. Suspect volumes are read-only where safe or unavailable, with no unsupported durability promise.
9. Implement affected-volume offline state, safe pending-request cancellation, healthy-drive access, explicit recovery and fresh handle generations. Stale cwd stays unusable until explicit absolute chdir.
10. Complete close/partial-I/O/stale-handle semantics and busy-unmount/reference cleanup. Filesystem-service failure disables all filesystems it owns and retains diagnostics.

**Deliverables:** MLFS service, namespace/descriptor providers, growth implementation, validation/repair tools and storage failure fixtures.

**Exit checks:** Growing a file beyond its first extent preserves content; two drives progress independently under injected waits; readers/writers obey conflicts; failed drive does not disable a healthy one; service crash has its broader defined effect; stale handles/cwd never silently rebind; safe cleanup permits later explicit recovery. Interrupted-write tests use disposable images.

**Architecture coverage:** §§7–7.4, 10.2, 11.6.

## S09 — Serial TTY, init and shell: C1

**Goal:** CF boots a usable serial console that loads commands from MLFS and preserves diagnostics through failures.

**Work packages**

1. Complete init's startup manifest/dependencies, service readiness and console launch. Hand ordinary filesystem access to S08; retain only necessary bootstrap/emergency support.
2. Implement logical TTY providers with one foreground input owner, line editing/echo, raw mode and setting restoration.
3. Use configurable UART A interactive and UART B output-only logs. Implement bounded nonblocking log records with discard-oldest accounting and a separate emergency path.
4. Freeze the initial monochrome terminal control subset, Latin-1 behavior, shared special-key decoder, CR/LF and line/parser limits. Keep no-scrollback scope.
5. Implement shell builtins, foreground spawn/wait, quoted arguments and < / > redirection with child-exclusive writer ownership and defined create/truncate ordering.
6. Implement standard descriptors 0/1/2 and separate per-process SPSC channels where a shared provider serves several processes.
7. Implement Ctrl-C foreground termination and safe pending-operation cleanup in line/raw modes. Restore terminal settings and foreground ownership.
8. Provide initial commands covering navigation, directory listing, file display/copy/create/remove, process/memory/mount diagnostics and module/GUI startup entry points as those later features become available.
9. Implement selected failures: shell restarts once; repeated failure reaches emergency diagnostics; init/core faults halt; MLFS failure does not remove /proc/emergency paths.

**Deliverables:** Init, shell, TTY service/provider, shared terminal definitions, basic commands and installable C1 CF image.

**Exit checks:** Cold CF boot reaches the shell; assembly and CMOC commands execute; quoted args/redirection work; background services progress; typeahead belongs to the TTY across handoff; background input fails appropriately; Ctrl-C during file work is safe; low memory and service loss leave defined diagnostics.

**C1 acceptance:** Repeatable console workflow plus S08 storage/failure checks. Pipelines, background shell syntax, append and expansion/substitution remain deferred.

**Architecture coverage:** §§1, 7, 8.1–8.4, 10.1–10.2, 10.8–10.9.

## S10 — Asynchronous application I/O and temporary CF transfers

**Goal:** A single-thread GUI client can continue handling events during storage work; large IPC handoffs have safe temporary-file lifetimes.

**Work packages**

1. Freeze async submit/token/readiness/collect/cancel calls, per-descriptor ordering, chunk limits and completion lifetime.
2. Copy accepted write chunks into admitted kernel/service storage; retain read results until collection into revalidated application memory.
3. Keep completion state discoverable when a notification queue is full; prevent lost wakeups, duplicate collection and descriptor-number reuse confusion.
4. Implement cancellation/process death without freeing buffers until device work is quiescent. Completed writes are not promised to roll back.
5. Implement temporary CF transfer predeclaration/preallocation, sequential exact-length writing, finalize-before-publication, queued references, reader completion and deletion.
6. Define zero-length transfers, wide offsets and failed finalization. Reclaim identifiable prior-session transfer files only after safe mounting.
7. Keep blocking descriptor calls available for simple console programs.

**Deliverables:** Async client/runtime API, responsiveness example and temporary-transfer facility.

**Exit checks:** A client services IPC while a slow file request is pending; completion queue pressure loses no result; cancellation does not reuse live memory; incomplete transfers cannot publish; producer death preserves queued referenced data; final reference release reclaims temporary storage.

**Architecture coverage:** §§6.1, 8.8.

## S11 — Monochrome video backend and PS/2 input

**Goal:** Hardware-independent drawing/input interfaces operate on the initial VDC/PS2 target.

**Work packages**

1. Define a narrow backend for mode initialization, geometry, bounded fills, glyph/text runs, bitmap chunks and cursor/damage operations. Keep VDC register details outside application protocols.
2. Implement MOS 8568 initialization for the intended 640×400 interlaced monochrome mode and document actual VRAM allocation.
3. Validate/fix the simulator bitmap/interlace behavior required by the chosen backend; retain a real-board test pattern.
4. Measure transfer cost and chunk long rendering work so input and scheduler progress remain bounded.
5. Verify the actual PS/2 transport/register/IRQ or polling contract. Implement keyboard/mouse framing, buffering, overflow and reconnect/recovery.
6. Implement Swedish layout/Latin-1 translation with hardware-independent key identities, modifiers and generated text; define repeat/dead-key/LED behavior.
7. Build a minimal graphics console using shared text/input rules, available as the WM-failure fallback.

**Deliverables:** VDC backend, PS/2 transport and translation, fonts/glyph map, test application and graphics console.

**Exit checks:** Geometry/test patterns and glyphs render correctly; keyboard and mouse operate together under load; overflow/reconnect has bounded recovery; long draws do not stall serial/timer work; simulator and target rendering results are distinguished.

**Architecture coverage:** §§8, 8.4, 8.6; later V9958 support remains a backend extension.

## S12 — Separate window manager and client library

**Goal:** Several processes own responsive windows through a versioned GUI protocol.

**Work packages**

1. Freeze GUI command/event structures, IDs/generations, geometry/coordinate/stride limits, errors and service connection rules.
2. Give the WM exclusive graphics ownership through kernel-controlled interfaces. Applications use the protocol rather than direct device access.
3. Implement stacking, decorations, click focus/raise, content hit testing, client capture, focus/capture loss and outline dragging.
4. Implement application-owned redraw, manager-owned damage/visibility/clipping, bounded drawing requests and fair client dispatch.
5. Implement nonblocking event publication, replaceable-event coalescing and bounded essential backlog. Disconnect an overflowing client without automatically killing its non-GUI process.
6. Implement cooperative close versus explicit force-quit. Destroy window resources independently of application lifetime where applicable.
7. Implement resize prepare/accept/reject/commit/abort with epochs and deadlines, retaining old geometry on failure.
8. Implement owner-window and optional application-wide modality, acyclic nested ownership, input fencing and focus restoration. Modality must not stop service/redraw traffic or other applications.
9. Implement GUI session identities and descendant teardown. WM failure closes the session's applications, reclaims resources and falls back to graphics console or serial.
10. Provide a client event-loop library and minimal test clients, including a nested-modal and stalled-client fixture.

**Deliverables:** WM process, versioned GUI headers/client library, bounded renderer/event queues and conformance clients.

**Exit checks:** Multiple clients redraw and receive input fairly; stale IDs/epochs reject; modal activation consumes blocked input correctly; resize allocation failure preserves old state; stalled clients do not freeze the WM; client disconnect and WM/session failure have their distinct cleanup scopes.

**Architecture coverage:** §§8.5–8.8, 10.1–10.2.

## S13 — GUI terminal using the same shell

**Goal:** The existing console shell runs unchanged behind a GUI terminal provider.

**Work packages**

1. Reuse S09 TTY/decoder semantics and implement a bounded cell model with the agreed controls and no scrollback.
2. Translate GUI keys/text to Latin-1 and shared special-key sequences without applying a keystroke twice.
3. Render damaged cell regions through the GUI client API; derive rows/columns from committed geometry.
4. Handle resize preparation, model allocation failure and redraw. Specify any alternate-screen support explicitly before requiring it in applications.
5. Connect a hosted shell with proper standard descriptors and foreground input ownership.
6. Implement owned terminal scopes for the shell/jobs. Closing or force-quitting one terminal safely ends its scope, without ending other terminals.
7. Integrate async event/I/O waits so shell output or storage waits do not stop window event servicing.

**Deliverables:** GUI terminal application and shared serial/GUI terminal-profile tests.

**Exit checks:** The same shell and commands work over serial and GUI; line/raw modes, Ctrl-C and key decoding agree; resize/OOM/close work; closing one terminal cleans its jobs and leaves another terminal running.

**Architecture coverage:** §§8.1–8.4, 8.6, 8.8.

## S14 — File browser and Tetris: G1

**Goal:** Complete the initial desktop acceptance scenarios with real applications.

**Work packages**

1. Specify the first MC-style browser's navigation and file operations: two-pane or selected initial layout, Latin-1/case-sensitive names, directory changes, copy/move/delete and operation progress/errors.
2. Implement file work in bounded async chunks; retain redraw/input during slow storage.
3. Use modal dialogs for confirmations and errors; define cancellation without promising rollback of already written data.
4. Handle BUSY files, read-only/failed volumes, stale handles and invalid cwd. Request fresh handles after recovery.
5. Implement Tetris as a native GUI client with board/state redraw, key events and monotonic-time-based game updates independent of scheduler tick counts.
6. Make game geometry/focus-loss behavior explicit. Fixed client size is acceptable under the agreed window model.
7. Run terminal, browser and game together on the minimum 512 KiB configuration. Reduce admitted caches/queues or application limits based on evidence without changing the architecture silently.

**Deliverables:** Browser, Tetris, application-level tests and a complete G1 desktop image.

**Exit checks:** CF→console→WM→terminal works; browser manipulates MLFS files; Tetris remains playable while files transfer; modal dialogs do not freeze other apps; low memory produces recoverable errors; WM crash reclaims GUI descendants and returns to the selected fallback.

**G1 acceptance:** All four original user acceptance scenarios pass, together with measured core/common/ROM/frame/stack budgets and demonstrated responsiveness.

**Architecture coverage:** §§1, 7–8, 10.

## S15 — Real expansion cards and multiple instances: X1

**Goal:** Qualify the framework on explicitly selected expansion hardware.

**Work packages**

1. Freeze final baseboard register offsets, pending/enable semantics, reset state, IRQ routing and fixed slot resources. Preserve the confirmed 32-byte slot-2 correction.
2. Collect actual controller documents, transfer/data widths, timing, FIFO/rate and reset/error behavior for the first selected cards.
3. Bind cards through explicit configuration; keep automatic ID/I2C EEPROM discovery deferred.
4. Implement at least the selected first storage card and a second compatible instance where hardware is supplied. Verify one code image with separate state/buffers.
5. Connect several raw drives to the same filesystem service and repeat healthy-drive progress and failure/recovery tests.
6. Add ADC/printer/modem/network drivers as separate class-specific work packages once their hardware contracts exist. Define the serving service/protocol scope for each.
7. Decide whether particular rates require DMA; do not imply a DMA subsystem already exists because the bus has handshake provisions.
8. Prove cancellation, interrupt-source dispatch, partial bind rollback and safe service-owner replacement.

**Deliverables:** Final expansion-controller adapter, selected card drivers/configuration and per-card qualification reports.

**Exit checks:** Repeated identical cards remain independent; one failed card/controller affects only its documented scope; raw ownership is exclusive; callbacks cannot reference freed state; recovered applications obtain fresh handles.

**Scope gate:** The generic framework is required. Qualification of every planned future card and a full network stack is not a prerequisite for the first console/desktop. Publish exactly which cards and protocols the release supports.

**Architecture coverage:** §§11.1–11.6.

## S16 — Release hardening, installation and recovery: R1

**Goal:** Another developer can build, install, exercise and diagnose the declared MLOS release.

**Work packages**

1. Run integrated cold/warm boot and sustained console/desktop workloads at the minimum hardware profile.
2. Exercise repeated launch/exit, queue pressure, frame/handle/request exhaustion, pending-I/O termination, modal/resize races and failed service recovery.
3. Repeat malformed boot and interrupted-write/recovery fixtures. Check that no test silently changes a real user-data image.
4. Reconcile runtime accounting after each workload: frames, objects, references, device claims, file ownership and GUI scopes.
5. Measure boot time, timer/context/IRQ cost, maximum observed critical sections, interactive progress, video throughput and stack headroom.
6. Publish reproducible ROM/core/service/module/application/CF-image commands and supported ABI/hardware versions.
7. Document installation, serial recovery, filesystem validation/repair, explicit volume recovery and supported-card limitations.
8. Audit the normative spec against code and acceptance tests. Keep historical proposals separate; correct stale “unresolved” wording where a policy is already settled.
9. Tag the tested source/configuration set and preserve simulator and board evidence, known limitations and budget results.

**Deliverables:** Release image, build/installation/recovery instructions, supported-feature matrix, regression results and measured budgets.

**Exit checks:** A clean build produces the declared artifacts; documented installation reaches the same acceptance scenarios; required board checks have passed; failures follow the selected policies; unresolved work is explicitly outside the release scope rather than hidden in a passed stage.

**Architecture coverage:** Entire initial-release baseline.

## Follow-on stages for the eventual product

| Stage | Goal | Required prerequisite/design work |
| --- | --- | --- |
| F01: application multithreading | Multiple threads share a process safely | Thread ABI, stack/admission policy, shared-map synchronization, runtime/TLS/reentrancy, wait/cancel/join rules; retain existing process ownership |
| F02: relocatable loading | Remove initial fixed-link limitations | Relocation records, toolchain production/validation, loader versioning; live pointers remain stable after launch |
| F03: additional storage block sizes | Extend beyond initial 512-byte filesystem blocks where supported | Audit on-disk format, bounded cache/buffer admission, boot/runtime compatibility and up-to-4 KiB tests |
| F04: colour and V9958 | Extend terminal/video capability | Backend capabilities, colour text representation, VRAM/mode budgets and application compatibility |
| F05: discovery and wider cards | Automatic identification and more services | Final baseboard ID/I2C contracts, per-card configuration, networking/service requirements and rate-driven DMA decisions |

F01 closes the eventual multithreading requirement; it is intentionally outside the one-thread-per-process first release. These stages require their own acceptance criteria before implementation begins.

## Cross-cutting contracts and stage ownership

| Contract/artifact | First defined | Completed/expanded | Primary consumers |
| --- | --- | --- | --- |
| Hardware profile and memory budgets | S00 | S01/S02; measured at K1/C1/G1 | ROM, kernel, drivers, tools |
| Native entry/context and privilege continuation | S01 | S04; regression thereafter | Scheduler, syscall/trap paths |
| Boot header/info and early loader | S03 | S05/S09 handoff | ROM, init, image tools |
| Syscalls, errors, handle identity | S02 | S05/S06/S10 | Assembly/CMOC applications |
| Application image/runtime | S05 | Versioned future relocation/thread extensions | Loader, compiler wrappers |
| Channel/service protocol | S06 | Specific service definitions S08/S12 | Filesystem, GUI, TTY clients |
| Driver/module/request ABI | S05 format; S07 operations | S15 hardware qualification | Kernel drivers and owner services |
| Filesystem/namespace/persistence | S08 | S10 transfers; S16 evidence | Shell, browser, applications |
| TTY/key/control profile | S09 | S11 input and S13 GUI parity | Shell, terminal, text apps |
| GUI wire format and client API | S12 | S13/S14 applications | WM and native GUI clients |
| Requirements/test/evidence index | S00 | Every stage; release audit S16 | Maintainers and reviewers |

## Risks and decision handling

| Risk/dependency | Response in this plan | What would justify a scope/design change |
| --- | --- | --- |
| GAL implementation or routing not yet ready | Simulator software track plus a separate board qualification gate | Fitted equations or measurements prove the selected wiring insufficient |
| Core/common/ROM capacity | Early addressed budgets and measured maps; bounded admission | Linked code/data does not fit after reasonable placement work; specify additional kernel-bank support deliberately |
| Bootstrap reader cost/dependency loop | Choose and version one early-service loading mechanism in S03 | Reader/bundle measurements contradict the selected budget |
| Existing synchronous MLFS | Explicit continuation/worker refactor in S08 | Measured service progress cannot satisfy multi-drive/event-loop requirements |
| Unknown expansion cards/register offsets | Framework/mock validation first, concrete hardware gate S15 | Final controller/data-rate facts require class changes or DMA |
| CMOC runtime assumptions | Early real C application and allocation/stdio checks | Startup/ABI/library constraints require wrappers or a reduced runtime |
| GUI/storage pressure on 512 KiB | Client-owned models, chunked work, bounded queues and repeated budgets | Required concurrent acceptance workload cannot fit or remain responsive |

Routine binary layouts, opcode assignments and struct choices should be drafted and checked by the implementer. User decisions are needed when measurements force a change to accepted behavior or when hardware/product facts are genuinely unavailable.

## Suggested first implementation work queue

1. Establish S00's pinned minimal build, map files and disposable image fixtures.
2. Write the exact native entry/return and privilege-continuation contract.
3. Implement S01's static entry/gate harness and separate simulator/board checks.
4. Assign the initial common-RAM addresses and implement S02's frame/map/copy primitives.
5. Publish the kernel-image header and implement S03's validated ROM load path.
6. Add the two diagnostic processes and complete S04's measured K1 bring-up.

This is the first bounded development objective. Shell, full MLFS service and GUI are consumers of that foundation and follow the later stage gates.

