# MLOS Architecture Baseline

Agreed design baseline and decision record — revision 0.44, 12 October 2026

This is a planning document, not an implemented or validated kernel specification. User decisions are separated from proposals and unresolved mechanisms. No repository changes are included.

## Baseline at a glance

The product/system policies and first kernel milestone below are agreed. Exact byte layouts, core/common-RAM addresses and budgets, hardware equations/timing, and target implementation remain unfinished. Sections 12–14 identify that work; section 15 preserves historical decisions without treating old proposals as current policy.

| Area | Agreed starting direction |
| --- | --- |
| CPU/processes | HD6309 native mode; timer preemption, yield and fair weighted dispatch; one thread per process initially; resource-limited process count. |
| Memory | Physical bank 0 core, bank 1 common frame, bank 2 discard frame; whole-frame reservation; up to 48 KiB resident footprint plus explicit banked resources; no swapping. |
| BIOS/kernel | Editable BIOS hardware layer; OS owns allocations/maps; all I/O writes are privilege-gated, including MMU updates; all reads are unrestricted; denied writes are ignored; SWI/NMI/reset entry and F405 relock; F405 status bit 7 is 1=privileged/0=locked, other bits unspecified and masked. Ordinary applications use OS APIs for device reads. Stage-3 GAL logic and validation remain pending. |
| IPC | Kernel-owned copied SPSC streams/messages, named service channel pairs, wait on multiple channels, temporary exact-length CF handoff. |
| Files | Mandatory MLFS; one filesystem service can exclusively own several drives under the shared mount namespace; per-process cwd, shared file readers/exclusive writer, ordinary-file growth and conservative interrupted-write recovery. Drive/controller failures isolate affected volumes while healthy volumes remain accessible; recovered volumes require fresh application handles. An affected cwd stays unusable until explicit absolute chdir; processes remain alive. |
| Expansion | Loadable drivers required; user-provided page 5 defines two baseboards with six fixed I/O slots each at F600–F7FF. Slot 2 is confirmed as 32 bytes; A4 is don't-care. Baseboard identification and per-card I2C EEPROM configuration are future features; manual binding is proposed initially. Trusted banked modules share one code image across compatible cards, with separate per-card state/buffers; they load from CF at boot or by console command and remain until reboot. Raw devices have one exclusive service owner, which serves multiple clients. The non-clearing six-slot pending bitmap and reset-disabled enable mask are provisionally agreed, subject to final hardware. Register offsets/routing and device interfaces remain pending. |
| Terminal | UART A interactive, UART B logs, configurable; Swedish/Latin-1 input; line/raw modes; initial monochrome control subset, no scrollback, later colour ANSI. |
| GUI | Separate window manager; application redraw models; focus/capture, cooperative close/force-quit, negotiated resize, owner/application modality; bounded event delivery; optional async GUI I/O. |
| First milestone | Read-only ROM loader finds /mlos.bin in the boot partition; validated bank-0 kernel boots serial diagnostics and two private-bank test processes; measure state preservation, preemption, trap cleanup and RAM use. |
| Validation state | Planning/source review only. No implementation, successful build, simulator pass, or physical-board pass is claimed. |

## 1. Product and release goals — agreed

MLOS targets microLind with an HD6309. The end product is a mouse-driven GUI with simple window management and multithreading. The window manager is a separate process, and the same kernel must also support console operation without it.

The minimum configuration is 512 KiB RAM and CompactFlash. Console operation requires a serial terminal. GUI operation initially requires the VDC and PS/2 mouse and keyboard interface.

The initial console release does not need application threads. Shell commands execute synchronously from the user's perspective. That does not remove the requirement for preemption, asynchronous device progress, and multiple service/application processes. The kernel should retain a process/thread distinction so threads can be added later.

Acceptance scenarios:

1. Boot from CF into a console and execute commands.
2. Start the window manager and a GUI terminal using the same MLOS shell.
3. Browse and manipulate files with a Midnight Commander-style application.
4. Run Tetris within the GUI.

The former fixed limit of 16 tasks is withdrawn. Capacity is configurable/resource-limited. Failed process creation and memory allocation must return errors. There is no swapping.

Applications may depend on the MLOS release. Application development must support assembly and CMOC. The current focus is 6309 only. BIOS interfaces are editable and there is no legacy binary compatibility requirement at this stage.

New requirement: MLOS must support loading drivers for a planned expansion board carrying several add-on cards, including disk drives/IDE hard drives, ADC, parallel printer and modem/network hardware. Fixed slot addressing is now supplied and slot 2's 32-byte size is confirmed. Card identification through the baseboard and optional per-card I2C EEPROM configuration are future features. Exact controllers, interrupt routing, throughput and DMA requirements are not yet provided. This does not commit every driver or network protocol to the initial console release.

Agreed implementation split: assembly handles entry/exit, CPU context, and bank mapping; CMOC is used where practical for policy, shell, filesystem, and services. The exact C runtime and reentrancy requirements remain implementation work.

## 2. Process and scheduling model

Agreed requirements:

- Timer-driven preemption and an explicit yield operation.
- Round-robin scheduling, potentially with a few priority levels.
- High-priority execution must not starve the rest of the system.
- Slow device operations must allow unrelated work to continue.
- A 1 kHz tick is a starting candidate, not a fixed requirement.
- The scheduling timer uses the XR88C92 serial counter/timer, routed through IRQ. The UART crystal is confirmed as 3.6864 MHz; the selected timer mode and preload still require target verification. Handling applications masking interrupts is outside the initial scope.
- Short kernel critical updates may defer scheduling; long device operations must allow other processes to run.

Ownership-record proposals and agreed scheduling direction:

- A process owns private bank allocations, logical mappings, open files, named-buffer attachments, and its trap handler.
- A thread owns saved CPU state, its stack, priority, and run/wait state.
- Initially each application/service process has one thread.
- Weighted round-robin gives every runnable priority class a nonzero share. A task being runnable at high priority cannot monopolize all dispatches under this policy.
- Blocking input, IPC, and storage waits sleep the caller instead of busy-spinning.
- The shell launching an application and waiting for its termination, while OS services continue, is agreed. Weighted round-robin and the priority classes below are now agreed; exact ownership/context record layout remains a proposal.

At 3 MHz, a 1 ms interval contains 3,000 cycles in total, including interrupt handling and any context switch. Tick rate and execution quantum are separate settings. Their values require measurement on the target and an audited simulator.

Agreed initial scheduling candidate: a configurable nominal 1 kHz tick and a five-tick (approximately 5 ms) execution quantum. Yield, blocking, and termination can end a quantum earlier; wakeup/preemption rules still need specification. At 3 MHz, 5 ms contains 15,000 cycles including overhead. A timer tick need not dispatch a different process while the current quantum continues; hardware interrupt entry/return costs still occur on each tick.

Agreed priority classes: interactive/service, normal, and background, with weighted round-robin among runnable classes and round-robin within each class. Configurable class weights 4:2:1 are accepted as an initial tuning candidate, not a hard real-time guarantee. The scheduler must skip empty classes, account for early yield/blocking, and preserve a nonzero share for every runnable class. Process capacity affects latency; tick/quantum/weights require target measurements.

The context record must explicitly cover all relevant 6309 registers, stack state, mode state, and process mappings. The exact hardware interrupt frames, extra software saves, and resume paths remain to be specified and tested.

## 3. Memory — agreed and proposed

Agreed:

- The kernel resides in physical RAM bank 0 and is mapped only during kernel execution.
- MLOS owns bank switching, physical allocation, and process mapping decisions.
- Small programs may start with one bank and request additional memory. The loader must also support applications requiring up to three initial banks, giving a maximum 48 KiB application-mapped footprint under the proposed common-RAM layout.
- Applications can request extra physical banks for resources and manage their contents and when they are needed. Every allocation and mapping change is performed by the kernel, which registers ownership and saves the resulting process map.
- A context switch restores the process's latest requested mappings. Extra physical resource banks need not all be mapped simultaneously.
- Allocation failure is an ordinary application-visible error, like malloc failure.
- Ordinary malloc may automatically grow through kernel allocation into eligible uncommitted logical windows; resource windows remain reserved. An individual allocation may cross adjacent eligible resident windows when a contiguous logical free range and sufficient physical backing are available.
- MLOS automatically reclaims completely empty private heap banks rather than retaining them until process exit. Reclamation must respect live objects and pending kernel/device references.
- No swapping, including as a fallback under memory pressure.

Current simulator hardware provides three 16 KiB windows at $0000–$BFFF and an 8 KiB window at $C000–$DFFF. ROM occupies $E000–$FFFF with the I/O overlay at $F400–$F7FF. The old BIOS reservations in the upper RAM window are replaceable; the shorter hardware window remains.

Agreed: permanently map physical bank 1, an OS-owned frame, into $C000–$DFFF. Its visible lower 8 KiB holds common kernel data and entry/exit workspace. Initially reserve the entire 16 KiB physical frame to avoid allocating an alias of kernel data. This consumes 16 KiB of physical RAM even though only 8 KiB is visible through this window.

Agreed: reserve one additional 16 KiB physical discard bank for vacant application windows, shared by the system. It holds no live kernel/application state and is excluded from ordinary allocation. The kernel parks vacant windows there before making their former backing banks reusable. It supplies a safe destination for invalid-window accesses, not an enforced memory fault or zero-filled allocation.

Agreed logical window arrangement; internal placement and sizes remain to be specified:

| CPU range | During application execution | During kernel execution |
| --- | --- | --- |
| $0000–$3FFF | Application's first private bank | Physical kernel bank 0 |
| $4000–$7FFF | Application growth/shared mapping | Preserved or temporarily mapped by kernel |
| $8000–$BFFF | Application growth/shared mapping | Preserved or temporarily mapped by kernel |
| $C000–$DFFF | Fixed OS common RAM | Same fixed OS common RAM |
| $E000–$FFFF | BIOS, entry/exit code, and I/O overlay | Same ROM and I/O overlay |

Common RAM should contain current-process state, entry-depth indicators, mapping records, kernel/emergency stack workspace, scheduler and wait metadata, bounded device buffers, small synchronization objects, and small pipe payloads. Exact capacities and addresses are not settled; size them from the target implementation. Large pipes, logs, caches, and named-buffer payloads should use separately allocated banks.

This agreed arrangement leaves at most 48 KiB of application-mapped RAM, shared by program code, ordinary data, stacks, heap, and shared mappings. Extra physical banks do not automatically expand the space addressable through ordinary C pointers. An explicit banked-resource allocation/map interface is accepted for physical memory beyond that address-space budget; its exact ABI and window restrictions remain to be defined.

Ordinary allocations must remain at stable logical addresses whenever their process executes. Adding a bank must not invalidate existing pointers or move the initial stack. A heap may use multiple free regions; whole-bank ownership and small malloc allocations are different allocator layers.

Proposed bank interface uses process-scoped handles, an explicit target window, and a recorded previous mapping. Mapping checks ownership and rejects reserved kernel/common banks. Windows containing active code, stacks, or ordinary pointer-based heap allocations must not be casually repurposed. A mapped resource pointer is valid only while that resource remains mapped. Future threads sharing a process map require synchronization of window changes.

The resident/resource/uncommitted window-role model is agreed; exact header encoding and transition checks remain to be specified. A window is a logical CPU address range; a bank is the physical RAM mapped into it. The executable's layout distinguishes resident windows (stable code/data/stack/ordinary heap) from explicitly swappable resource windows. Uncommitted windows can be assigned on request, but making them resident prevents later casual resource remapping. A completely empty heap-only resident window can return to the uncommitted role through kernel-managed reclamation; any subsequent role assignment must follow the executable's declared constraints. The purpose is to keep malloc and banked-resource mapping from using the same addresses for incompatible purposes. Programs declare layout requirements, not physical bank numbers; the kernel selects available physical banks and records ownership and mappings.

Illustrative layouts, not mandatory allocations:

| Logical window | Small utility | Game with banked resources | Full 48 KiB resident application |
| --- | --- | --- | --- |
| $0000–$3FFF | Code, data, stack, small heap | Resident code, data, stack | Resident segment 1 |
| $4000–$7FFF | Uncommitted; available for growth | Resident game state and heap | Resident segment 2 |
| $8000–$BFFF | Uncommitted | Swappable resource bank | Resident segment 3 |

The 48 KiB limit includes code, initialized data, BSS, stack, arguments, heap, and any shared mappings; it is not a 48 KiB file payload plus extra execution memory. An application occupying all three resident windows has no spare resource/shared window. Extra physical allocations can still exist, but exposing them requires an explicit safe overlay or copy arrangement. Reject application-requested remapping of a resident window with live contents. Kernel reclamation of a completely empty heap-only bank is allowed under the agreed policy; advanced live-code/data overlays are a later feature. This restriction concerns application-visible mappings, not the kernel's ability to access IPC backing storage. A 48 KiB resident application need not reserve an IPC window: kernel-mediated copies are the agreed initial access mode. A game reserving one full resource window has at most 32 KiB for its other resident contents while that resource window is in use. These layouts do not change the fixed common-RAM window.

Kernel entry must preserve the application's stack and mappings before replacing its first bank. ROM code switches to a common kernel stack before mapping physical bank 0. Exit code runs from ROM while restoring the application map and saved stack before resuming it. Nested entry, interrupt frames, and fault paths require a precise implementation.

When the kernel replaces window 0, an application pointer into that window no longer names the same bytes in the current mapping. Kernel code must translate/map the owning process's memory or use bounded copies. It must not dereference user pointers blindly after switching maps.

The fixed data window is a convenience for software, not hardware-enforced RAM protection. The intended I/O gate blocks unprivileged peripheral/MMU writes, but allows all device reads and their normal side effects. It does not prevent applications from writing already mapped common RAM. The common window remains unprotected memory.

### 3.1. Core-kernel bank budget — agreed direction

Physical bank 0 is one 16 KiB frame. Agreed target: keep core scheduling, process/handle management, allocation/mapping policy, IPC primitives, and trap/termination handling in bank 0. ROM provides the fixed entry/exit and selected BIOS hardware routines. The fixed upper common-RAM window supplies bounded entry/exit workspace and a small always-mapped working set; large metadata, IPC payloads, and caches occupy additional OS-owned banks.

The MLFS service, init, shell, window manager, and applications use their own process banks. Service processes remain part of MLOS but do not all need their code in the core kernel frame. This agreed placement needs a link-map/code-size budget and a target runtime audit; it is not evidence that the core currently fits in 16 KiB.

Agreed: 16 KiB is the initial core-kernel target, and additional kernel code banks may be added later if measurements require them. Any extension still keeps the core in physical bank 0 and requires explicit entry/mapping/return rules; it cannot silently replace live kernel code.

Bootstrap storage access must exist before the filesystem service starts. The boot path must load the kernel and enough initial service code using BIOS/bootloader support, then transfer ordinary file ownership to the running MLOS service. Details are an implementation task.

## 4. BIOS and kernel boundary

Agreed: BIOS is a useful, editable hardware layer for MLOS and bare-metal programs. MLOS owns allocation and mapping policy. The hardware privilege requirement covers all I/O writes; all I/O reads remain permitted by hardware. Direct BIOS access by managed applications must distinguish pure computation, harmless reads, side-effecting reads and write-producing routines; the exact callable helper set remains unresolved.

Agreed: use plain SWI for managed MLOS entry, the register ABI specified in section 10.5 for assembly callers, and CMOC wrappers for C callers. Bare-metal applications can use the full BIOS. Managed MLOS applications route memory-management operations through the kernel. A jump/call to a BIOS address does not itself establish privilege: only the qualified hardware entry sources do. I/O writes require privileged execution; I/O reads do not. Ordinary RAM writes remain available to applications. The window manager retains exclusive graphics ownership through kernel-mediated backend calls, consistent with the user's acceptance of this direction. A software API can enforce ownership of mediated operations, while unrestricted raw device reads remain physically possible. Agreed application convention: ordinary managed applications use OS/service APIs for device reads as well as writes, even though raw reads are hardware-permitted. Drivers/services retain input-draining and acknowledgement ownership; kernel/BIOS executes hardware writes while privileged. The loadable-driver framework is now a requirement; the accepted trusted banked-module arrangement is described in section 11.1. Detailed driver/service boundaries, safe pure BIOS helpers and any diagnostic-helper interface remain to be specified. Bare-metal reset can leave privilege enabled, subject to verified initialization.

The inspected software snapshot has unfinished dispatcher/build/interface work; existing skeleton interfaces do not establish a validated ABI. The next implementation must reconcile BIOS jump-table calling conventions with kernel calls and reproduce the installed ROM.

## 5. I/O protection, MMU gate, and entry sources

Latest agreed hardware intention:

- The user now selects write-only protection for all I/O targets, including peripherals and MMU registers. This supersedes revision 0.30's read-and-write gating.
- All I/O reads are permitted regardless of mode, including their normal device side effects. The user explicitly accepts the possibility of interference such as consuming keyboard data.
- SWI, NMI, or reset establishes privileged I/O-write permission.
- Writing the relock register at $F405 withdraws I/O-write permission before application execution.
- Mapping registers are $F400–$F403; their writes are protected and readback remains permitted.
- An unprivileged I/O write is ignored: it changes neither the target device nor mapping/privilege state and generates no new hardware fault or denial notification.
- Reading $F405 reports retained mode and is permitted while locked without a special exception. Agreed status ABI: bit 7 is 1 when privileged and 0 when locked; bits 0–6 are unspecified, and callers must mask with $80. This is the selected software contract, not a claim that the present circuit implements it.
- Ordinary managed applications use OS/service APIs for device reads despite unrestricted raw hardware reads. This is an application ABI convention, not hardware read isolation.
- GAL logic is to implement this behavior. The user confirms the board provisions the mechanism, but the logic revision is not yet implemented.

Agreed detection method for the pending logic: GAL reads processor BA/BS and the low address byte to identify vector-fetch cycles. Unlock is qualified by the CPU's vector-entry bus state, rather than merely a raw interrupt request. Exact GAL equations, latch phase, selected vector-byte matches, and SWI-variant handling remain to be checked.

Selected software direction: IRQ timer, with fixed ROM code using a dedicated SWI bridge when write privilege or kernel mapping is required. IRQ itself is not an unlock source, but reads are now unrestricted: a locked-mode handler may inspect mode/peripheral status and perform a read-based acknowledgement before the bridge. The selected XR88C92 timer's stop-counter read is such an acknowledgement (section 10.3). Any required device write or mapping update still needs privilege. Exact source-specific sequences remain bounded and must be audited. Applications masking interrupts are outside the initial scope. Hardware trap entry similarly preserves diagnostic context before entering the banked kernel through SWI.

The complete IRQ-to-SWI-to-return sequence remains an implementation task. It must preserve both hardware frames, the original application context, and the kernel-entry reason. An interrupt during kernel execution may be acknowledged and recorded without immediately switching a process in the middle of a critical update; any device write still requires established privilege. Privilege and nesting must be tracked independently of process priority; the final return sequence must preserve the interrupted kernel's permission state and lock only when resuming application execution. NMI remains an exceptional entry source rather than the selected scheduling timer.

Entry/exit must define when the gate is relocked and preserve a valid gate state after nested entry. The critical case is an interrupt occurring between mapping writes or between a map change and its software record update. Relocking inside a nested handler must not silently break the interrupted kernel's remaining mapping writes.

Implementation status: the user reports that the board provisions the MMU gate, but its GAL logic is still to be written/programmed. The user now identifies motherboard/motherboard-stage3 as the target. Inspection confirms U26/U23 GAL22V10 and U27 GAL16V8 signal routing, described in section 5.2. The older firmware files and the schematic's explanatory equations do not establish an implemented state machine. Exact installed part/speed grade, macrocell configuration and fit, clock/phase, reset initialization, and mode-dependent enables remain engineering work.

The simulator currently accepts mapper writes without modeling this gate. Add gate semantics and test ignored unprivileged writes to each I/O target, normal reads in both modes including side effects, mapping writes/readback, intended mode status, every entry/return path, pending interrupts, reset initialization, and nested entry before relying on the mechanism.

### 5.1. Observable gate contract — derived from agreed intent; electrical details pending

The contract below describes the intended two-state behavior. It is not a tested GAL implementation or a claim about the power-up behavior of the present board.

| Event | Intended result |
| --- | --- |
| Qualified plain SWI, NMI, or reset vector fetch | Set PRIVILEGED/UNLOCKED for I/O writes; another qualifying fetch remains idempotently privileged. |
| Qualified write to F400–F403 while UNLOCKED | Update the selected mapping register; remain UNLOCKED. |
| Qualified write to F400–F403 while LOCKED | Do not change the mapping register; remain LOCKED. |
| Qualified peripheral I/O write while UNLOCKED | Permit the addressed write under normal device semantics. |
| Peripheral I/O write while LOCKED | Ignore the write with no device effect, no privilege-state change and no new hardware fault. |
| Peripheral/MMU I/O read in either mode | Permit normal device semantics, including any read side effects. |
| Read F405 in either mode | Bit 7 reports 1=privileged, 0=locked; bits 0–6 are unspecified and callers mask $80. Reliable D7 bus driving remains to be implemented/verified. |
| Qualified privileged write to F405 | Set LOCKED for I/O writes; payload value need not select the state under the current intent. |
| Write F405 while already LOCKED | Ignore; remain LOCKED. |
| IRQ/FIRQ/trap/SWI2/SWI3 vector fetch | Do not unlock under the selected initial plain-SWI/NMI/reset policy. |
| Ordinary reads or unrelated bus operations | Do not unlock or relock the gate merely because a low address byte matches. |

Qualify vector operations with the processor's vector-entry BA/BS state and the selected vector addresses; a raw interrupt request alone is not the unlock condition. Which of a vector's two byte cycles sets the state, the sampling/latch phase, chip-select/read/write qualification, and reset precedence still require the actual wiring/equations and native bus verification. Plain SWI, NMI, and reset vector addresses are recorded in section 10.3. Mapping/relock writes must complete in program order at the selected bus phase.

Boot ROM must have a deterministic reset-to-first-map path before using RAM/stack that depends on an unknown initial mapping. Define gate/MMU power-up behavior and how the reset-vector sequence establishes writable setup; do not assume an extra asynchronous reset input exists on the planned GAL without checking its pins.

The kernel treats a mapping change as a bounded transaction: preserve the interrupted context, execute from ROM where necessary, perform validated map writes and synchronized software-record updates, and relock before ordinary application resume. Existing IRQ/trap SWI bridges and nested-entry requirements remain. A nested path that relocks cannot return to an outer mapping transaction that blindly assumes UNLOCKED; safe-point/nesting behavior must be specified and tested.

The user now confirms an intended mode-status read at F405. Stage 3 has mapping readback circuitry and a PROT_STATE/D7 circuit, but their final equations and software-visible semantics are not validated (section 5.2). Agreed denial behavior is ignored unprivileged writes with no new hardware fault or automatic process termination. Reads execute normally and may mutate device state through read side effects. This gate does not establish access protection for ordinary/common RAM. A syscall that attempts an unauthorized operation can still return a software error; that is distinct from an ignored raw hardware write.

### 5.2. Stage-3 schematic inspection — observed wiring; logic pending

The user identifies the current target as microlind-hw/motherboard/motherboard-stage3. The main-branch address_logic.kicad_sch inspected on 11 October 2026 has title-block revision C1/date 2025-08-15; its blob hash is recorded below. These are source-level wiring observations, not confirmation of assembled-board continuity or programmed behavior.

| Circuit | Observed schematic connections | Design implication |
| --- | --- | --- |
| U26, GAL22V10 address logic | A0–A9 on pins 1–10; /IO_EN on 11; /WR on 13; ENTER_PROT output 17; EXIT_PROT output 18; /RD at 19; PROT_STATE output 21; /MEM_EN output 23. | Address and bus strobes provide entry/relock decode. No PROT_MODE connection is shown at U26. Pin 19 must be configured for its wired input role. |
| U27, GAL16V8 signal logic | E on 1, Q on 2, processor pre_R/W on 3, BA on 4, BS on 5, /MEM_EN on 6, EXIT_PROT on 7, ENTER_PROT on 8; PROT_MODE output 14; /MEM_WR output 15; /MEM_RD output 16. | Vector-entry qualification and retained mode belong here. /MEM_WR is the direct map-register write-enable path; mode-qualified enforcement must reach this signal. E/Q are wired, but the actual latch/sampling implementation remains unspecified. |
| U23, GAL22V10 memory logic | PROT_MODE at pin 15; /MAP_EN at 14; /MEM_RD at 13; /MAP_RD output 18; /IO_EN output 19. Other outputs select ROM and RAM regions. | Privilege state also reaches the memory decoder. Configure pin 15 as the wired input. The latest scope is all I/O writes with unrestricted reads. U23 has no general R/W or /RD input in the inspected wiring; /MEM_RD is specific to map readback. Gating /IO_EN on retained privilege alone would block both reads and writes. Determine a read/write-sensitive enforcement path and audit every downstream enable. Ordinary RAM protection is not established. |
| U24/U25, 74LS670 map storage | Both /Ew inputs, pin 12, connect to U27 /MEM_WR. A0/A1 select the written entry. Both /Er inputs connect to /MAP_RD. | Suppressing the qualified /MEM_WR pulse prevents an actual mapping-register update. Changing an unrelated enable is insufficient unless that change also suppresses this pulse. |
| U28, 74HC245 | AM14–AM21 connect to its B side; D0–D7 to its A side; direction is tied for map-to-data readback; /MEM_RD controls enable. U23 selects the addressed map entry during a map read. | Stage 3 provisions mapping readback. Final bus timing, map selection and byte values must be verified before treating readback as a kernel ABI or gate test oracle. |
| PROT_STATE circuit | U26 pin 21 drives R21 (33 kOhm), then Q1 (BC337) base; Q1 collector is D7 and emitter is ground. | This provisions pulling D7 low during a selected read. It is not a complete, verified mode-status register. |

The schematic notes contain several gaps relative to the agreed gate contract:

1. ENTER_PROT's written expression matches low address nibbles A and E. Those correspond to the first bytes of plain SWI and reset vectors; NMI's first-byte nibble C is missing. The note does not constrain A4–A7. The implementation must select the agreed vector-byte addresses and qualify them with the actual vector-entry state/timing.
2. The latch note sets PROT_MODE using !BA, BS and ENTER_PROT, and clears it with EXIT_PROT. It also mentions /RESET, but no reset net is wired to U27 or into the address-logic sheet. Do not compile that term as if a reset input exists. The agreed reset-vector unlock can initialize the state through ENTER_PROT; deterministic power-up/reset behavior and the first map write still need validation.
3. The written /MEM_WR expression combines map decode and a write strobe without a PROT_MODE term. It therefore does not, by itself, express locked-state suppression. The pending implementation must gate the actual U24/U25 write-enable path; verify U27 feedback/macrocell mode and fit before assuming a particular latch or equation is supported.
4. EXIT_PROT's note decodes a write to F405, consistent with the relock address. Its timing must clear the permission state without accidentally generating a map-write pulse.
5. PROT_STATE's written expression decodes a read at F405 but contains no retained privilege state. U26 has no direct PROT_MODE input. The shown transistor can sink D7, but a defined status bit, other data bits and bus-driver behavior are not established. The user confirms that mode readback was intended. Implement and validate the agreed bit-7 F405 read ABI; the missing retained-state path and reliable high/low data drive remain engineering work.

Derived naming recommendation, not a new agreed hardware requirement: define PROT_MODE=1 as privileged/I/O-write-enabled and PROT_MODE=0 as application/I/O-write-locked, since the notes SET on entry and RESET on exit. Use PRIVILEGED/APPLICATION in software to avoid confusing privilege being enabled with protection being enforced. D7 readback polarity is now agreed: 1=privileged, 0=locked. Internal signal polarity may differ if required by the hardware; expose the agreed software bit consistently.

The latest user decision is protection of all I/O writes with unrestricted reads. U23's mode routing is a provision for enforcement; its exact implementation must preserve reads and normal RAM writes. It does not add ordinary/common-RAM isolation or change the agreed memory map by itself.

### 5.3. I/O-write enforcement — agreed scope and denial; detailed mechanism pending

The intended gate covers CPU-originated writes to CF, serial timer/UART channels, PS/2, parallel, graphics, sound, interrupt-controller registers, expansion I/O, and MMU registers within the decoded I/O space. Reads remain allowed in both modes, including consuming FIFO data, acknowledging interrupt flags or advancing device pointers. This tradeoff is explicitly accepted; hardware write restriction cannot guarantee exclusive access against raw side-effecting reads.

Final equations must suppress every applicable I/O write path. Do not assume gating /WR alone covers devices that use E plus R/W and chip select rather than a separate write strobe. Do not gate /WR globally in application mode if that also blocks ordinary RAM writes: the inspected CPU/memory wiring uses it for SRAM write enable. Likewise, gating /IO_EN solely by retained mode blocks reads and violates the selected policy.

The inspected U23 decoder receives PROT_MODE but no general R/W or /RD; the inspected U26 receives read/write strobes but no direct retained-mode signal. U27 has mode generation and strobes but no general I/O-region decode input. These are engineering constraints, not proof that the policy is impossible. Derive and fit a cycle-qualified implementation, potentially requiring changed signal roles or routing; do not claim equations alone on the current pin assignments have already solved it. Retained privilege state must remain distinguishable from transient cycle-access permission for nesting/status readback.

Preserve the existing I/O decode region and normal RAM access under denied writes. Audit device-select/strobe overlap, bus driving, inactive levels, write pulse suppression and read timing. External bus-master behavior remains a separate audit. Hardware write restriction does not validate kernel syscall arguments, constrain arbitrary application instruction execution, or protect mapped common RAM.

Agreed graphics direction: the window manager retains exclusive graphics ownership through kernel-mediated backend calls, with actual hardware writes in kernel/BIOS execution. Recovery may revoke ownership and reclaim the backend as already agreed. Ownership is a software driver/API rule; raw graphics reads remain hardware-permitted, and the global privilege latch cannot identify which process owns graphics.

Agreed application convention: ordinary managed applications use OS/service APIs for device reads, including reads that consume data or acknowledge events. Hardware still permits raw reads; an application that bypasses the convention can interfere with a device and no new read fault is generated. Driver/service ownership of input consumption, acknowledgement and graphics operations is a correctness rule, independent of multi-user authorization. Trusted banked hardware-driver modules are now accepted; the filesystem service's bounded CF interface and the precise division between hardware modules and protocol services remain to be finalized. Pure BIOS helpers and any diagnostic-helper interface remain unresolved; no general direct-read whitelist for ordinary applications is selected.

Implement bounded graphics/storage operations and leave no device transaction or mapping update half complete at a blocking/yield boundary. Emergency reporting needs privilege for UART/graphics writes. The SWI/NMI/reset unlock-source set remains unchanged. The timer IRQ may inspect and read-acknowledge the UART before SWI when safe; write acknowledgements/configuration and mapping still require privilege. A nested interrupt must not cause an inner exit to withdraw permission from an interrupted outer driver transaction.

Mode status is readable in either mode under the unrestricted-read policy. Agreed ABI: ($F405 & $80) != 0 means privileged; zero means locked. Bits 0–6 are unspecified and must be ignored, so never compare the whole byte with $00 or $80. Its electrical implementation remains pending: U26 lacks a direct retained-mode input and Q1 only pulls D7 low. Supply a reliable D7 level for both states, prevent contention with other bus drivers and meet read timing; floating data is not a valid high status bit. Validate the same bit-7 result while lower bits vary.

Reading status after a qualified SWI/NMI entry reports the newly enabled state and cannot reveal the overwritten pre-entry state. A ROM IRQ bridge may read/capture the state before its own SWI. Internal SWI entry metadata, NMI policy and nested-return handling must be specified separately; the readable status bit alone cannot solve those cases. The user has not selected a use for NMI. Keep it reserved rather than requiring a debugger, scheduler or recovery feature. Proposed first-release handling is described in section 5.4; it remains a working proposal, not an accepted requirement, and does not change process-trap or GUI-recovery policy.

### 5.4. NMI — reserved; proposed minimal first-release handling

The user has not yet identified a purpose for NMI and does not know which behavior to select. No resumable NMI/debugger requirement is introduced. Proposed working default: leave NMI unused for normal MLOS operation, retain a valid ROM vector/handler and the already agreed NMI privilege-entry decode, and handle an unexpected NMI as a system diagnostic stop pending manual reset.

Observed stage-3 source wiring, reconfirmed on 11 October 2026: U3 pin 2 (/NMI) connects to R2, a 10 kOhm pull-up to VCC, in cpu_men.kicad_sch. The root schematic's CPU_MEM /NMI sheet pin is marked no-connect. There is no routed NMI source through that top-level pin in this inspected source revision; this is not a measurement of an assembled board or a claim about external modifications.

Rationale: the Motorola 6809-family manual describes NMI as an edge-triggered, non-maskable interrupt. It can interrupt code whose IRQ/FIRQ masks protect a kernel update. Together with the planned GAL's NMI entry that enables I/O writes before the handler reads status, a resumable NMI requires its own context, map/stack and previous-privilege restoration protocol. That complexity is unnecessary for the initial console/GUI goals. Native HD6309 frame/timing details remain subject to the existing target audit.

Proposed unexpected-NMI path:

- Enter fixed ROM; avoid ordinary OS services, dynamic allocation, IPC waits and scheduler dispatch.
- If CPU entry completed and the reserved emergency workspace is usable, preserve a small best-effort diagnostic record: reason, saved PC/S, available register context and mappings. Establish a verified emergency stack without relying on the interrupted process to be healthy.
- Attempt bounded output on the emergency serial/log channel; never wait indefinitely for UART readiness. Do not use CF or perform filesystem flushing/repair from this handler.
- Enter a non-resuming stop path requiring reset. Do not RTI into the interrupted process or kernel transaction, and do not attempt ordinary process/resource cleanup from an unknown kernel state.
- Specify repeated-NMI handling so diagnostics do not recurse indefinitely; NMI itself cannot be suppressed by the normal interrupt mask bits. Detailed guard/stack behavior is an implementation task.

The CPU's interrupt-entry stacking occurs before ROM software can switch to an emergency stack. Consequently, this minimal path cannot promise diagnostics after an invalid interrupted S/mapping or corrupted common RAM. Treat register collection as best effort; implement the existing emergency-halt direction without depending on a successful full dump.

The selected scheduling timer stays on IRQ, and application instruction/math traps retain their agreed log-and-terminate behavior. Future debug-break/watchdog uses can be designed when a real NMI source and desired recovery semantics exist; they are not first-release deliverables. Adoption of this reserved/diagnostic-stop proposal remains open.

## 6. IPC and lifecycle

Agreed:

- IPC transport uses named shared-memory buffers created/attached through the kernel.
- MLOS maintains all IPC resources: names, backing storage, endpoint registration, queue state, waiters, notifications, and reclamation. Applications hold handles/attachments; they do not maintain the resource lifecycle. Requested creation by a process does not transfer lifecycle management out of the OS.
- Shared rings plus kernel wait/signal operations are accepted.
- Initial access uses copied, handle-based kernel read/write operations. Applications do not directly map IPC payload banks. Direct mapping is an optional later extension.
- Channel mode is selected at creation: byte stream or complete messages. Terminal traffic uses streams; GUI commands/events use message channels.
- Message sends are all-or-nothing: publish one complete message when it fits, otherwise wait or return an error according to the operation's blocking mode. Receivers must never see a partially committed message.
- IPC reads/writes block by default, with an explicit nonblocking option. Blocking sleeps the caller and allows other processes to run; it must not busy-spin or hold the kernel's mapping/critical-update state across the wait.
- Capacity is chosen at channel initialization and stays fixed for its lifetime. Default capacity is 512 bytes. Requests may range from one byte to what available memory permits; no power-of-two, filesystem-block alignment, or arbitrary small per-channel maximum is required. Invalid/unrepresentable sizes and allocation failures return explicit errors.
- No creator authorization or user-account permissions are required for IPC attachment. Any process can attach by name to an available endpoint through MLOS. The kernel still enforces one producer and one consumer, endpoint direction, valid handles, and lifecycle state. This is correctness checking, not an access-grant mechanism.
- Successive mouse motion can be combined while preserving button transitions.
- A dying process releases its resources and connected processes receive notification.
- After notification, registered peers have a chance to drain buffered data before it is discarded.
- Initially each buffer connects exactly one producer and one consumer.
- Following producer closure/death, retain unread data until the consumer drains it or exits. There is no timeout initially.

Implementation details and proposals (agreed access mode noted):

- Kernel-managed backing storage may be shared by endpoints without being permanently mapped into either application's resident address space. Large payload storage occupies OS-allocated banks.
- Agreed initial access mode: handle-based ipc_read/ipc_write calls copy between application memory and the named OS buffer. Kernel code accesses backing banks temporarily while preserving process mappings. This permits IPC for a fully resident 48 KiB application without a dedicated application resource window. Chunked copying must keep kernel stacks, common RAM, and scheduling latency bounded; banked user-pointer handling still needs implementation.
- Deferred optional direct mapping avoids payload copies but consumes an application-visible window while mapped. The OS still owns allocations, endpoint validity checks, synchronization, and teardown; creator authorization is not part of the initial design. A reserved window is a requirement of that direct access mode, not of OS-managed IPC in general.
- Shared structures use relative offsets rather than cross-process pointers.
- Publish/consume state has a specified atomicity and wakeup protocol so a consumer cannot miss a signal between checking the buffer and sleeping.
- A process death produces a peer-closed/peer-died event and wakes waiters.
- Endpoint closure, buffered-data handling, and payload reclamation are separate lifecycle operations.

Agreed capacity accounting: the requested capacity is usable queued payload bytes; OS descriptors and message-length metadata are additional storage. This makes a one-byte stream usable and allows a message channel to hold a one-byte message rather than consuming its entire advertised capacity with a header. Message metadata must have bounded allocation and zero-length-message semantics must be defined. Internal allocation may round up storage without changing the advertised capacity. Total memory admission includes payload, metadata, and allocator overhead.

The 512-byte default is convenient for initial filesystem transfers but does not couple IPC capacity or alignment to MLFS/CF block sizes. Larger queues may span OS backing banks without increasing an application's mapped footprint. Capacity/count/offset fields must represent such queues; individual copied operations remain bounded by valid application buffers and bounded kernel work. Exact widths and record representation remain implementation decisions.

Agreed multi-channel wait: a process can sleep until any listed IPC handle becomes ready, with an optional deadline. This lets a service dispatch its many one-way client channels without busy polling or blocking on one idle client. Readiness checks and sleeping must avoid lost wakeups. A wait deadline does not change the agreed no-timeout retention of draining payloads.

Agreed message receive behavior: an undersized destination buffer reports the required length and leaves the message queued. Remaining API proposals: stream operations report actual byte counts and may complete partially; message records have an explicit length; oversized messages fail immediately rather than waiting for impossible capacity. Message atomicity concerns visibility/commit, not masking interrupts throughout the payload copy. Reserve/copy/commit must support bounded kernel work and correct process-death cleanup.

A single-producer/single-consumer channel carries data in one direction. Bidirectional GUI communication therefore needs separate command and event channels for each client; named-service rendezvous is agreed in section 6.2, with detailed endpoint naming and acceptance semantics still to be specified. There are no access grants; occupied producer/consumer slots cannot be claimed by a second process. A service with many clients needs a way to wait on multiple channels and dispatch them fairly.

Proposed lifecycle: OPEN -> DRAINING -> CLOSED. Producer closure/death stops new writes, signals the consumer, wakes waiters, and releases the producer's attachment. Existing unread data remains available during draining. Once drained, or if the consumer exits, mappings/attachments are withdrawn before payload banks are returned for reuse. Consumer death has no surviving reader to drain data: notify the producer, reject subsequent writes, and reclaim after withdrawing attachments. A stale handle must not silently refer to a newly allocated buffer.

The chosen no-timeout policy allows a live consumer to retain an unread draining buffer indefinitely. That is an accepted retention rule, not a promise of eventual reclamation. Unresolved: the exact EOF/peer-died result, how consumption and drain completion are recorded, and whether empty attached endpoints survive payload reclamation. Explicit close should release an endpoint; detailed channel ownership rules still need specification.

### 6.1. CF-backed bulk transfer — lifetime and exact length agreed; detailed API pending

Agreed: CF files carry large application datasets while an ordinary RAM IPC message carries the ready notification and a transfer identifier. All IPC, including CF-backed transfers, is temporary and valid only during the running OS session. Producers declare the dataset size before writing; MLOS preallocates its backing storage. This is an explicit application-requested transfer facility. It does not silently convert RAM allocation failure into disk use or swap process memory.

Use RAM streams when producer and consumer can process data incrementally: a large total dataset alone does not require a large queue or disk storage. CF handoff is useful when the complete dataset must be retained, reread, or made available independently of simultaneous producer/consumer progress. It adds storage I/O and disk-space failure handling; bulk CF work must be scheduled in bounded chunks through the filesystem service.

Recommended initial protocol:

1. MLOS creates a unique unpublished temporary payload and records its transfer lifecycle. Producer writes in small chunks under an exclusive write handle.
2. Producer requests finalization. MLOS checks the completed byte count, completes pending filesystem writes, closes the writer, and establishes a read lease/immutable transfer state before making the transfer publishable. File rename atomicity is not assumed.
3. A small ordinary IPC message publishes the transfer identifier and byte length. The queue-held reference retains the backing file until delivery, including if the producer exits.
4. Consumer receives the reference and reads the immutable payload in bounded chunks through MLFS. It need not load the entire file into its resident address space.
5. Consumer explicitly releases the transfer or exits. MLOS closes remaining leases and deletes temporary storage once no queued or endpoint references remain. Read-open files cannot be deleted early under the agreed MLFS rules.

MLOS owns the transfer registry, temporary storage, read leases, queued references, error cleanup, and deletion. An unpublished transfer can be reclaimed on producer death; a published transfer is retained for the consumer. Sending must acquire a queue-held reference as part of message commit; failed enqueue must not leak one. The managed temporary transfer facility and predeclared size are agreed. Precise handles, state transitions, and reference accounting are implementation proposals, not existing implementation.

This completed-file handoff matches exclusive writing and read-only sharing. Simultaneous append/read through one file conflicts with the initial file-open policy and is deferred. Retaining a queued transfer indefinitely when a live consumer does not drain it follows the existing no-timeout policy, now consuming CF space.

Agreed lifetime: no IPC channel, queued message, transfer ID, or CF transfer is restored after reset/reboot. CF payload files may physically remain after an interrupted session; that does not make them valid IPC. MLOS must reclaim old temporary transfer storage before admitting new IPC on the affected volume. Proposed implementation: a clearly identifiable OS-owned spool area with bounded boot cleanup, after safe filesystem mounting/recovery. Normal shutdown also reclaims transfers. Ordinary user files must not be included. This lifetime rule removes the need for durable message delivery across reboot; safe filesystem updates and mount recovery remain requirements.

Implementation constraints found in the current default-branch MLFS write routine: writes use the first allocated extent, clamp length to its allocated capacity, and do not grow it automatically. Bulk creation requires a declared length and preallocates storage, checking every short write. Fragmentation, extent limits, and target-safe wide file offsets must be audited; files larger than application RAM still use small transfer buffers. The public MLFS I/O abstraction exposes read/write operations but no explicit flush callback, so persistence semantics need additional target work.

Remaining mechanisms: spool identification/cleanup, queue-held references, finalization and error results, and target-safe file offsets. Agreed initial write behavior is sequential: the declared length is exact, finalization requires that many successfully written bytes, and excess writes fail rather than extending storage. Incomplete finalization fails without publishing the transfer; exact retry/error states remain to be specified. Sequential writes avoid publishing unwritten holes; zero-length semantics remain unresolved. Growth beyond a CF transfer's declared capacity is not supported; transfer fan-out remains deferred. Initial IPC remains one producer and one consumer.

### 6.2. Named service connections — agreed direction; detailed API pending

Agreed: a kernel-managed named service registry. A service registers a listener, and clients connect by its service name. Each accepted connection has its own client-to-service and service-to-client channels, preserving one producer and one consumer on each channel. Existing explicitly created named channels remain supported. Service names and the raw channel namespace need unambiguous separation.

The kernel maintains a bounded pending-connection queue and notifies the listener of connection readiness. This queue contains kernel-controlled connection records; it is not a shared multi-producer application payload channel. A service accepts connections and uses multi-channel waiting to dispatch its private client channels fairly. Channel modes and capacities are declared when establishing a connection, using the existing 512-byte payload default per channel and resource-based admission. Connection metadata and both queues count toward the memory budget.

Recommend immediate failure for a missing listener, BUSY for an occupied service name, and explicit errors when memory or pending-connection capacity is exhausted. A blocking connect may wait for acceptance, with an explicit nonblocking form; precise pending-result/cancellation conventions remain to be specified. Partial creation must roll back safely, including client death before acceptance. Admission and channel attachment must be atomic with respect to service exit.

On service exit, remove its registration and close its owned endpoints; established peers receive the existing closure/death notification and drain retained incoming data under the agreed lifetime policy. Pending connection requests fail. Listener and connection identities must distinguish service instances so restarting a name does not silently reconnect old handles. There is no automatic reconnection initially. Registration ownership enforces lifecycle correctness, without introducing user-account authorization.

The named listener/private channel-pair design, resource/missing-service errors, service-death notification, and no automatic reconnection are adopted. Detailed acceptance, cancellation, readiness, and namespace encoding remain implementation work; the blocking-connect conventions above are API proposals.

## 7. MLFS and file ownership — agreed

MLFS is mandatory and part of MLOS. The source exposes partition creation/mounting and allows up to 16 partition entries. Internal filesystem allocation and directory mutations need serialization under preemption. It currently exposes pathname/offset reads and writes; MLOS must add open-file descriptors and ownership rules.

Agreed sharing policy:

- Multiple processes may read-open the same file.
- While read handles exist, manipulation of the opened MLFS file is prohibited. Virtual status views such as planned /proc files require separate read semantics; reading them must not freeze the kernel state they report.
- A write-open is exclusive.
- Conflicting opens initially fail immediately with BUSY. Writers cannot acquire a file with active readers, and readers cannot acquire a file with an active writer.
- Process termination closes its handles and releases corresponding ownership.

Agreed: one filesystem service can handle several drives, holding their exclusive raw-device claims and serving many clients. Keep device/volume state and pending work distinct beneath the shared mounted namespace. Proposed implementation direction: serialize conflicting metadata updates per volume and short global namespace updates, while asynchronous storage state machines permit progress on other drives and processes during hardware waits. Do not hold a service-global lock across a slow device operation. Existing MLFS reentrancy, target contexts and continuation/buffer behavior need audit/porting; this is not a claim that the current synchronous library implements multi-drive asynchronous progress.

The target port must reconcile host-oriented types, temporary full-block allocations, target stack/heap limits, and supported filesystem block sizes. Preserve the on-disk format deliberately; target-specific buffering restrictions must be documented separately from format compatibility.

Agreed target support: start with 512-byte filesystem blocks; support up to 4 KiB is a desired extension. Here block size means MLFS filesystem block size, separate from the CF device transfer unit. The first release must explicitly reject unsupported filesystem block sizes rather than misinterpret them. Size the service's cache, temporary allocations, and stack for the chosen target limits; a 4 KiB block should not require an equally large stack object.

### 7.1. Unix-style namespace and current directories — agreed direction

The current public MLFS API exposes directory create/delete/read operations and pathname-based file operations; the README describes subdirectory navigation. Target behavior and locking still need implementation/validation; no target directory test has been executed.

Agreed: one Unix-style path tree and mountable filesystem backends. The initial recommended arrangement places the boot/system partition at / and other mounted partitions at paths such as /mnt/cfN. Exact mount names/configuration and directory layouts remain implementation choices. Virtual filesystems are part of the planned direction, including /proc for process status.

MLOS needs a small filesystem dispatch layer that selects the mounted backend and resolves its partition-local or virtual path. Ordinary descriptor operations should retain the same caller-facing conventions across MLFS and virtual files. A /dev device backend for expansion drivers is now proposed in section 11.1; block-device geometry/sector operations and class-specific controls must not be reduced to ordinary file semantics. Backend operations, route tables, mount identities, mount-root parent traversal, path validation, descriptor lifetime, and reserved OS spool handling still need specification and core-kernel budget validation.

Agreed process context: each process owns its current working directory, inherited when a child is launched. Shell cd changes that shell's directory and the starting directory of subsequently launched children. Other shells and the file browser retain their own navigation context. Absolute paths resolve through the shared namespace; relative paths resolve through the caller's directory. If that cwd's volume becomes unavailable or its generation is replaced, the process stays alive but new relative-path operations fail; an explicit chdir to a valid absolute path establishes a fresh cwd. Recovery never silently resets or rebinds the old cwd (section 11.6). Release the process's directory reference during normal exit and termination cleanup. The BUSY rules in section 7.2 are agreed; directory identity, reference accounting, and synchronized implementation remain to be specified.

### 7.2. Virtual status views and mount/directory lifetime — agreed direction

1. **Read-only /proc initially.** Agreed: /proc/<pid>/status, /proc/meminfo, and /proc/mounts as the first views. Status can expose process identity/name, scheduler state and priority class, owned-bank count, and logical mappings. Capture a small fixed status record when opened; successive reads use that snapshot rather than mixing state from different moments. Bind open handles to a specific process instance/generation; a reused PID must not redirect an existing handle to a different process. A captured status snapshot can remain readable after its subject exits and must not retain the subject's application banks. A later open for a vanished subject returns not-found. Enumeration/read race behavior for large process lists still needs definition.

   The planned virtual backend generates data from OS records without CF storage. Agreed: keep status capture and surviving diagnostic access independent of MLFS service availability; an MLFS service failure disables its disk operations while virtual status inspection remains usable by surviving programs. Emergency kernel-fault reporting still uses the separately agreed minimal serial path. Keep record capture and formatting bounded, and validate placement against the 16 KiB core target.

2. **BUSY for directory changes affecting active references initially.** Agreed: refuse rename or deletion when the directory or a descendant is a process's current directory, or when the change would invalidate a live file/directory reference. This avoids stale stored paths/identities in the first implementation. Creating or changing unrelated entries remains subject to ordinary file ownership and filesystem rules; holding a current directory is not a blanket prohibition on its contents. Define safe directory identities and ancestor/reference accounting before considering rename-through-live-references later.

3. **BUSY on unmount while a backend is in use.** Agreed: refuse unmount when the mount has current-directory references, open descriptors, active I/O, or queued/published temporary CF-transfer references. Initial unmount has no forced variant. Resolve or release these references first, using existing process/IPC cleanup rules; the no-timeout transfer retention policy still applies. Unmount is a synchronized admission/lifetime operation and must not race with a new open or request.

These /proc view, snapshot, directory-change, and unmount policies are agreed. Precise data structures, public operations, bounded formatting, and synchronized reference/lifetime handling remain implementation work.


### 7.3. Standard descriptor I/O and ordinary file growth — agreed; implementation pending

Agreed: a process-local descriptor interface with standard slots 0 (input), 1 (output), and 2 (error output). Read/write/close dispatch to byte-oriented providers such as regular files, terminal connections, and RAM byte streams. This lets the same shell/application run through serial or graphical presentation and supports redirection without hardware-specific application I/O. Complete-message IPC retains dedicated message operations so byte-stream reads do not erase message boundaries. Exact descriptor/handle widths, seek operations, partial-count/error conventions, CMOC buffering, and runtime integration remain to be specified.

Agreed ordinary-file behavior: allocate more filesystem blocks as successful writes outgrow the file's reserved capacity, subject to disk space, format/extent limits, and other resource failures. The current mlfs_pwrite_file uses only de.extents[0] and caps writes at that extent's capacity; implementing growth therefore requires MLFS changes and target-safe offset/count handling. Extent traversal, growth metadata ordering, and accurate short-write/error reporting still need specification. Scheduled storage progress must retain the existing bounded/preemptible I/O requirement.

Ordinary-file growth does not change the agreed predeclared capacity and preallocation of temporary CF IPC transfers. Those transfers still reject writes beyond their declared bounds and follow their separate publication/lifetime rules.

The descriptor interface and ordinary-file growth are adopted design requirements; their implementation and precise ABI remain pending.


### 7.4. Interrupted-write boot policy — agreed; recovery mechanisms pending

Agreed: a conservative first-release policy for MLFS after an unclean stop or an interrupted metadata update: validate the volume before enabling writes. If clean status or consistency cannot be established, permit read-only diagnostic access only when mount checks establish that reads are safe; otherwise leave the volume unmounted and report the condition through available diagnostics. Require explicit repair/reinitialization before enabling writes to a suspect volume.

An unclean stop includes power loss/reset during allocation, directory/file-size changes, truncate, or other metadata operations. A clean/dirty indication can help only when its update ordering and persistence are implemented and verified; it does not prove volume integrity or atomic CF writes. Marker representation, compatibility/versioning, metadata checks, target persistence operations, and a repair tool remain implementation work. Do not assume the current source already provides these mechanisms.

This policy does not promise power-loss atomic ordinary-file updates or automatic crash recovery. Unpublished/old temporary IPC spool storage is still reclaimed only after safe mounting/recovery, before admitting new transfers on that volume. Recovery must not delete ordinary files or mutate suspect metadata without the selected repair policy. A corrupted boot image or failure before the kernel loads also requires a separately verified ROM/bootstrap recovery path; virtual /proc diagnostics are available only once the kernel and a surviving diagnostic program can run.

The validate/read-only-or-offline/manual-repair first-release policy is adopted. Stronger automatic recovery remains a later design choice.

## 8. Graphics, terminal, and recovery

Agreed:

- The window manager owns exclusive graphics access through the kernel-mediated backend direction accepted by the user, preserving window management as a separate process. Hardware writes require privilege; raw reads remain hardware-permitted and cannot be made exclusive by this gate.
- Initial GUI is monochrome.
- Current target: MOS 8568, 64 KiB private VRAM, 640×400 interlaced.
- Future backend: Yamaha V9958; application interfaces should be hardware agnostic.
- Applications use redraw events; moving windows may use outline-only dragging.
- GUI terminals run the same MLOS shell as console boot.
- On window-manager failure, all descendants of the GUI session are terminated and their resources released. Independent console/background processes and core OS services are outside that cleanup scope.
- Session membership must persist for descendants even if immediate parent processes exit; tracking only the current parent chain is insufficient.
- Recovery first attempts a graphics console, then a serial console if graphics fails.
- An output-only serial log console must be available at any time.
- An interactive console is also supported, on a separate UART channel from output-only logs. Agreed configurable default: UART A for the interactive console and UART B for output-only logging. Board wiring, baud rates, and BIOS/runtime handoff still require verification.
- Input initially uses a Swedish keyboard layout and Latin-1 (ISO-8859-1); UTF-8 is deferred.
- Filenames are case-sensitive, including Å/å, Ä/ä, and Ö/ö. Distinct case variants name distinct files.

Proposed interfaces:

- Applications use a window/event/drawing protocol, not chip register addresses.
- The window manager uses a monochrome graphics interface with capability queries and backend-specific implementations.
- Initial primitives include clipped rectangle fill, monochrome bitmap transfer, and text/glyph drawing. Hardware acceleration is optional behind the interface.
- A virtual terminal separates shell input/output from physical serial and graphical presentation.
- Kernel/recovery services can revoke window-manager device ownership and reclaim the graphics backend for console recovery.
- Logging uses a bounded buffer with a defined overflow policy, avoiding an unbounded wait on serial output.

A packed one-bit 640×400 bitmap occupies 32,000 bytes. Two occupy 64,000 bytes, leaving 1,536 bytes of 64 KiB VRAM. Fonts, scratch space, attributes, and backing surfaces need explicit budgets if double buffering is selected.

Simulator inspection confirms 64 KiB private VDC RAM, but the current compositor is character-mode rendering. Bitmap/interlace rendering and timing fidelity are separate implementation milestones; GUI rendering performance cannot be established from the current always-ready model alone.

Unresolved: precise redraw/clipping, detailed driver placement/interface, electrical mode-status implementation and nested entry handling. The bit-7 status ABI and ordinary application read-API convention are agreed. UART A interactive/B logs are already agreed as configurable defaults. Recovery must close/revoke dying GUI endpoints while retaining enough console/logging and graphics-driver state to establish the fallback console.

Agreed character encoding: Latin-1 (ISO-8859-1). Filename lookup uses exact byte matching with no case folding. Directory sorting/collation is a separate policy, not determined by case-sensitive lookup. Keyboard translation, fonts, shell, filenames, and terminal behavior must agree on it. Swedish key positions and character encoding are separate decisions; PS/2 scan-code translation must also preserve modifiers and non-text keys for applications. Existing font data must be checked/remapped rather than assumed compatible.

### 8.1. Foreground terminal input — agreed; detailed discipline pending

Agreed: one foreground input owner per logical terminal. The shell owns input while accepting commands. Starting a foreground command transfers input ownership to that child as part of launch, before it becomes runnable; the waiting shell does not consume input. Command exit or trap termination restores ownership to the live waiting shell. Independent terminals have independent owners. This is the initial single-process foreground model; process groups and full job control are deferred.

Terminal association inheritance refers to a shared terminal provider, with separate process channels as agreed in section 10.8. Output from background processes remains possible through their own output channels. Agreed: a clear NOT_FOREGROUND error for an attempted background terminal read, rather than an indefinite read wait. The current Ctrl-C policy continues to request kernel-managed termination of the foreground command.

Unread terminal typeahead should remain with the terminal until consumed by its current owner, so changing foreground ownership does not strand input in a waiting parent's channel. Delivery, ownership transfer, and wakeup must be synchronized. Do not pre-deliver unread input into the shell's private queue before handing control to a child. Library buffering, canonical/raw input modes, line editing, and return to shell input settings require further specification; they cannot silently override terminal ownership.

Foreground ownership, background-read errors, and retention of unread terminal input across ownership changes are adopted. Exact synchronized delivery and terminal discipline remain implementation work.

### 8.2. Serial log overflow — agreed; implementation pending

Agreed: a bounded kernel log ring with nonblocking publication. If it fills, discard the oldest complete queued records to retain recent diagnostics and count discarded records. Report the loss when output resumes. Oversized records need a bounded truncation/rejection rule, and serialization must avoid a long interrupt-masked copy or a wait for UART progress.

The output-only log UART is drained asynchronously. A slow or disconnected log receiver must not stop application scheduling or normal kernel operation. Emergency reporting after a core fault remains a separate bounded path. Exact ring size, record representation, UART channel assignment, and loss-marker formatting remain unresolved.

The nonblocking bounded ring, oldest-complete-record discard policy, and dropped-record accounting are adopted. Exact sizes and serialization remain implementation work.

### 8.3. Line and raw input modes — agreed direction; detailed discipline pending

Agreed: two input modes on a logical terminal, controlled by its foreground owner. Default line mode provides echo, backspace editing, and Enter-delimited input through a bounded terminal line buffer; callers may read a completed line in smaller pieces without losing the remainder. Recommend EOF input on Ctrl-D when the edited line is empty, with exact handling of a nonempty edited line still to be specified.

Raw mode returns available input bytes without line editing or automatic echo. Interactive applications such as the file browser and a console game can request it explicitly. The already agreed Ctrl-C foreground termination policy remains active initially in both modes; overriding that policy requires a later explicit design decision. Raw terminal input does not replace the separate GUI keyboard/window event protocol. Latin-1 text, non-text key representation, serial escape handling, and exact raw read/wait conventions remain to be specified.

Input settings belong to the terminal foreground session, with a saved previous setting for the waiting shell. On command exit, termination, or launch rollback, restore that shell's input settings as well as ownership so a failed raw-mode application does not leave the shell unusable. Buffer capacities, maximum edited-line length, overflow behavior, and CMOC buffering need explicit bounds.

Line/raw modes, echo/editing behavior, automatic restoration, and Ctrl-C termination in both modes are adopted. Ctrl-D details, buffer limits, and non-text key encoding remain proposals or implementation decisions as identified above.

### 8.4. Terminal controls, backing model, and keys — agreed direction; colour extension planned

Agreed initial direction: a documented MLOS monochrome terminal profile using a small subset of familiar ANSI/DEC escape sequences: cursor positioning/movement, display/line erase, normal and reverse-video attributes, and cursor visibility. Ordinary CR/LF, tab, backspace, wrapping, and scrolling need precise behavior. Use 7-bit ESC-prefixed control sequences; keep Latin-1 text and avoid adding 8-bit C1 control recognition initially. Initially consume recognized colour-setting sequences without colour effects. The user wants colour ANSI support later; retain that as an explicit roadmap requirement. Its palette/attribute representation and colour-capable graphics backend are future design work. The initial two-byte cell representation is an implementation choice, not a fixed public ABI or a promise that later colour and style attributes fit in the same byte. Specify supported operations explicitly rather than advertising complete VT100 or xterm compatibility. Applications use a small library for terminal control and capability/geometry queries.

The accepted planning direction uses a GUI terminal process that owns a text-cell model and parser state, and sends drawing requests to the separate window manager. Store one character byte and one attribute byte per cell. An 80 by 25 grid therefore needs 4,000 bytes of cell storage, excluding parser, dirty-region tracking, IPC, heap, and process overhead. This is a cell-storage calculation, not the whole process RAM cost. Whole-bank admission still applies. An 8 by 16 one-bit glyph set with 256 slots takes 4,096 bytes before any metadata and can be shared by the renderer. Glyph data must match the agreed Latin-1 profile.

The 640 by 400 framebuffer holds an 80 by 25 grid only when the whole area is available to 8 by 16 cells; window borders and title bars reduce the client area. Do not hard-code every GUI terminal to 80 by 25. Query actual rows/columns, and preserve a correct grid/redraw state if resizing is implemented. Exact resize notifications and allocation-failure behavior remain to be specified.

Redraw damaged cells/regions and reconstruct an exposed terminal window from its cell model. Do not require a private 32,000-byte bitmap per terminal. Agreed: no scrollback history is needed. Recommend deferring an alternate screen buffer initially; that separate saved-screen feature has not been explicitly settled. Retained cells are the current screen. Serial output sends the same profile's control bytes to an appropriately configured external terminal, rather than requiring the GUI cell model in the serial-only shell. Graphics fallback-console state remains separately budgeted. Full-screen applications must repaint or restore the prompt when leaving; no second saved screen is promised.

Agreed direction: consistent escape-sequence encodings for arrows, navigation, and function keys from the GUI terminal and supported serial-terminal configurations. A shared application library decodes the raw stream into key events; the kernel/TTY byte interface retains its agreed raw semantics. Literal Escape and an Escape-prefixed key sequence require a bounded configurable decoding delay when no more bytes arrive; begin testing around 40 ms, using sleep/readiness rather than polling. Exact byte mappings, normal/application key modes, malformed sequence handling, and delay tuning remain to be specified. Ctrl-C keeps its agreed foreground-termination behavior. Native GUI window events remain a separate interface.

The parser and key decoder must retain partial sequences across reads, bound parameter/string storage and per-dispatch work, and recover from unsupported or malformed sequences without unbounded allocation. Parser policy, output batching, frame/update timing, and device throughput require implementation measurements.

The initial control subset and shared key-decoding direction are adopted, no scrollback is required, and colour ANSI support is planned later. Exact control/key tables, parser bounds, geometry/resize semantics, and the separate alternate-screen proposal remain unresolved.

### 8.5. GUI focus, redraw ownership, and event pressure — agreed; protocol details pending

Agreed: click-to-focus and raise for ordinary application windows. Keyboard events go to the focused client. A content click that changes focus is also delivered to that client; title-bar and border actions belong to the window manager. While a mouse button is held, capture subsequent movement and its release to the original target so a drag can finish even outside that window. Initial capture must distinguish window-manager frame dragging from client-area interaction. On target destruction/disconnection, release capture safely; old events must not address a newly reused window handle.

Agreed: explicit focus gained/lost events. Clients must clear or reconcile held-key/button state on focus loss and capture cancellation. The window manager retains the current physical input state. Exact modifier snapshots, event ordering, click-through rules for modal/disabled windows, and mouse/key encoding remain to be specified. Game pause-on-focus-loss is an application choice, not an imposed scheduler action.

Agreed: application-owned content models. The window manager retains window position, stacking, decorations, visibility/damage, and resource identity. It requests redraw of damaged client regions; clients reconstruct content from their own model using drawing commands. The window manager validates ownership and clips every request to the current visible client region. Apps need no per-window full-screen backing bitmap. Text terminals retain their cell model under section 8.4; a game retains board/state and optional explicit resources. The proposed initial drawing operations are bounded fills, monochrome bitmap chunks, and text/glyph runs, with precise wire layout still pending.

Outline-only dragging remains the agreed initial option. Coalesce repeated redraw damage, bound damage/clip tracking, and attach enough identity/state to reject obsolete drawing requests after a window is destroyed or its geometry changes. Exact drawing epochs, redraw acknowledgements, and resize/allocation-failure handling require specification. An unresponsive client's damage remains local to its window; the manager can continue decorations, input routing, and other clients' redraw work.

Agreed: nonblocking publication of window-manager events to each private client channel. Combine replaceable motion/redraw notifications and keep a bounded per-client pending backlog for essential key/button/focus/close events. A finite queue cannot preserve an unlimited stream for a client that never reads. If essential backlog capacity is exhausted, disconnect that GUI client and remove its windows; use kernel endpoint closure to notify/wake the process even when no further payload event fits. Preserve the existing buffered-data drain/lifetime rules.

Disconnecting one GUI connection does not imply killing its process or unrelated processes. A client may observe closure, release GUI resources, and exit or continue using other facilities. Its open files and non-GUI resources follow normal process lifetime and explicit close rules. Window-manager failure still invokes the separate agreed whole-GUI-session descendant cleanup. Connection removal must also invalidate window IDs, release input capture/focus safely, and withdraw references before reuse. The precise fallback focus choice and reconnection API remain to be specified.

The manager must never block its entire event loop on a client's full outgoing queue, a reply backlog, or a long bitmap operation. Event/command admission, bounded rendering work, and fair client dispatch require implementation budgets and target measurements. Pending event storage is additional to the advertised channel payload capacity and counts toward total memory admission.

These focus/capture, application redraw ownership, and bounded event-overflow/disconnection policies are adopted. Exact event records, memory budgets, drawing epochs, and protocol sequencing remain implementation work.

### 8.6. Close requests, resize negotiation, and keyboard translation — agreed direction; detailed protocol pending

Agreed: cooperative window closing. The close button delivers a CLOSE_REQUEST; the application may close the window, ask about unsaved work, or reject/cancel the request. Destroying a window is not automatically process termination: an application may own other windows or non-GUI work. Applications may choose to exit when their last window closes. No silent forced termination timeout is attached to an ordinary close request initially.

Provide a separate explicit force-quit action for a selected application, implemented through kernel termination and the existing safe resource/pending-I/O cleanup rules. This removes that application's windows and terminates its process, rather than merely disconnecting its GUI endpoint. Terminating an application that owns several windows removes all of them. Emergency GUI-session teardown on window-manager failure remains the separate existing rule.

Agreed direction: treat a GUI terminal and its hosted shell/commands as an owned terminal scope. Normal accepted terminal closure must end the hosted shell and its owned running jobs safely; an active job may cause the terminal to ask the user before accepting closure. Force-quitting the terminal requests kernel cleanup of that hosted scope. Other GUI terminals and independent/background jobs outside this scope continue. Scope membership must persist if intermediate processes exit, as GUI-session membership already does. A descendant can leave the scope only through a future explicit detach operation, not by silently losing its parent. Exact ownership tokens, nested-terminal behavior, normal-close sequencing, and explicit force-quit UI remain to be specified. Do not substitute the whole GUI-session identifier for the smaller hosted-terminal scope.

Agreed: per-window resize capability and declared minimum/maximum client dimensions. The manager draws an outline while proposing a new size; the client prepares its model/buffers and accepts or rejects it. Allocation failure rejects the proposal, retaining the old model and geometry. Commit agreed geometry only after preparation succeeds and use a new geometry identity/epoch for subsequent drawing and events. Both sides need defined commit/abort sequencing, stale-proposal checks, and preparation cleanup if either side exits. Keep the client informed of the final client dimensions and request redraw after commit.

One pending resize proposal per window is enough initially; replace/coalesce subsequent drag targets through a specified cancel/reproposal rule. A configurable nonresponse deadline cancels the proposal, retaining the old geometry; it does not terminate the application or block other windows. New storage prepared for an aborted proposal must be released safely. Do not require every application to support resizing: a game may declare a fixed client size. Font/cell dimensions and decorations determine terminal rows/columns; applications query the committed geometry.

Agreed: one OS keyboard translation layer for the Swedish layout and Latin-1 text policy. Native GUI input includes key identity, press/release state, modifiers, and separate generated-text events. Key identity is hardware independent, not a PS/2 scan code exposed as the GUI ABI. A native application uses key events for navigation/shortcuts/game controls and text events for text entry, avoiding double application of the same keystroke. Focus loss/capture cancellation still reconciles held input under section 8.5.

The GUI terminal consumes those events and produces the agreed Latin-1 bytes and special-key escape sequences for its hosted TTY. Serial input is already a byte stream from the external terminal and uses the shared decoder; it does not promise physical key-release events. Ctrl-C termination applies to foreground TTY commands under the agreed terminal policy; native GUI applications receive their keyboard events under their own application/WM shortcut rules. Repeat, dead keys, Alt/Control combinations, LEDs, and reserved manager shortcuts remain to be specified.

Translation/driver placement is a memory-budget decision, not a requirement for another always-resident process. Actual PS/2 input transport, interrupt/poll handling, and mouse/keyboard device recovery need hardware/source verification. The protocol must not assume an unverified PS/2 IRQ or scan-code set.

These cooperative-close/explicit-force-quit, terminal-scope cleanup, negotiated-resize, and shared-keyboard directions are adopted. Exact scope records, close/resize sequencing, and keyboard protocol remain implementation work.

### 8.7. Modal windows — agreed; activation protocol pending

Agreed: MLOS supports modal windows with owner-window default scope, an optional application-wide scope, nested dialog routing, and reliable owner/child cleanup and focus restoration. Exact wire operations and activation barriers remain to be specified.

Agreed: owner-window modality is the default: an explicitly owned dialog blocks keyboard, mouse, close-button, move, and resize interaction with its owner and applicable owned window subtree outside the active modal branch. Unrelated windows of that application remain usable. Offer application-wide modality as an explicit option, blocking that GUI client's other windows outside the active dialog branch. Other applications remain usable in both modes. Desktop-wide/system modality is outside the adopted initial scope.

The window manager owns and enforces modal registration, owner links, blocked-input sets, stacking constraints, focus routing, and teardown. A modal owner must be a live window belonging to the same GUI client initially; reject cycles and invalid/stale handles. Modality controls input eligibility. It does not suspend processes, hold kernel locks across a user interaction, or suppress redraw/service events for blocked windows. Application modal declarations are GUI routing rules, not an account authorization mechanism.

Agreed direction: modal child windows remain above their owner inside the application's relevant window group, while other applications may be raised above that group. A click on a blocked owner activates/raises the eligible dialog branch and is consumed; it must not perform the owner's action or be replayed after dismissal. Opening a dialog for a currently active owner transfers focus to the eligible dialog. A dialog belonging to an inactive application must not steal focus from another application. When the user returns to the blocked application/window, focus routes to its eligible modal leaf. Exact stacking/group records and any visual indication of blocked owners remain to be specified.

Agreed: nested modal dialogs with acyclic ownership. For a given blocked branch, only the top/deepest active modal accepts input; its modal ancestors remain blocked. Unrelated branches and other applications retain eligibility according to the selected scope. An application-wide modal and nested owner-modal descendants must have a deterministic precedence rule; pending multiple application-wide requests should be serialized or rejected rather than creating competing active leaves. Depth and live-window capacity are bounded by admitted resources, with an explicit creation/activation failure if metadata or queue capacity is unavailable.

On activation, cancel/reconcile capture and pending interactive resize in the newly blocked set, send focus/capture state changes, and prevent already queued owner input from being applied after modality takes effect. The precise activation acknowledgement, input generation/barrier, and client-library filtering require protocol specification. A blocked client still consumes its shared event channel and handles redraw, notifications, and input for eligible dialogs. Modal state changes must not become a synchronous window-manager wait for the application.

Agreed: closing/destroying a modal removes its blocking state and restores focus to the nearest eligible live owner only if that application's branch still holds focus. If another application has gained focus, closing the dialog must not pull focus back. Destroying an owner destroys its owned modal descendants and releases their modal records. Normal owner-close requests remain subject to active modality and cooperative-close policy; accepted programmatic destruction and explicit force-quit still clean up the ownership tree. Client exit/disconnection, event-backlog exhaustion, and GUI-session failure must remove every affected modal record so a dead dialog cannot leave surviving windows disabled.

Dialog controls, unsaved-work questions, rendering, and result values belong to the application or a shared UI library. A convenience wait-for-dialog call may be offered only if it continues servicing the client's necessary event traffic; an application must not stop reading its event channel while the dialog is open. Callback/state-machine handling is a suitable initial model. Exact library ABI and dialog widgets remain to be specified.

Owner-window default plus optional application-wide scope, nested modal routing, and owner/child cleanup/focus restoration are adopted. Pending competing modal activation, exact input fencing, memory admission, and library behavior still require specification.

### 8.8. Asynchronous I/O for GUI event loops — agreed direction; API pending

Consistency review: initially each GUI application has one thread, descriptor I/O may block, and the window manager disconnects clients whose bounded essential-event backlog is exhausted. A GUI process waiting inside a synchronous CF request may therefore stop reading input/redraw events even though the scheduler and other applications continue. Preemption alone does not keep that client's event loop responsive.

Agreed direction: optional asynchronous descriptor/storage operations for GUI clients, retaining the agreed blocking read/write interface for simple console programs. A submission returns an operation token after bounded admission and argument/data copying. The client waits on GUI and I/O-completion channels with the existing multi-channel IPC wait, handles other events, and collects the eventual count/error/data. Completion tokens identify the operation rather than relying on reused descriptor numbers. Precise submission/collection ABI and per-descriptor ordering remain to be specified.

Use bounded kernel/service-owned transfer buffers and result storage: accepted write chunks no longer depend on a caller buffer that may be changed/freed, and read chunks are copied to validated application memory when collected. Account for pending/completed operations in memory admission; failure returns an error before accepting an operation that cannot be retained. Services must retain/query completion state if a bounded notification cannot be enqueued immediately, and never block all clients on one completion queue. Exact notification/readiness accounting must prevent lost completion wakeups and duplicate collection.

Cancellation and process exit withdraw future delivery and request safe cancellation, then release buffers, descriptor references, exclusive-file ownership, and physical banks only after any in-flight device work no longer uses them. Cancellation does not promise undoing bytes already written. The filesystem's shared metadata/storage state machine remains serialized with bounded preemptible work, and unrelated GUI/IPC handling continues. Temporary CF transfer lifetime rules are unchanged.

This optional asynchronous I/O direction is adopted; it does not require application threads in the initial release. Exact operation records, submission/collection API, notification capacity, and cancellation ordering remain implementation work.

## 9. Traps — agreed

Illegal-instruction and math-error traps terminate the process. A registered application handler may log/report before termination; it does not resume execution or repair saved registers in the current design.

Proposed safeguards: reporting runs in the faulting process's context, has a bounded stack and execution allowance, and cannot recursively trap forever. Handler failure terminates immediately. Kernel faults require a separate emergency diagnostic path; they are not ordinary application termination.

## 10. Executable format — accepted direction

A raw executable image with a small header is accepted. The header describes its ABI version, entry offset, initialized-data size, zero-initialized-data size, and stack requirement. The shell supplies arguments and standard input/output handles; program termination returns an exit status.

Agreed: the loader must support applications up to 48 KiB under the proposed logical map. It allocates all declared initial resident banks before execution, from one to three banks. The image, BSS, initial stack, arguments, and any initial heap reserve must fit within that footprint. Physical banks need not be adjacent; mapping supplies the required logical addresses. File headers are loader metadata rather than an additional requirement to keep header bytes resident.

The precise field widths, endianness, magic, initial logical entry address, and placement of stack/heap/arguments remain to be specified. Proposed header additions describe the initial resident extent and any reserved resource/shared window. The linker/CMOC output and loader must agree on absolute logical addresses. Executable layout declaration does not give applications direct MMU access.

### 10.1. Boot, shell, and cancellation — agreed

- A small init process starts core services and the serial shell. Console is the initial default; a shell command can start the GUI session. A later startup setting may choose GUI automatically.
- State-changing shell commands such as cd and exit are builtins. Independently loaded commands execute as foreground processes, each with an initial single thread; the shell waits while OS services continue. Separate ownership and trap cleanup preserve the shell if a command fails.
- Ctrl-C requests termination of the foreground application through kernel cleanup, then returns control to the shell. Termination must not reclaim buffers or release filesystem ownership while outstanding work still uses them; cancellation safe points and pending-I/O handling need specification.

These startup, foreground-command, and Ctrl-C policies are agreed. Exact startup configuration, cancellation safe points, pending-I/O handling, and input routing remain implementation work. This agreement does not adopt additional proposals elsewhere in the document.

### 10.2. Service failure policy — agreed

| Failure | Agreed initial response |
| --- | --- |
| Console shell | Terminate its foreground job with safe cleanup, then restart the shell once. Further repeated failure leaves an emergency serial diagnostic console rather than an unbounded restart loop. |
| MLFS service | Stop further filesystem requests, notify affected clients with an I/O/service failure, preserve serial diagnostics, and require manual recovery/reset. Do not replay unfinished writes or restart blindly over potentially incomplete filesystem metadata. |
| Init or core kernel | Report through an emergency serial path and halt for manual reset, avoiding dependence on normal IPC/service recovery. |
| Window manager | Apply the already agreed GUI-session descendant cleanup and graphics-console-to-serial fallback. This is not a new restart policy. |

These initial fault policies are agreed. Outstanding I/O and ownership must be settled before buffers/handles are reclaimed; exact safe stopping rules remain implementation work.

### 10.3. Hardware facts required next

Selected timer: XR88C92 serial counter/timer via IRQ. The inspected default-branch stage-2 test programs that timer for a nominal 50 Hz test. Earlier BIOS sources also expose 6522 timer routines, but VIA is not the chosen scheduler source. Neither the test nor its comments establish a working 1 kHz configuration.

Confirmed UART crystal: 3.6864 MHz. Reserve the selected counter/timer for scheduling; ordinary serial channels should use independent baud-rate-generator selections where available. Timer mode, preload, shared IRQ servicing, and UART A/B compatibility still need target verification.

Agreed initial configuration, derived from the datasheet but not yet hardware-tested: timer mode with ACR[6:4]=111 (crystal divided by 16), CTPU:CTPL=$0073 (115). Timer output has a period of twice the preload count; ISR bit 3 is asserted on its rising edge, so IRQ frequency is 3,686,400 / (16 × 2 × 115) = approximately 1,001.739 Hz. One tick is approximately 0.998264 ms and five ticks approximately 4.991319 ms. Use the configured period for monotonic time/deadline conversion rather than treating each tick as exactly one millisecond. A fixed preload and time conversion using the configured period are agreed; no per-tick reload dithering is selected.

In timer mode, reading the stop-counter command clears the timer interrupt without stopping the periodic timer. Shared IRQ handling must acknowledge only the indicated sources, preserve the combined interrupt mask, and bound service work. Source-specific UART handling remains to be specified.

Audit finding: the inspected stage-2 test selects timer mode 7 and preload $1200 (4,608). With the confirmed crystal and datasheet timing, that configuration predicts 25 Hz, although its comments say 50 Hz. Verify the actual interrupt rate on the target and reconcile the test before using it as timing evidence; no source change or hardware measurement has been performed.

The GAL MMU gate's unlock sources SWI/NMI/reset, BA/BS plus low-address-byte vector-fetch detection, and relock write at $F405 are agreed. The Motorola 6809-family manual identifies BA=0/BS=1 as interrupt/reset acknowledgement, qualifying vector fetches; native 6309 trap timing still needs target validation. Under the existing selected-vector policy, IRQ and trap handlers remain in ROM and use the dedicated SWI bridge before privileged I/O writes or mapping are required. The latest write-only policy permits UART status reads and read-based timer acknowledgement before SWI; required device writes still need privilege. No change to the unlock-source set is implied by the clarified detection method.

Expected vector pairs from the current BIOS table: plain SWI $FFFA–$FFFB, NMI $FFFC–$FFFD, reset $FFFE–$FFFF; IRQ $FFF8–$FFF9 and trap $FFF0–$FFF1 remain bridge entries under this policy. These are policy-derived expected decode matches. The inspected stage-3 notes select low nibbles A/E and omit NMI's C; they require revision and are not implemented GAL equations. Audit both byte cycles, sampling phase, ordinary/dummy reads, reset, SWI variants, nested interrupts, and relock behavior.

### 10.4. Serial driver and CPU-mode work

Required serial-driver integration: the timer and both UART channels share interrupt-control state. The current default-branch SERIAL_ENABLE_CT_IRQ routine writes $08 directly to SERIAL_IMR, replacing other enabled sources. MLOS must manage a combined mask and service pending timer/receive/transmit events without losing unrelated enables. Timer configuration must also preserve unrelated ACR settings, including baud-rate selection. Central driver-owned software shadow values are a proposed mechanism; exact registers and acknowledgement must be audited against the datasheet.

The existing BIOS reset code executes LDMD #$01 for native mode. Agreed MLOS ABI: remain in HD6309 native mode throughout normal OS/application execution; the OS owns CPU mode-control settings and applications must not change them. This is an application ABI rule, not hardware-enforced protection. Trap diagnostic status and all relevant extra register state still need precise handling.

### 10.5. Syscall and stack conventions — agreed direction

Agreed initial syscall convention: plain SWI enters MLOS; A carries the call number, X points to an application parameter block for calls needing arguments, and D carries the result. Carry clear indicates success; carry set indicates failure with D holding an error code. No-argument operations need no parameter block. Preserve other application registers; define exact CC effects and native interrupt-frame offsets during implementation. The handler must place results into the saved application frame before RTI. CMOC wrappers translate the compiler's calling convention; the compiler ABI and runtime must be audited before claiming compatibility.

The kernel copies and validates parameter blocks through the recorded application map. A pointer cannot be dereferenced as an ordinary kernel pointer after its application window has been replaced. Blocking operations retain kernel-owned request state; copying payloads must still follow the bounded banked-memory rules elsewhere in this draft.

Agreed initial stack policy: the executable declares a fixed application-stack reservation, with 1 KiB as a configurable toolchain default pending measurements. The loader includes this reservation in the resident footprint and supplies the declared initial S. No automatic stack growth initially. Keep headroom for interrupt/bridge frames and validate the exact reserve from native-mode entry tests. Kernel/emergency stacks remain separate in common RAM. Debug canaries and saved-S range checks can detect some overruns; they do not prevent corruption on the current unprotected hardware. Applications needing deeper C call chains declare a larger stack.

### 10.6. Executable linking, heap growth, and reclamation — agreed direction

1. **Fixed linked logical addresses initially; relocatable loading later.** Agreed: initially link each executable for its declared MLOS logical layout and load it at those addresses. Different processes can use the same logical addresses because their physical banks differ. Relocatable loading is the preferred long-term direction. Relocation takes place before application execution; ordinary live pointers remain stable after startup. Exact load origin, direct-page convention, initialized-image layout, stack placement, header bytes, relocation records, and toolchain support remain to be specified. Reserve an explicit format/version distinction between fixed and relocatable images; an initial loader must reject unsupported image forms rather than misload them. No validated CMOC relocation support is claimed.

2. **Automatic ordinary-heap growth through the kernel.** Agreed: malloc may obtain additional physical banks and commit eligible uncommitted application windows as resident when its existing heap cannot satisfy a request. It must never take a reserved resource window or repurpose a resident window with live contents. Preserve all existing ordinary pointers and the initial stack location. Heap regions may be separate; the allocator must track each region. Failure to find suitable logical space, physical RAM, or bookkeeping returns ordinary allocation failure, with no swapping. Extra unmapped physical resource banks remain a separate explicit interface. Kernel ownership of memory operations remains unchanged.

3. **Automatically reclaim completely empty private heap banks.** Agreed: free makes remaining free space reusable within the process, and MLOS returns a completely empty heap-only bank to the global physical free pool once it is safe to reclaim. Do not retain such banks until process exit. Here empty means no live allocation or other required object, not that its bytes contain zero. Banks containing code, initialized/static data, BSS, arguments, stacks, or reserved OS objects remain occupied. Explicit resource-bank contents remain application-managed until released through the bank API; an all-zero resource bank is not evidence of release.

Required reclamation ordering: account for every live allocation touching the bank and any kernel/device operation that still uses it; withdraw the bank's free regions and references from allocator metadata; revoke its application mapping in both the saved process map and any active map; return its eligible logical window to uncommitted; then make the physical bank available for reassignment. Treat these updates as a bounded synchronized transaction with respect to scheduling, mapping, and other allocations. Future threads require the same process-map synchronization. Do not move other live allocations to manufacture an empty bank.

An outstanding kernel/device reference delays reuse. Proposed bookkeeping uses pin/reference counts and a pending-reclamation state; after the last reference is released, finish reclamation without waiting for process exit. An allocation marked free while still pinned must not be reused for another allocation before the operation releases it. Exact API handling of concurrent free and I/O remains to be specified.

Ordinary pointer-based allocation is limited by logical windows as well as physical memory. A process with two resident windows and its remaining window reserved for resources cannot add a third resident heap window even when free physical banks exist. Reclaimed eligible windows may later be recommitted for heap growth with different physical banks.

### 10.7. Vacant-window mapping and allocation spans — agreed direction

Current simulator observation: each RAM window selects a physical bank. BankedMemory masks the register value by bank_count minus one. In the inspected 512 KiB configuration there are 32 banks, so $FF selects bank 31 rather than disabling a window. The user confirms the GAL also has no ability to disable individual memory windows.

Agreed fallback: reserve one 16 KiB physical discard bank for all vacant application windows, containing no live application or kernel state. Reserve it once for the system, not once per process. It is permanently excluded from the allocatable physical pool. Before reassigning a reclaimed bank, remove it from active/saved process maps and park its vacant window on the discard bank. Access there does not produce a memory-protection fault and its contents are unspecified. Never park a vacant window on the core kernel/common-RAM bank. Implementation and target/simulator validation remain pending.

Agreed: ordinary malloc allocations may cross adjacent eligible resident logical windows when a contiguous logical free range exists and enough physical backing can be supplied. Do not impose a one-bank per-allocation limit. Physical banks need not be adjacent. All banks touched by a live spanning allocation must stay allocated and occupy their assigned logical addresses whenever the owning process executes. The scheduler restores the complete process map after running other processes. Kernel/device references also delay reclamation. This follows the resident-window rule: ordinary live heap banks cannot be repurposed as resource windows.

Allocation admission has two independent requirements: enough physical backing and a sufficiently large contiguous logical free range within the application's resident/uncommitted eligible windows. Physical availability alone cannot satisfy an ordinary pointer-based allocation beyond the proposed 48 KiB mapped footprint or across a reserved region. Code, data, arguments, stack, allocator overhead, and earlier allocations reduce the space available to the heap. No implicit relocation of live objects or swapping is introduced. Explicit bank handles remain available for datasets outside the ordinary mapped heap.

Whole-bank admission must count all newly required 16 KiB physical frames, not just the requested payload bytes. For example, if both windows are initially uncommitted, a 20 KiB block at $4000–$8FFF requires two physical frames backing $4000–$7FFF and $8000–$BFFF: 32 KiB of physical backing. The remaining 12 KiB in the second frame can be used for other heap allocations if layout/metadata permit. A request that uses existing committed heap space may need fewer new frames.

The allocator must account for every bank covered by an allocation and operation. A bank containing any part of a live allocation is not empty. After free, reclaim each affected bank independently once no other live object or kernel/device reference occupies it; other allocations in the remaining portion of a frame may keep that frame resident. Tracking spans, alignment, range validation, metadata placement, and synchronized publication/reclamation are implementation work.


### 10.8. Launch context and handle inheritance — agreed; precise ABI pending

Agreed: direct process creation through spawn with executable, arguments, and a standard-I/O setup. Inherit the parent's working directory and GUI-session membership under the existing agreed rules, and use the same terminal/standard-I/O destinations by default. Other file and IPC handles are supplied explicitly rather than all being inherited. Copy launch arguments into the child's private resident memory and prepare banks, stack, startup context, and I/O before making it runnable. Failed preparation must release provisional resources after outstanding operations are safely settled. Exact argv/startup layout and CMOC entry shim remain to be specified.

Handle inheritance must preserve the existing ownership rules. Inheriting a terminal association is not a second producer on the parent's SPSC output channel: allocate separate per-process channels through the shared terminal backend, with foreground input ownership agreed in section 8.1 and its precise delivery mechanism still to be specified. Stdout and stderr may reference the same output provider within one process. Child-owned redirection opens and any explicit handoff of writable file/IPC endpoints must keep a single active owner; ordinary handle copying must not create concurrent write owners or duplicate occupied SPSC roles. Writable-file handoff, reader offsets, descriptor reference counts, and parent restoration on foreground-command exit require precise implementation rules.

This launch/inheritance policy is adopted. Shell redirection/pipeline syntax, full terminal discipline, and the precise handoff ABI remain unresolved.


### 10.9. Initial shell arguments and redirection — agreed scope; grammar pending

Agreed: an initial shell with foreground commands, simple whitespace-separated arguments, quoted arguments, and input/output redirection using < and >. Input redirection opens a regular file for reading; output redirection opens it exclusively for writing and explicitly creates or truncates it according to the chosen > semantics. Only the child owns a redirected writer, preserving the agreed exclusive file-open policy. Conflicting file use returns BUSY rather than creating another writer.

The launch operation must validate executable/argument/resource setup and establish the child's descriptor bindings before making it runnable. Failed launch must release provisional ownership safely. File creation/truncation is a visible filesystem change and is not automatically undone on later launch or application failure; do not promise transactional redirection. Exact preflight/open ordering, truncate support, quoting/escaping grammar, and count/length limits require specification.

Agreed: defer pipelines, shell background syntax, command substitution, wildcard expansion, and append redirection from the first console release. The kernel remains preemptive with multiple services/processes; this is the initial shell feature scope. Descriptor streams and process ownership should permit pipelines to be added later without replacing the core I/O design.

This initial shell scope, including quoted arguments and < / > redirection with create/truncate behavior and an exclusive child-owned writer, is adopted. Precise grammar, limits, and launch/open ordering remain implementation work.

## 11. Proposed implementation milestones

1. Specify and test ROM entry/exit, common RAM, bank-0 switching, gate behavior, native context records, and trap termination.
2. Boot kernel from CF/MLFS into serial console; support one loaded application, argument/return convention, allocation failure, and complete exit cleanup.
3. Add preemptive processes, yield, sleep/wakeup, fairness, named buffers, and process-death notifications. Application threads may remain deferred.
4. Port/integrate MLFS with descriptors, reader/writer ownership, scheduled storage progress, and bounded buffering.
5. Add virtual terminals, serial logging, and a hardware-independent monochrome graphics backend; extend simulator bitmap/interlace behavior.
6. Start the separate window manager, GUI shell terminal, file browser, and Tetris; test window-manager crash and graphics-to-serial recovery.
7. Add multiple threads per process using the existing ownership model; implement the V9958 backend later.

These milestones are a proposal. Console bring-up is incremental, but preemptive architecture and entry paths are designed before adding concurrency.

### 11.1. Loadable expansion-card drivers — banked modules and loading policy agreed; ABI pending

The user plans an expansion board with several different add-on cards and requires loadable drivers, including disk/IDE storage, ADC, parallel printer and modem/network hardware. This extends the architecture beyond fixed BIOS drivers. Keep the bootstrap CF/serial hardware support available before module loading; the minimum system still boots from CF. Booting directly from an expansion drive is a separate future bootstrap requirement, not implied here.

Agreed initial implementation: trusted HD6309 kernel driver modules loaded from CF/MLFS into OS-owned RAM banks, at boot or by an explicit console command. Successful modules remain resident until reboot; runtime unloading is deferred. The core kernel stays in physical bank 0. The kernel maps a module through a controlled logical window to call it, preserving caller mappings, native CPU context and stack ownership, and restores the prior mapping on return. Establish a precise module-code/state/entry-stack layout; do not assume there is room for every driver in the fixed 8 KiB common window or the 16 KiB core.

A simple first loader can use fixed-linked module addresses plus a versioned kernel-driver import/entry table, consistent with the current fixed-linking direction. Drivers may depend on the OS release. Do not expose arbitrary private kernel symbols as a public ABI. Assembly is the natural initial hardware layer; permit CMOC implementations through explicit wrappers when code size, calling convention and interrupt-entry preservation have been established. Relocatable loading remains the longer-term direction.

Whole-bank module allocation is a proposed first accounting model, not a required permanent representation: a small driver may consume an entire 16 KiB frame. All module code/state/buffers consume the same no-swap physical pool as applications, services and IPC. Validate image bounds, version/entries, required banks, driver resources and bounded buffers before hardware initialization. Publish devices only after successful initialization. On failure unwind partial allocation/registration after quiescing any started hardware and withdrawing IRQ callbacks; do not free code/state still reachable by a device, interrupt or DMA operation. Packing or a smaller allocation granularity can be considered later. No successful module loading or target fit is claimed.

| Card/function | Proposed lower-level driver interface | Higher-level consumer |
| --- | --- | --- |
| Floppy/disk/IDE storage | Block geometry, sector reads/writes, completion and media/error status. | MLFS/mount service; multiple drives exposed under mounted paths. Controller/sector format and removable-media semantics remain open. |
| ADC | Channel/range configuration and bounded sample acquisition, with optional buffered samples. | Applications through a device handle and defined sample records. Rates, precision, timestamps and overflow behavior require card requirements. |
| Parallel printer | Buffered output, ready/busy/error status and bounded handshake progress. | Printer stream; optional spooling service later. |
| Modem | Byte stream, UART/modem controls and completion/status events. | Terminal/communications services; modem protocols are separate from the card driver. |
| Network adapter | Bounded frame send/receive and link/error status. | Separate protocol service. Ethernet/serial link type and IP/TCP/UDP scope are not yet selected. |

Suggested device namespace is a virtual /dev backend, with illustrative names /dev/hd0, /dev/fd0, /dev/adc0, /dev/lp0, /dev/modem0 and /dev/net0. Names, descriptor operations and typed control requests are proposals. Storage uses the block interface beneath MLFS; a raw block descriptor must not allow writes that bypass a live writable filesystem's ownership/cache/metadata rules. Agreed raw-device ownership is exclusive to one service; client-sharing and operation semantics are defined by that service/device class, independently of MLFS regular-file shared-reader/exclusive-writer rules. Unmount/busy lifetime rules still apply to an underlying driver.

Proposed responsibilities:

- The kernel owns the driver registry, module banks and generation-safe references, claims to I/O ranges or explicit shared/selected windows, interrupt subscriptions, request records, timeouts, pinned transfer buffers and completion routing. Resource claims prevent accidental conflicts; they are correctness/lifetime rules rather than multi-user access control.
- A driver contains controller-specific initialization, bounded transfer steps, status/acknowledgement operations, stop/quiesce/error handling and device-class operations. Actual I/O writes execute during privileged kernel/module entry; ordinary clients use OS/service APIs for reads and writes.
- Filesystem logic, modem command/session handling, printer spooling and network protocols remain separate services or applications where useful. Do not put an entire filesystem or network stack into a short interrupt callback.
- Drivers may start slow operations and return pending completion; the requesting process waits through the existing blocking/optional async model while unrelated work continues. Module/driver code must not block on a slow card while holding a global kernel/device lock or leave a map update half complete.
- Interrupt front ends only identify/acknowledge enough state, capture bounded data and schedule continued work. Callbacks live in a bank, so entry must map the correct module from fixed ROM/kernel code with a valid common stack; never leave a raw callback pointer callable when its bank is not mapped. Shared IRQ probing must use driver-specific safe status reads, which may themselves have side effects.
- Card identification is explicitly deferred: a future baseboard register/interface will report installed card identities, and I2C connectivity to every position will permit optional configuration-EEPROM reads. Proposed first release: load only explicitly configured board/slot/driver bindings; do not read a nonexistent ID register or require EEPROM discovery. Initialization checks, if any, must be specific to the declared controller and bounded.
- Agreed loading/lifetime policy: load from CF at boot or through a console command, and retain successfully loaded modules until reboot. The exact configuration/command grammar remains an implementation detail. Closing client handles or terminating a process does not unload its driver. Failed loads still unwind only after hardware/callback quiescence. Hot insertion/removal is not selected. A future runtime-unload extension must enforce BUSY/reference checks for mounted devices, open handles, active requests, callbacks and DMA/buffers, then quiesce hardware before freeing code/state.
- Drivers in the accepted arrangement are trusted kernel code. Their faults follow core/emergency policy; the current RAM/protection model does not promise isolated driver crashes. Separate protocol/filesystem/spooling services remain useful above these hardware modules. The alternative service-process hardware-driver model is deferred.

Observed motherboard expansion wiring: P3 is the ExpansionPort connector. It carries address/data, E, R/W, /RD, /WR, /EXP_EN, /RAMX_EN, mapped address bits, /BREQ, BAVAIL and /MAP_EN. Only one interrupt line is shown on this connector, /IRQ8 at pin 4; it does not export the full motherboard IRQ-source set. The user confirms a baseboard register will identify requesting card slots, accepting register-based pending-slot dispatch. This is a planned hardware provision, not an implemented/tested register. The user now provisionally accepts non-clearing active-high pending bits 0–5 and a matching enable mask initially zero, with card-side acknowledgement. These may change after hardware completion; exact offsets, routing and electrical timing remain pending. The uploaded PDF's IRQ labels differ from the stage-3 source; confirm the actual route rather than freezing IRQ8 as the backplane ABI (section 11.2). Clear the actual device cause through its controller-specific operation; do not blindly clear an aggregate line and lose concurrent requests. The provisionally agreed register contract is not evidence of an implemented backplane. Section 11.3 records it and the hardware-adaptation boundary.

The user now supplies the fixed address scheme in page 5 of µLind Motherboard.pdf; section 11.2 records two baseboards with six slots each. The current plan therefore does not need a shared slot/page selector. Drivers claim their board/slot's fixed I/O window, and the OS retains baseboard-control ownership. Any indirect registers internal to a particular card still require driver-specific serialization. Existing fixed motherboard ports and MMU registers remain reserved.

DMA handshake signals are exported but do not establish a completed DMA subsystem. A future bus-master driver must obtain stable physical buffers from MLOS, pin them through completion/cancel/quiesce, validate ranges/lengths and preserve the processor/bus handoff. The I/O-write gate does not by itself constrain an external bus master. Programmed-I/O is a proposed first-driver direction where the card supports it; ADC/network throughput and FIFO budgets require measurements before making rate/loss guarantees.

Fixed expansion-slot addressing is supplied (section 11.2), and trusted banked modules, boot/console loading, retention until reboot and a baseboard pending-slot register are accepted. First-release explicit binding configuration is still the proposed way to load declared hardware without automatic identification. Pending/mask bit semantics are provisionally agreed, with changes permitted after hardware completion. Register offsets/physical timing, upstream IRQ routing, driver entry/import/buffer ABI and device classes remain to be specified. Automatic identification and EEPROM discovery are deferred. Controller models, IDE data-width adaptation, DMA and card rates follow; runtime unloading is deferred.

### 11.2. Fixed expansion-board addressing — user-supplied plan; decode details pending

The user states that expansion cards reside in kernel-controlled I/O space and identifies page 5 of the uploaded µLind Motherboard.pdf as the address scheme. It defines two 256-byte baseboard regions, each containing a 64-byte baseboard-control area and six fixed card windows. Slot 1 is two adjacent 64-byte rows under one 7-bit label, combined below as 128 bytes. No runtime board/slot selector is implied.

| Function | Baseboard 1 | Baseboard 2 | Reserved bytes per board |
| --- | --- | --- | --- |
| Baseboard control | $F600–$F63F | $F700–$F73F | 64 |
| Slot 1 | $F640–$F6BF | $F740–$F7BF | 128 |
| Slot 2 | $F6C0–$F6DF | $F7C0–$F7DF | 32, confirmed by user; A4 don't-care |
| Slot 3 | $F6E0–$F6E7 | $F7E0–$F7E7 | 8 |
| Slot 4 | $F6E8–$F6EF | $F7E8–$F7EF | 8 |
| Slot 5 | $F6F0–$F6F7 | $F7F0–$F7F7 | 8 |
| Slot 6 | $F6F8–$F6FF | $F7F8–$F7FF | 8 |

The labelled ranges account for exactly 256 bytes per baseboard and 512 bytes across $F600–$F7FF, without overlaps or gaps. They are assigned I/O address space, not additional program RAM. Twelve fixed card slots are described across the two baseboards; this is not a guarantee that both are populated or routed on the current motherboard.

Resolved slot-2 document error: the user confirms 32 bytes is correct. Slot 2 occupies $F6C0–$F6DF or $F7C0–$F7DF; A4 must be don't-care alongside A3–A0, with A5=0 and the board/high-bit selection unchanged. The PDF's printed A4=1 term would select only D0–DF and is erroneous. This settles the intended decoder contract; the uploaded PDF and GAL source have not been edited or programmed.

Driver resource registration can now identify board number, slot number, fixed base address and reserved window size, together with driver/card identity, class, IRQ routing and OS-owned code/state/buffer references. The kernel validates slot fit and conflicting claims. Proposed drivers receive their assigned base/size at initialization rather than hard-code baseboard 1 addresses. Reserve the baseboard-control area for a coordinating OS/backplane driver; its control-register ABI is not provided. Slot-relative offsets must follow the actual card decoder, including aliases or any indirect registers, rather than assume every reserved address is unique.

The existing protection policy applies unchanged: I/O writes require privilege and ignored writes are the denial behavior; all raw reads are hardware-permitted, while ordinary managed applications use OS/service APIs. “Kernel controlled I/O” is software ownership plus the write gate, not hardware prohibition of reads or per-driver permission checks.

The user clarifies that the page-13 card-identification idea is not implemented. In the future, a baseboard register/interface will expose the identities of the attached cards. I2C connectivity is planned/provided to every board position so a configuration EEPROM on a card can supply extended configuration when needed. Both identification and EEPROM discovery are future features; no register offset, indexing format, ID encoding, empty-slot value, I2C topology/addressing, EEPROM layout or implementation is selected now.

Proposed first-release binding uses explicit machine configuration: board number, slot number, driver image and controller-specific options, plus an explicit interrupt route when required. Derive base address/window size from the settled slot map rather than allow a configuration file to redefine motherboard ranges. A manual binding is a declaration of expected hardware, not automatically verified presence. The driver may perform only safe, bounded controller-specific initialization/checks, and absent/wrong hardware must fail without an unbounded wait or a published working device. Do not depend on an ID register that does not exist or interpret open-bus data as presence.

Keep configured bindings and future discovered identities separate from module loading: the loader receives a validated device/resource description regardless of how it was obtained. Later baseboard IDs can select a known compatible driver; optional EEPROM metadata can refine supported parameters. Discovery timeouts or invalid metadata should remain reportable errors and not silently redirect to a different card/driver. The future identification/EEPROM format is intentionally deferred and is not a first-release dependency.

The document contains other inconsistencies with the previously inspected stage-3 source/accepted ABI:

- Page 3 describes F405 as $7F during PROT_MODE and open bus otherwise. The agreed MLOS status contract remains bit 7=1 privileged/0 locked with unspecified lower bits and reliable D7; the user's reference to page 5 does not revoke that newer decision.
- Page 6 labels the general expansion connector interrupt nIRQ7, page 11 calls Expansion IRQ4 and Keyboard IRQ8, whereas stage-3 P3 pin 4 is labelled /IRQ8. These identify competing source versions/labels, not verified routes. Confirm the actual backplane aggregate source and per-slot pending/mask mechanism before programming interrupt subscriptions.
- Page 6's slot-1 connector table lists A0–A5 even though page 5 reserves 128 bytes. Clarify the seventh register-address bit or possible aliases in the real connector/card implementation before using the upper half as distinct registers. This does not alter the page-5 reserved range.

Page 5 separately defines physical expansion-RAM regions:

| Planned physical range | Label | Size |
| --- | --- | --- |
| $100000–$17FFFF | Board 1 RAM Low | 512 KiB |
| $180000–$1FFFFF | Board 1 RAM High | 512 KiB |
| $200000–$27FFFF | Board 2 RAM Low | 512 KiB |
| $280000–$2FFFFF | Board 2 RAM High | 512 KiB |
| $300000–$3FFFFF | Exp RAM Space | 1 MiB address region |

These are physical memory ranges, distinct from the fixed I/O registers. The 4 MiB address span matches 256 possible 16 KiB bank numbers, but does not establish installed memory. Proposed allocator extension: admit only configured/validated, present general-purpose RAM frames and exclude device-owned memory, gaps and reserved frames. Kernel/common/discard reservations remain banks 0/1/2. The existing 512 KiB budget remains the minimum-machine calculation; no expanded-RAM installation or test is assumed. Extra physical RAM does not increase the 48 KiB simultaneously resident application footprint.

### 11.3. Expansion pending-slot register — provisionally agreed; hardware may change

The user confirms the baseboard will have a register to identify which add-on slots request interrupt service. This closes the question of register-based dispatch versus polling every card as the normal interrupt-identification mechanism. The user now accepts the pending-bit and enable-mask proposals as the working contract, explicitly allowing revision when hardware is completed. Do not treat this as a frozen or implemented electrical interface. Exact register offsets, physical timing and upstream route remain open.

Provisionally agreed contract for each six-slot baseboard:

| Register/function | Working behavior, subject to final hardware |
| --- | --- |
| IRQ_PENDING | Read-only, non-clearing snapshot. Bits 0–5 correspond to slots 1–6; 1 means requesting service. Bits 6–7 are reserved and software masks them out. Offset remains unassigned. |
| IRQ_ENABLE | Read/write per-slot enable mask using the same bit assignments; 1 enables that slot's contribution to the upstream interrupt. Reset value 0. Masking changes upstream interrupt contribution; it does not clear a card's pending cause. |
| Aggregate interrupt | Assert when any bit in IRQ_PENDING & IRQ_ENABLE & $3F is nonzero, subject to the verified motherboard route. |
| Acknowledgement | The card driver clears/drains its controller's interrupt cause; reading the baseboard pending register does not discard requests. For a held-level request, its pending bit falls when the card withdraws the request. |

These are provisionally agreed logical active-high bitmap semantics; physical card/aggregate lines may be active-low. Do not infer the logical bit polarity from signal-name bars. If a card provides pulses rather than held requests, specify a latch and race-safe clear/reassert protocol instead; the level-derived proposal does not preserve an arbitrarily short pulse by itself. A pending bit indicates service is required, not the count of queued ADC samples or packets, which must be tracked by the card/driver.

Recommended dispatch sequence: identify the upstream source, read registered baseboard pending bits, intersect with enabled/registered slots, preserve kernel/caller maps and invoke the correct bounded module callback for each selected slot. When both baseboards share one upstream source, read both boards; separate routes can address only the appropriate board. Use bounded rotating slot/board service order, recapture pending status as needed, and schedule continued work rather than spinning indefinitely in an interrupt handler.

Before successful device initialization and callback publication, keep that slot's interrupt contribution disabled. Publish its registry entry/callback before enabling the source. Because modules are retained until reboot, normal close/process exit does not remove callbacks. A load failure must leave the slot disabled and quiesce the hardware before releasing reachable code/state/buffers.

An unregistered slot or an acknowledged device fault must not monopolize CPU interrupt entry. Recommended response is to mask its contribution, record bounded diagnostics and mark the affected device unavailable until controlled recovery. Repeated assertion alone does not prove a fault: a healthy busy device can retain work. Use bounded service and, where needed, temporary masking plus deferred work, then re-enable/recheck without losing pending events. Exact service budgets, timeout/fault thresholds and recovery policy remain engineering work or proposals. If completed hardware changes the mask capability, revisit interrupt-storm and deferred-work handling before relying on the current dispatch model.

All pending-register reads are permitted under the accepted hardware read policy, but ordinary applications continue to use OS APIs. IRQ_ENABLE and device-acknowledgement writes require privileged entry. The fixed ROM IRQ-to-SWI bridge remains necessary when the dispatch needs bank mapping or device writes. A non-clearing status read alone needs no privilege and must not change the mode latch.

The accepted module/loader direction can be specified independently of future card IDs: configuration supplies board/slot/driver binding and the pending register supplies interrupt selection. ID/EEPROM enumeration is not required. The working pending/mask behavior is now selected; actual offsets, routing and final hardware timing remain to be confirmed.

Recommended adaptation boundary: only an OS backplane/controller layer knows the physical pending/mask offsets, register polarity and source routing. It exposes normalized pending-slot and enable-mask operations to kernel dispatch. Card modules use their supplied card I/O resources and per-instance context rather than directly manipulating backplane-global registers. Keep controller configuration/implementation versioned so a final hardware change is localized to that layer and its dispatch validation; do not assume every semantic change can be hidden without revisiting the OS contract.

Agreed module/instance separation: load one code image per driver implementation and instantiate separate per-card records, I/O bindings, mutable state, request progress and buffers for multiple compatible cards. This avoids duplicating a 16 KiB code-bank allocation for each identical card. Each callback and completion identifies its instance; do not encode the active board/card in module-global mutable variables or share a writable transfer buffer implicitly between cards. Separate state/buffer allocations count toward admission, and code retention until reboot applies independently of client handles. Shared code does not imply unguarded reentrancy: per-instance synchronization, mappings and interrupt entry remain implementation work. This is logical code/state separation, not a requirement that every small state record consume its own full physical bank.

### 11.4. Shared driver code and per-card instances — agreed; entry/state ABI pending

The user explicitly requires support for several identical cards and separation of driver code from their state/buffers. One retained module contains executable code, entry metadata and immutable tables. Each physical card binding owns its board/slot resources, mutable controller state, buffers, outstanding work, completion/timeout accounting and IRQ subscription. Allocate and account these instance resources through MLOS, separately from the shared code image. A multi-function card may also expose several device endpoints beneath its controller instance; endpoint naming/state layout remains to be specified.

Binding another compatible card reuses the module image and admits a new instance, rather than overwriting the first card's state or loading another copy solely to obtain different globals. If the second instance cannot allocate required resources or initialize successfully, quiesce/roll back only that unpublished instance. Keep the first instance and its registered callbacks intact. Identify module implementation/version compatibility before reusing an image; an identical device class does not guarantee that different controller hardware uses the same module.

The entry ABI must provide an explicit instance context/resource description for initialization, request submission/progress, interrupt handling, controls and shutdown/error quiescence. The common dispatcher maps the correct module and instance backing before use; saved callbacks refer to module identity/entry offset plus instance identity, not an unqualified virtual function/data pointer. Exact native register/CMOC calling convention and state-buffer window layout remain engineering work.

Driver state must not rely on a single module-global current-card, buffer cursor or saved request pointer. Requests/completions refer to their own device/instance generation, preserving already agreed stale-reference checks. Mutable controller access is serialized at the required per-instance granularity; a long operation on one card must not hold a module-global lock or polling loop that stalls another card or the OS. Shared immutable tables are safe to reuse. Short module-global management updates, if any, must still obey bounded kernel critical-section rules.

Successful modules remain resident until reboot. Registered instance state remains valid while its device/callback is published; ordinary application close/exit releases client/request references rather than destroying the hardware instance. Per-request buffers are released only after completion or safe cancellation, respecting hardware/DMA references. Instance size, baseline buffer needs and configurable transfer capacity must be declared sufficiently early for admission; detailed metadata and optional buffer growth remain to be specified.

Agreed device-interface policy: raw devices are exclusively owned by a service, and that service serves many clients. Ordinary clients use the service's logical endpoints/operations rather than acquire or share its raw device handle. The service controls configuration, input consumption, command sequencing and class-specific client sharing. This leaves MLFS regular-file shared-reader/exclusive-writer rules unchanged. Internal block-service references for multiple mounted partitions are not competing raw application owners; existing mount/raw-write lifetime protections remain. Section 11.5 specifies the ownership/lifetime direction.

### 11.5. Exclusive service ownership of raw devices — agreed; claim/recovery ABI pending

The user confirms that raw devices are exclusive to a service, while the service supplies data/access to many clients. Separate three identities: the retained driver module (shared code), its per-card/device instance (hardware state/buffers), and the owner service process (exclusive raw-device access). Neither an ordinary client handle nor service exit unloads the retained module automatically.

An exposed raw device has one current service owner. Bind its ownership record to the service process generation and a raw-device claim/handle generation, so reused process/handle numbers cannot inherit an old lease. Reject a competing mediated raw claim with BUSY. Every raw operation uses the owner's live handle; ordinary clients use the named service's per-client channels or the appropriate logical descriptor provider. This is lifecycle/resource correctness in a single-user system, not a new user-account authorization scheme. Physical raw reads remain unrestricted by the selected hardware policy.

A card/controller can expose more than one device endpoint, such as independent UART channels or disks behind one controller. The precise raw endpoint boundaries must follow which hardware state can be owned independently. The kernel module still coordinates shared controller resources; an owner of one endpoint must not reset or mask unrelated endpoints on the same card. Exposing separate raw endpoints must not hand conflicting controller-global configuration to multiple services.

Services implement device-class sharing: the filesystem serves multiple clients/files/partitions through its block-device ownership, an ADC service routes samples and arbitrates configuration, a printer service orders jobs/output, and a modem/network service owns link/session/protocol state. Use the existing private client-channel pairs and multi-channel waiting where applicable; do not change copied SPSC channels into an unimplemented shared multi-producer queue. Client admission, buffering, fairness and overflow policies remain bounded and class-specific. Printer spooling persistence, ADC subscription/rate policy and network protocols are not selected by this ownership decision.

Service death removes its registration, closes/notifies its client connections under the existing drain/no-auto-reconnect policy, revokes further raw submissions and requests safe cancellation/quiescence of its pending device work. Retain request/buffer/hardware references until no in-flight operation can use them. Release or transfer the exclusive claim only after the required safe point; if quiescence fails, keep the device unavailable and do not admit a new owner over active stale work. Device instance/code residency follows the agreed driver lifetime, independently of those client/owner references.

A replacement owner needs an explicit fresh claim and controller-specific reconciliation/initialization; it must not receive old-owner callbacks or completion records, or silently inherit existing client sessions. Existing MLFS failure/manual-recovery, GUI teardown/fallback and named-service reconnection rules remain in force. Exact raw claim/close/control calls, cancellation completion and failure reporting are engineering work; no blanket automatic service restart policy is introduced.

Agreed service-topology case: the user confirms one filesystem service must be able to handle several drives, each with its own raw claim and driver-instance/device reference. This preserves one exclusive owner per raw device. The raw claim registry must allow multiple device records to identify the same owner service. Other services can be designed around the same structure; their specific multi-device requirements/protocols are not selected by this filesystem decision. Section 11.6 records the multi-drive filesystem direction.

### 11.6. One filesystem service, several drives — agreed; dispatch/recovery details pending

The user confirms one filesystem service should handle several drives. It may claim CF and additional disk/IDE raw endpoints through their respective kernel modules; one shared module may serve compatible controllers, and different module implementations can serve different hardware. Raw ownership remains exclusive per device, not limited to one device per service.

Maintain distinct records for each block device and its geometry/error/request state, for each mounted partition/volume, and for each open file. Route the agreed pathname namespace through the mount/device association; per-process cwd and MLFS shared-reader/exclusive-writer rules remain unchanged. Separate drive identity, partition identity and mount generation so an identical partition index or LBA on two drives cannot alias. Cache and metadata-lock keys must include the full device/volume identity, not a bare sector number. The existing “up to 16 partitions” source observation does not by itself define a system-wide versus per-drive service limit; target context/format limits need explicit audit.

The service's memory budget includes all active drive/volume contexts, handles, queues and bounded cache/transfer buffers. Admission must fail cleanly when resources are exhausted; extra drives do not imply unbounded cache growth or swapping. Native device sector size and MLFS filesystem block size remain separate geometry fields; initial 512-byte filesystem-block support and the desired 4 KiB extension are unchanged.

Proposed scheduling direction: interleave admitted requests across drives/volumes, keep a bounded amount of each volume's work in progress and preserve serialization of conflicting metadata. A driver request may be pending while the service processes another device's request. Shared-controller operations still obey the controller driver's own serialization. Port/adapt the current MLFS synchronous call chain as needed; merely placing blocking calls in one process would still stall that service's other clients. Precise request states, volume reentrancy and fairness budgets are engineering work, not tested behavior.

Agreed failure scope:

- The user agrees a diagnosed drive/controller failure makes only its affected drive(s)/volumes unavailable; unrelated healthy drives and virtual diagnostics remain accessible. Preserve each healthy volume's existing access mode, including writes where otherwise allowed. A controller failure may affect several attached drives. An individual request timeout/error must be classified before declaring a whole drive unavailable; exact thresholds are engineering work.
- Fail/complete affected client requests, reject new operations on the unavailable device and retain hardware/buffer references until safe quiescence. Leave affected mounts explicitly unavailable rather than silently falling through to an underlying directory or another drive; allow safe handle cleanup and preserve mount-identity/lifetime rules.
- Do not replay unfinished writes or auto-remount writable storage over uncertain metadata. Explicit recovery validates the affected storage under the already agreed interrupted-write policy. Parameter/resource errors are not themselves proof of a failed drive.
- A crash of the filesystem service itself still disables all filesystem work owned by that service, not just the last drive it touched. Follow the existing client notification/manual-recovery/reset policy; /proc and emergency serial diagnostics retain their independently agreed paths.
- A CPU/memory fault in a trusted kernel driver remains a kernel/core fault under the existing policy. Logical per-drive state separation is not hardware driver-crash isolation.

Local drive/controller-failure isolation is now agreed. Filesystem-service and trusted kernel-driver crash rules remain broader as described above. Detection, cancellation/quiescence, bounded cross-drive progress and explicit recovery mechanics still need implementation/validation; no successful multi-drive MLFS run or target recovery test is claimed.

Agreed recovery handle policy: the user confirms that any application that loses a handle must request a new one. A recovered volume does not revive its old file handles. Revalidate/reinitialize storage under the existing conservative policy and give any restored mount/device context a fresh generation after safe cleanup. Old handles remain failed/stale and can be released; applications explicitly reopen files to obtain new handles. They must not silently refer to changed media or a rebuilt filesystem, and old-generation completions must not be redirected to new requests.

Apply the same no-automatic-rebinding principle to other lost/revoked OS handles, consistently with the existing named-service no-auto-reconnect rule. This does not make every peer closure an immediate invalid-handle event: the agreed IPC consumer can still drain its retained buffer, then receive normal end-of-stream. Previously completed application data/results are not retroactively reassigned to a new resource generation. Exact token/generation widths and descriptor-reuse semantics remain ABI work.

Recommended error/cleanup convention: subsequent operations on an invalidated file handle report a distinct stale/invalid-handle error, rather than an ordinary zero-byte EOF. Handle-release/close must still permit local cleanup without issuing new I/O to the failed/replacement volume; hardware/request references remain retained until safe cancellation/quiescence. Numeric error codes, partial-operation reporting and close-result details remain to be specified. Existing BUSY rules still require live references to be dealt with before ordinary unmount, and no automatic forced-unmount variant is selected.

Agreed current-directory failure policy: if a process's cwd refers to an unavailable or replaced volume generation, keep the process alive but mark that cwd unusable for new relative-path operations. Require explicit chdir to a valid absolute path on an accessible mount. Do not silently reset it to root or rebind it when the volume returns; the application's explicit chdir obtains the fresh directory reference under the accepted lost-handle rule. Absolute access to healthy mounted paths remains available, including the absolute chdir used for recovery.

Implementation must preserve those semantics in mount dispatch, cwd generations and reference cleanup: recovering a volume alone cannot make old relative-path resolution valid again. Ordinary unmount BUSY rules and safe release of invalid references remain distinct from volume failure marking/recovery; no forced-unmount policy is introduced. Exact invalid-cwd error codes, getcwd/prompt reporting, child launch with an invalid inherited cwd and recovery/unmount sequencing remain ABI/implementation details to specify. No successful target implementation is implied.

## 12. Implementation work and open decisions

1. Finalize the fixed upper 8 KiB common-RAM budget and reserve its physical frame.
2. Specify the agreed resident/resource/uncommitted roles in executable headers and mapping checks; define map/unmap/free semantics, stale-handle checks, and future synchronization between threads sharing a process map.
3. Specify the agreed copied IPC API, payload-capacity accounting, stream/message record representation, multi-channel readiness/deadlines, and small-receive-buffer result. Define arbitrary-size allocation/indexing, EOF/peer-death reporting, and reclamation mechanics under the agreed no-timeout rule.
4. Specify executable header bytes and resident/resource window declarations for the up-to-three-bank loader; use the agreed initial fixed linking model and plan later relocatable loading. Define the exact logical image/stack layout.
5. Specify the agreed builtin/foreground-command split, executable loading, arguments, exit status, and standard I/O inheritance; implement the agreed Unix-style namespace and per-process current directories; specify filesystem dispatch and implement the agreed /proc and mount/directory lifetime policies in sections 7.1–7.2. Implement the agreed standard descriptor I/O, ordinary-file growth, and explicit launch inheritance in sections 7.3 and 10.8; specify their detailed ABI and writable-handle handoff.
6. Assign separate UART channels to logs and interactive console; implement the agreed foreground-input and bounded log-overflow policies in sections 8.1–8.2, and implement the agreed line/raw input modes and settings restoration in section 8.3.
7. Define CMOC runtime integration and bounded MLFS buffering for initial 512-byte blocks and the desired 4 KiB extension.
8. Specify redraw/refresh targets, the Swedish PS/2 keymap and Latin-1 glyph/control handling, and GUI API details.
9. Complete and verify ROM IRQ/SWI/trap entry and return paths, nesting, gate state, and banked user-memory access.
10. Specify the agreed temporary CF-transfer facility with predeclared size: spool cleanup across sessions, agreed sequential exact-length finalization, wide offsets, zero-length semantics, and reference reclamation.
11. Specify the agreed init/startup, GUI launch, and foreground cancellation policies; implement the agreed init, shell, and core-service failure policies; preserve the agreed virtual diagnostic availability under MLFS failure in section 7.2.
12. Measure the agreed bank-0 core budget, implement controlled extension mapping if needed, and validate/tune the 1 kHz tick, 5 ms quantum, and 4:2:1 priority shares.
13. Verify the selected serial timer's mode/preload and shared IRQ acknowledgement against the confirmed 3.6864 MHz crystal; audit GAL vector-decode equations and timing. Implement the agreed service-failure policies.
14. Implement the agreed SWI register/result convention, CMOC wrappers, and fixed stack reservations; define precise CC effects, native frame handling, kernel/user DP, and mode-register/trap-status conventions. Implement agreed automatic heap growth and safe empty-bank reclamation; implement the agreed discard-bank mapping and cross-window ordinary allocations in sections 10.6–10.7.

15. Implement the agreed named-service rendezvous direction in section 6.2 and define admission, acceptance, cancellation, and service-instance cleanup.
16. Implement the agreed initial shell arguments/redirection scope in section 10.9 and sequential exact-length CF-transfer behavior in section 6.1.
17. Implement the agreed initial terminal control/profile and key-decoding direction without scrollback; plan later colour ANSI support under section 8.4. Specify actual geometry/resize handling, bounded parser behavior, and whether to add an alternate screen buffer.
18. Implement agreed click focus/capture, application-owned redraw content, and bounded GUI event-pressure/disconnection policies in section 8.5.
19. Implement the agreed close/force-quit and hosted-terminal scope cleanup, negotiated resize, and shared keyboard translation in section 8.6. Specify protocol commit/abort rules and distinguish native GUI keys from TTY byte input.
20. Implement agreed modal-window capability, owner-window/application-wide scope, nested routing, teardown/focus restoration, and event-loop/activation barriers in section 8.7.
21. Implement agreed optional asynchronous GUI descriptor/storage I/O under section 8.8, and define bounded buffers, operation tokens, completion delivery, and cancellation.
22. Implement agreed configurable UART A interactive/B log assignments and the interrupted-write mount/repair policy in section 7.4.
23. Implement the agreed whole common-frame reservation/initial frame numbers, read-only MLFS bootstrap convention, and measured first kernel milestone in section 14. Finalize the boot-image/boot-information ABI and ROM transition contract first.
24. Implement the pending GAL/PLD equations for SWI/NMI/reset unlock and F405 relock against the identified stage-3 U26/U27/U23 routing. Reconcile the schematic-note gaps in section 5.2: NMI decode, absent reset input, mode-qualified /MEM_WR and all-device write paths while preserving reads/RAM writes, internal mode polarity, and retained-state PROT_STATE wiring. Implement ignored-write denial and the agreed bit-7 status in both modes, with reliable bus driving and lower-bit-independent callers; derive the cycle-qualified signal/routing/fit solution, implement the agreed application read-API convention and resolve driver/nesting details in section 5.3 and the proposed reserved-NMI policy in section 5.4. Confirm installed parts, feedback/macrocell configuration and fit; specify phase/reset/nesting under section 5.1 and verify simulator and physical hardware behavior.

25. Specify the accepted banked trusted-driver entry/import/buffer ABI, CF boot/console loader and retention-until-reboot lifecycle in section 11.1, using fixed slots and the confirmed slot-2 correction. Finalize explicit binding configuration; keep ID/EEPROM discovery deferred. Implement against the provisionally agreed pending/mask contract in section 11.3, keeping a controller-adaptation boundary for final hardware changes and confirming offsets/routing/timing; implement the agreed shared-code/separate-state driver instances, specify device classes and /dev controls, the agreed exclusive service-owned raw-device claims in section 11.5, the multi-drive filesystem contexts/dispatch and agreed local device-failure isolation in section 11.6, including classification, safe quiescence and the agreed explicit recovery/fresh-handle and invalid-cwd/absolute-chdir rules, with remaining close/error/getcwd/launch semantics, and pending-request/callback lifetime. Card controllers, rates, sector/data widths, FIFO sizes and DMA remain hardware requirements to collect.

## 13. Architecture checkpoint — planning review

The current requirements describe the console/GUI product, preemptive process ownership, kernel-mediated banking/allocation, copied SPSC IPC and temporary CF handoff, mounted MLFS/virtual status views, terminal behavior, and separate window-manager focus/redraw/modal/failure policies. This is sufficient to begin detailed interface and bring-up planning, not evidence of an implemented system.

Most entries in section 12 are concrete specification/implementation tasks rather than unsettled product choices. The asynchronous GUI I/O direction, interrupted-write mount policy, and UART assignments are now agreed. The physical reservations, read-only MLFS bootstrap direction, and first measured kernel milestone in section 14 are now agreed. The board provisions an I/O privilege gate, now intended to cover all I/O writes with unrestricted reads and readable mode status, while its GAL logic is a pending hardware/firmware deliverable; simulator and software results cannot close the hardware-gate criterion. Their exact ABI/addresses and target implementation are still pending. Trusted banked expansion-driver modules, CF boot/console loading and retention until reboot are now accepted, and the baseboard will provide a pending-slot register. The pending/mask contract is now provisionally agreed and may change with final hardware. Raw devices are now exclusively service-owned, with services providing many-client access; one filesystem service can own several drives and keep healthy volumes accessible after an unrelated drive/controller failure. Driver ABI, device namespace/claim ABI, the agreed shared-code/separate-state instance ABI and concrete controller offsets/routing/timing still need specification before controller-specific implementation. Earlier unresolved details, including alternate-screen behavior, zero-length transfers, and exact ABI/driver protocols, remain identified in their sections.

The agreed common-RAM reservation plus core bank and discard bank reserve three 16 KiB physical frames: 48 KiB of a 512 KiB machine. The other 29 frames/464 KiB must also hold all service/application banks, IPC backing, caches, logs, and metadata; they are not all application heap. Actual code, stack, and bookkeeping budgets have not been measured. The full common-frame reservation and initial bank numbers are adopted in sections 3 and 14.1.

Before claiming target feasibility, verify native ROM entry/exit and the actual GAL gate, measure the bank-0/common-RAM budgets and scheduling overhead, integrate bounded CF progress and MLFS growth/recovery, and audit simulator graphics behavior. Current MMU gating/common mapping/discard-bank rules do not establish general memory protection. No source-inspection result or accepted GUI policy substitutes for those hardware/implementation checks.

## 14. First kernel milestone — agreed; detailed implementation pending

### 14.1. Physical reservations

Agreed: reserve physical bank 0 for the core, bank 1 for the fixed common-RAM frame, and bank 2 for the shared discard frame. The common window exposes only 8 KiB, but initially its full 16 KiB frame is reserved, as agreed in section 3. Bank numbers 1 and 2 are a deterministic initial convention, not application-visible allocation promises. No ordinary allocator may return these frames. In the minimum 512 KiB configuration, this leaves 29 physical frames for everything else before service, IPC, cache, and metadata admission.

Finalize common-RAM addresses and a measured budget for entry state, kernel/emergency stacks, mapping/context records, scheduler/wait metadata, and bounded device buffers before code expansion. Test programs use separately admitted physical frames and the agreed logical layouts. Allocation failure must not partially publish a process or consume a frame permanently.

The whole-frame reservation and initial physical numbering are adopted. Exact common-RAM allocation/addresses and measured capacity still require implementation.

### 14.2. Read-only MLFS bootstrap

Current source inspection: BOOT_MLOS_UTIL in bios/src/mlbios.asm reads LBA 0 into STORAGE_BUFFER_START and jumps into that buffer. The project's MLFS_BOOTLOADER_FORMAT notes instead place MLPT at LBA 0 and describe locating /mlos.bin through partition/superblock/root-directory reads. These are incompatible conventions for the same sector. The source is a stub, not an implemented MLFS kernel loader. Its existence does not demonstrate boot validation.

Agreed: retain MLPT at LBA 0 and implement a small read-only ROM loader. Select an explicitly designated MLFS boot partition (initial agreed label: boot), require supported 512-byte MLFS blocks initially, and find the regular root file mlos.bin. Require a single extent with no indirect extents for the first kernel image; ordinary runtime files retain their separately planned growth/extent capabilities. Missing/unsupported/corrupt images return to serial BIOS diagnostics/monitor without executing unvalidated payload.

Agreed direction: a small versioned kernel boot-image header with magic, payload length, entry offset, and integrity check, with the exact encoding/checksum and boot-information record specified before implementation. The initial core payload must fit physical bank 0 and its validated entry range. Kernel payload links for its agreed logical bank-0 execution addresses, not the documentation's older $8000 skeleton address. Header bytes and common-RAM initialization must not overwrite executable code, ROM entry state, or live boot stacks. Additional kernel code banks remain a future supported extension after the core path works.

Validate partition versions/counts, device/partition/extent bounds, supported block size, root and file ranges, overflow in LBA arithmetic, payload length, entry point, and image integrity. Read only the declared payload; do not load all reserved extent capacity. A structural/checksum check does not establish cryptographic authenticity or full filesystem health. The interrupted-write policy in section 7.4 still applies; full writable mounting/recovery occurs through the runtime filesystem work. Preserve enough ROM/common-RAM state for safe load-failure diagnostics.

Inspecting a clean test CF image and deliberately malformed copies is required; never use a user's ordinary-data image for destructive fault injection. No target boot test or image modification has been performed in this planning work.

These partition/file/header directions are adopted; precise header fields/encoding, integrity algorithm, loader bounds handling, and boot-information records remain to be specified. BIOS source and image tooling will need deliberate changes; no backwards compatibility is required by the user.

### 14.3. Bring-up sequence and pass evidence

Agreed: the first milestone is banked-kernel/preemption bring-up with a serial diagnostic interface. First verify ROM/native entry and MMU gating using a small harness, then boot the core through the read-only MLFS loader, and run two tiny diagnostic processes in distinct private banks. Embed or otherwise supply those controlled test images without requiring the full application filesystem service or shell to be finished first. Console shell, general file services, IPC feature completeness, and GUI follow as later milestones.

| Area | Required evidence for this milestone |
| --- | --- |
| Boot | Valid kernel image starts from CF; missing, malformed, oversized, and out-of-range images produce bounded serial diagnostics without a bad jump. |
| Entry/exit | Native CPU state, application S and mappings survive SWI/yield/IRQ return; kernel bank 0 and common stacks are entered safely. |
| Gate | Pending GAL logic is implemented against stage-3 wiring; actual vector qualification, ignored I/O writes, normal side-effecting reads in both modes, normal RAM writes, mapping readback, bit-7 mode-status behavior independent of unspecified lower bits and F405 relock are checked on hardware; read-based timer acknowledgement, necessary write/mapping SWI bridges and nested privileged transactions are exercised. Simulator checks are separate evidence. |
| Isolation of maps | Two processes use the same logical addresses with different physical backing and retain their own sentinel data. This tests mapping correctness, not general memory protection. |
| Scheduling | Timer-driven preemption continues when a test process does not yield; explicit yield also works. Measure actual tick period, quantum, and entry/switch cost at the target CPU clock. |
| Fault and lifetime | A controlled application trap is logged and terminates that process; its resources are safely reclaimed and the survivor continues. Core faults follow the existing emergency policy. |
| Resource failure | Exhaustion/rejected launch has no partial live process or leaked frame. Reserved frames remain excluded from allocation. |
| Budget | Record linked core size, common-RAM occupancy, stack high-water/headroom observations, and physical-frame accounting. |

Counters and trace capture must be bounded; diagnostic logging must not dominate the scheduling measurement. Test expected register/stack/map state and termination records, not only visible blinking/output. Record simulator and physical-board results separately. Actual native frame details, low-level calling conventions, and target observations are prerequisites for claiming success.

This milestone and pass-evidence direction are adopted; nothing in this section reports implemented code or successful tests.

### 14.4. Bring-up while gate logic is pending

The agreed final milestone still includes the programmed hardware gate and its measured behavior. Development can proceed in stages: first exercise banked ROM entry/context/scheduling on the simulator's existing mapping path; add the intended gate state model and failure/nesting tests; implement the board's GAL logic and run a small vector/I/O/map/status/relock harness; then complete integrated CF boot and physical-board milestone checks. This is development ordering, not removal of the agreed gate requirement.

Specify the GAL contract and software ROM transitions together. Use the observed stage-3 GAL families and routing in section 5.2, then confirm installed part/speed grades, macrocell configuration/fit, reset behavior and bus phase before programming device-specific logic. No physical bypass or provisional programmed state is assumed safe without checking the board. Simulator behavior with enforcement disabled is useful for software bring-up but is not evidence that restricted I/O writes, unrestricted reads or mapping writes work.

## 15. Decision history

Entries record what was settled or proposed at each past revision. Current status is defined by the main sections and the baseline summary above.

Settled in revision 0.2: timer via IRQ with no application interrupt-mask handling initially; brief kernel critical sections; application-managed banked resource contents with kernel-mediated mapping; drain-before-discard; BUSY on conflicting opens; small executable header; separate output-only logs and interactive-console functions; GUI-session descendant cleanup.

Settled in revision 0.3: support up to 48 KiB application footprints; assembly/CMOC implementation split; initial single-producer/single-consumer buffers; retain draining data until consumed or consumer exit with no timeout; separate UART channels; initial 512-byte MLFS blocks with up-to-4-KiB support desired; Swedish keyboard and an 8-bit ASCII-compatible Nordic character set. Window roles and the exact extended character table remain proposals.

Settled in revision 0.4: resident/resource/uncommitted window roles; OS maintenance of all IPC resources; Latin-1 encoding and case-sensitive filenames. Kernel-mediated copied IPC is recommended to preserve access for 48 KiB resident applications, but remains a proposal pending the user's choice.

Settled in revision 0.5: kernel-mediated copied IPC initially; optional direct mapping deferred; byte-stream or message mode selected at channel creation; streams for terminal traffic and messages for GUI commands/events; all-or-nothing message sends. Blocking defaults, sizing, endpoint admission, and detailed receive/error semantics remain open.

Settled in revision 0.6: blocking IPC by default with explicit nonblocking operations; capacity fixed at initialization, default 512 bytes, arbitrary requested sizes from one byte subject to available memory and representability; attachment by name without creator authorization. Kernel endpoint/handle/lifecycle checks remain required. Payload-only capacity accounting and multi-channel waiting are proposals pending confirmation.

Settled in revision 0.7: requested IPC capacity counts usable payload, with metadata additional; undersized message receives report the required length without consuming the message; wait_any-style multi-channel waiting supports an optional timeout. CF-backed completed-file handoff is a new proposal awaiting adoption.

Settled in revision 0.8: all IPC is temporary, including CF-backed bulk transfers; no delivery or transfer identifiers survive reboot; CF transfers declare their size and preallocate backing storage. Boot cleanup must reclaim identifiable old transfer files after safe mounting. Init/startup, foreground command isolation, and Ctrl-C behavior are the next proposals.

Settled in revision 0.9: init starts core services and the serial shell; console is the initial default with a command to start GUI and later configurable automatic GUI launch; shell state changes are builtins and other commands run as isolated foreground processes while the shell waits; Ctrl-C requests kernel-managed foreground termination with safe pending-operation cleanup. Core-kernel budget/overflow policy, a five-tick initial quantum, and weighted priority classes are new proposals awaiting adoption.

Settled in revision 0.10: target the core at physical bank 0 with additional kernel code banks allowed if needed; OS services use separate process banks; initially test a configurable 1 kHz tick with 5 ms quantum and interactive/service, normal, background classes using configurable 4:2:1 weighted dispatch shares. Timer and GAL entry-detection facts and service-failure policy are the next open items.

Settled in revision 0.11: use the XR88C92 serial timer through IRQ; GAL detects vector fetch from BA/BS and low address bits; shell restarts once with safe foreground cleanup, MLFS failure disables file operations pending manual recovery/reset, and init/core-kernel failure reports to emergency serial and halts. Existing SWI/NMI/reset unlock policy and IRQ/trap SWI bridges remain. UART clock details, GAL equations/timing, and fixed native-mode ABI remain open.

Settled in revision 0.12: UART crystal is 3.6864 MHz; HD6309 native mode remains fixed during normal MLOS/application execution, with mode-control settings owned by the OS. Timer preload $0073, syscall register conventions, and fixed stacks with a 1 KiB default are new proposals awaiting adoption. Datasheet analysis predicts 25 Hz for the existing test's purported 50 Hz configuration; target verification is required.

Settled in revision 0.13: initial timer mode crystal/16 with fixed preload $0073 and time conversion from its configured period; plain SWI calls with A as call number, X as optional parameter-block pointer, D as result/error, carry as success/failure, other registers preserved, and CMOC wrappers; fixed executable-declared application stacks, initially 1 KiB by default, without automatic stack growth and with separate kernel stacks. All require implementation and target validation. Fixed linked executable addresses, automatic heap growth into uncommitted windows, and retaining resident heap banks until exit are the next proposals, not yet adopted.

Settled in revision 0.14: fixed linked logical images initially, with relocatable loading preferred later; automatic malloc growth into eligible uncommitted windows; automatically return completely empty private heap banks to the physical free pool after safe reference withdrawal and mapping revocation. The earlier proposal to retain empty heap banks until exit is rejected. Real GAL support for disabling vacant windows, a possible reserved discard bank, and allocations spanning logical bank boundaries are the next questions.

Settled in revision 0.15: the GAL cannot disable individual memory windows. Clarified that all banks backing a live spanning ordinary allocation must occupy their assigned logical windows whenever the owning process runs, with normal process preemption and map restoration still possible. The discard-bank fallback and the choice between single-bank allocations initially or cross-window ordinary allocations remain proposals awaiting adoption.

Settled in revision 0.16: support ordinary malloc allocations spanning adjacent eligible resident logical windows; all covered physical banks stay allocated and their mappings are restored whenever the owning process runs. Reserve one shared 16 KiB physical discard bank for vacant windows. Physical backing and contiguous logical space both constrain allocation admission; ordinary allocations remain bounded by the application's mapped address space. The proposed initial single-bank allocation limit is not adopted.

Settled in revision 0.17: Unix-style mounted path namespace, including planned virtual filesystems such as /proc for process status; each process owns a current working directory inherited by launched children. Exact default mount paths and dispatch structures remain to be specified. Initial read-only /proc views with open-time status snapshots, BUSY on directory changes invalidating active references, and BUSY on unmount while a backend is in use are new proposals awaiting adoption.

Settled in revision 0.18: initial read-only /proc status/memory/mount views with open-time process-status snapshots independent of CF/MLFS, without retaining the subject's private banks; BUSY on directory changes invalidating active references; BUSY on unmount while current directories, descriptors, I/O, or retained CF transfers use the backend, with no forced variant initially. Standard byte-oriented descriptor I/O, explicit process launch inheritance, and ordinary-file growth are the next proposals.

Settled in revision 0.19: process-local standard descriptors 0/1/2 and byte-oriented read/write/close for files, terminals, and RAM streams, with dedicated complete-message operations; direct spawn with controlled inheritance of current directory, session, and standard-I/O destinations and explicit additional handles; ordinary files grow on write subject to storage/format/resource limits, while temporary CF transfers keep their fixed predeclared capacity. Named service connections, foreground terminal input ownership, and bounded serial-log overflow are the next proposals.

Settled in revision 0.20: named service listeners establish private one-way channel pairs per client, preserving SPSC data paths, with explicit admission failures and service-death notification and no automatic reconnection; one foreground input owner per logical terminal, background terminal reads return NOT_FOREGROUND, and unread input stays with the terminal across handoff; serial logging uses a bounded nonblocking ring that discards oldest complete records and reports loss. Line/raw terminal modes with restoration, initial shell arguments/redirection scope, and sequential exact-length CF finalization are the next proposals.

Settled in revision 0.21: default edited/echoed line input and explicitly requested raw input with automatic shell-setting restoration on exit/fault; Ctrl-C retains foreground termination in both modes; initial shell supports quoted arguments and < / > redirection with exclusive child-owned output and create/truncate behavior while pipelines, background syntax, append, expansion, and substitution are deferred; temporary CF transfers are sequential and exact-length, incomplete finalization cannot publish, and excess writes fail. Terminal control profile, cell-model/history scope, and shared escape-key decoding are the next proposals.

Settled in revision 0.22: the initial monochrome terminal control subset is accepted with colour ANSI support desired later; no scrollback history is needed; consistent serial/GUI special-key encoding and shared decoding with a configurable Escape delay around 40 ms are accepted as a starting direction. Colour representation is a future extension, not frozen by the initial cell byte layout. The separate alternate-screen proposal is not explicitly settled. GUI focus/capture, application-owned content redraw, and bounded event-backlog disconnection are the next proposals.

Settled in revision 0.23: click-to-focus/raise and mouse capture through release; explicit focus events; application-owned content reconstruction with manager-owned decorations/stacking/clipping; nonblocking per-client GUI event delivery, coalescing, and bounded essential-event backlogs; disconnect and remove windows on backlog exhaustion while leaving the process to observe closure and choose its subsequent lifetime. Closing/force-quit, terminal scope cleanup, negotiated resize, and shared keyboard translation are the next proposals.

Settled in revision 0.24: cooperative close requests and explicit kernel-managed force-quit; hosted-terminal shell/job cleanup with an owned terminal scope; negotiated resizing with old geometry retained on rejection/nonresponse; shared Swedish/Latin-1 keyboard translation with native GUI key/state/text events and terminal byte-stream conversion. Modal-window support is a new requirement. Owner-window default, optional application-wide scope, nesting, and lifetime/focus rules are next proposals, not yet selected.

Settled in revision 0.25: owner-window default and optional application-wide modality, nested modal routing, owner/child cleanup, and focus restoration without stealing focus from another active application. The GUI modality policies are now agreed; activation fencing, records, and event sequencing remain implementation work. Consistency review identifies optional asynchronous GUI I/O as a next proposal so synchronous CF waits do not exhaust a healthy client's event backlog. UART assignments and interrupted-write boot policy remain open.

Settled in revision 0.26: optional asynchronous GUI I/O with completion delivery while blocking calls remain for simple console programs; after interrupted writes, validate before writable mount and keep suspect volumes read-only where safe or unmounted until explicit repair; configurable UART A interactive console and UART B output-only logs. A source audit finds a mismatch between the current sector-zero jump stub and the documented MLPT sector-zero layout. Whole-frame common reservation, the read-only MLFS kernel bootstrap convention, and a first measured bring-up milestone are next proposals.

Settled in revision 0.27: reserve physical bank 0 core, bank 1 whole common frame, and bank 2 discard frame; adopt a read-only ROM bootstrap using MLPT and a designated boot partition's root mlos.bin, initially 512-byte filesystem blocks and one extent, with a validated versioned kernel image; adopt the first serial/two-process banked-kernel bring-up milestone and its measured pass-evidence direction. Exact image/context/memory ABI and actual hardware gate validation remain engineering work. A baseline summary and consolidated decision history separate settled policy from old proposals.

Settled in revision 0.28: the user confirms the board provisions the vector-unlock/F405-relock mechanism, but the GAL logic is not yet implemented. Treat that logic as a pending hardware/firmware deliverable, retain the agreed observable behavior and hardware milestone requirement, and develop simulator/software entry paths while specifying the actual target part/pins/phase/reset behavior. No existing source or simulator pass is claimed to implement the new gate.

Recorded in revision 0.29: the user identifies motherboard-stage3 as the current target. Source inspection confirms U26/U23 GAL22V10, U27 GAL16V8, ENTER_PROT/EXIT_PROT/PROT_MODE wiring and the direct /MEM_WR path to both map-storage chips. Schematic notes omit the NMI entry match, refer to an unwired reset input, omit a mode term from map-write enable, and do not define a retained-state readback bit. These are pending implementation reconciliations; recommended mode polarity and any wider U23 protection remain proposals. No GAL programming or hardware test occurred.

Settled in revision 0.30: U23's mode input is intended to enforce protected mode for all I/O operations, and F405 mode-status readback is intended. This supersedes the MMU-write-only scope. Locked-mode IRQ handlers must establish privilege before timer/peripheral acknowledgement. Status accessibility/polarity, denied-I/O bus semantics and kernel-mediated versus trusted-service driver placement remain proposed details; no new unlock source or RAM protection is selected. GAL logic and validation remain pending.

Settled in revision 0.31: the user revises protection to all I/O writes only; all reads execute normally, with keyboard/read-side-effect interference explicitly accepted. Unprivileged writes are ignored without a new fault. The user reaffirms exclusive window-manager graphics ownership in response to the kernel-mediated backend proposal; raw-read exclusivity cannot be enforced by this hardware policy. F405 is readable in either mode without an exception. This supersedes revision 0.30's read gating and mandatory pre-acknowledgement SWI: read-based timer acknowledgement is now permitted before the bridge. Exact mode-status bit ABI, safe-read application policy and cycle-qualified GAL routing/fit remain pending. No code programming or test is claimed.

Settled in revision 0.32: the user accepts F405 bit 7 as 1=privileged/0=locked with bits 0–6 unspecified and callers masking $80. Ordinary managed applications use OS APIs for device reads despite unrestricted hardware reads. Detailed circuit/driver integration remains pending. Entry review records that SWI/NMI overwrite mode before a handler can read its previous value; the status register alone cannot restore nested state. A diagnostic-and-halt first NMI policy is the next proposal, not yet accepted. No implementation or test occurred.

Recorded in revision 0.33: the user has not selected any NMI role. Stage-3 CPU/root schematic inspection shows the NMI pin pulled inactive via R2 (10 kOhm to VCC) and its root-sheet interface marked no-connect. Proposed first-release default is to reserve NMI, retain a minimal ROM handler, attempt bounded emergency serial diagnostics and stop until reset on unexpected entry; no resumable debugger or NMI scheduler is required. This remains a proposal, not a user acceptance. CPU-entry stacking and repeated-NMI behavior limit diagnostics and require implementation checks. No code or hardware changes occurred.

Recorded in revision 0.34: the user requires loading drivers for a planned multi-card expansion board, including disk/IDE, ADC, parallel printer and modem/network hardware. Add a proposed banked trusted-module framework with OS resource/IRQ/request ownership, device classes and /dev, independent protocol services, bounded asynchronous progress and explicit load/unload/reference policies. Inspection finds one P3 interrupt signal (/IRQ8); per-card identification/aggregation and slot addressing are open hardware decisions. The framework is not yet accepted or implemented; existing NMI and protection policies remain as previously recorded.

Recorded in revision 0.35: the user supplies µLind Motherboard.pdf and identifies page 5 as the expansion addressing plan. Record fixed F600/F700 baseboard regions, six unequal slot windows per board, and separate physical expansion-RAM ranges. Slot-2 range labels specify 32 bytes but the printed A4=1 term selects 16 bytes; correction requires confirmation. Page 13 mentions an 8-bit card-type ID without a register/discovery ABI. Other PDF IRQ/status/connector labels differ from stage-3 sources or newer accepted decisions and remain to be reconciled. Fixed addressing is now supplied; trusted module execution and the remaining driver/discovery/IRQ proposals are not yet accepted. No attachment, repository, GAL or hardware implementation was modified.

Settled in revision 0.36 on 12 October 2026: the user confirms slot 2 is 32 bytes and the PDF decode expression is in error; A4 is don't-care for the labelled C0–DF ranges. Card identification is not implemented. A future baseboard register will report attached-card identities, with I2C connectivity to all positions for optional configuration EEPROMs. Automatic identification and extended EEPROM configuration are future features. Explicit first-release bindings are proposed; trusted module execution, loading/unloading policy and IRQ aggregation remain unresolved. The uploaded PDF, source repositories and hardware have not been modified.

Settled in revision 0.37 on 12 October 2026: the user accepts trusted banked kernel driver modules loaded from CF at boot or through a console command, retained until reboot initially. The baseboard will have a register identifying requesting slots. No automatic ID/EEPROM discovery or runtime unload is required. Exact module ABI and pending-register layout/read/clear/mask/route are not yet defined; non-clearing six-bit status and per-slot enable masking are the next proposals. No source or hardware implementation/test occurred.

Settled provisionally in revision 0.38 on 12 October 2026: the user accepts non-clearing active-high slot bits 0–5 and the matching reset-zero per-slot enable mask, with card-side acknowledgement, as a working contract that may change after hardware completion. Retain unassigned offsets/routing and isolate physical register details in a proposed controller-adaptation layer. Do not claim hardware implementation/validation. Shared driver code with separate per-card instances is the next module-ABI proposal, not yet selected.

Settled in revision 0.39 on 12 October 2026: the user confirms several identical cards must share driver code while retaining separate mutable state and buffers. Record one module image plus per-card instance/resource/request identities; failure to bind a second card must not overwrite or remove the first instance. Native/CMOC entry/state/window ABI remains to be specified, and shared code does not imply unguarded reentrancy. Exclusive raw-device opens with service-mediated sharing are the next proposal; no file-sharing policy is changed or hardware/code implementation claimed.

Settled in revision 0.40 on 12 October 2026: the user accepts raw-device exclusivity to an owner service, which serves many clients. Keep module, per-card/device instance and service-owner lifetimes separate; clients use service endpoints, and raw claims/references survive only as required for safe in-flight cleanup. Class-specific client sharing and recovery/claim ABI remain engineering work. Multiple raw devices owned by one service are the next explicit topology proposal, not yet selected. MLFS regular-file sharing, unrestricted hardware reads, retained modules, and existing service failure/reconnection rules are unchanged. No implementation/test occurred.

Settled in revision 0.41 on 12 October 2026: the user confirms one filesystem service can handle several drives. Keep exclusive raw claims per device and distinct device/volume/file identities beneath the shared namespace. Async interleaving, cache/lock keys, geometry/context limits and target MLFS reentrancy/continuation work remain engineering tasks. Local drive/controller failure isolation is the next proposal; service-wide MLFS failure, core-driver fault and conservative recovery policies are unchanged. The user has not selected class-specific ADC/network multi-device semantics. No implementation/test occurred.

Settled in revision 0.42 on 12 October 2026: the user agrees that unrelated drives/volumes remain accessible after a drive/controller failure. Only affected volumes become unavailable; filesystem-service crashes and trusted driver/core faults retain their wider existing failure scopes. Healthy access modes, per-device/volume identity, bounded progress, no blind write replay and safe reference cleanup remain part of the implementation direction. Fresh-generation recovery with stale old handles is the next proposal, not yet accepted. No implementation or validation occurred.

Settled in revision 0.43 on 12 October 2026: the user confirms lost handles require an explicit new request. Recovering a volume does not resurrect its previous file handles; keep resource generations and completion identities distinct, and preserve IPC drain/EOF semantics and named-service no-auto-reconnect policy. Distinct invalid/stale-handle errors and local stale-handle cleanup are recommended ABI details. An unusable cwd requiring explicit absolute chdir rather than automatic reset/rebinding is the next proposal, not yet accepted. No code or test occurred.

Settled in revision 0.44 on 12 October 2026: the user accepts that a process whose cwd is on a failed/unavailable volume remains alive, relative-path operations fail, and explicit chdir to an accessible absolute path is required. Healthy mounted paths remain accessible through absolute paths. No automatic cwd reset/rebinding occurs on volume recovery, consistent with the fresh-handle rule. Kernel refs, error/getcwd/child-launch ABI and recovery/unmount sequencing remain engineering work; no implementation/test occurred.

## Sources inspected

- [microLind software](https://github.com/MicroLind-Developers/microlind-sw), snapshot 8ac09c3.
- [Simulator hardware map](https://github.com/MicroLind-Developers/microlind-sim/blob/fc9a48430705d0cc6b318468350eef36bfdbf0de/examples/hw.cfg).
- [Simulator mapper](https://github.com/MicroLind-Developers/microlind-sim/blob/fc9a48430705d0cc6b318468350eef36bfdbf0de/src/devices/memory_mapper.cpp).
- [Simulator VDC renderer](https://github.com/MicroLind-Developers/microlind-sim/blob/fc9a48430705d0cc6b318468350eef36bfdbf0de/src/app/vdc_render.cpp).
- [MLFS API](https://github.com/MicroLind-Developers/microlind-sw/blob/8ac09c3/mlfs/lib/include/mlfs.h).
- [MLFS implementation](https://github.com/MicroLind-Developers/microlind-sw/blob/8ac09c3/mlfs/lib/src/mlfs.c).

Additional inspection on 11 October 2026: default-branch [MLFS header](https://github.com/MicroLind-Developers/microlind-sw/blob/main/mlfs/lib/include/mlfs.h), blob b536c145d040c2527a1cbce9fd2740aa496bd02c; [MLFS write routine](https://github.com/MicroLind-Developers/microlind-sw/blob/main/mlfs/lib/src/mlfs.c), blob ccfd37154a67c9a749e19a7ec70c149f3bcba3d3. General background on durability: [SQLite atomic commit documentation](https://sqlite.org/atomiccommit.html); it does not establish MLFS or CF guarantees.

Additional inspection on 11 October 2026: default-branch [stage-2 serial timer test](https://github.com/MicroLind-Developers/microlind-sw/blob/main/spikes/stage2_irq_firq_timer_test/timer_test.asm), blob 2e7490c44bde04d59ea6faba69d641844955735a; existing local BIOS serial/VIA timer routines from snapshot 8ac09c3. No timer or interrupt test was executed.

Additional inspection on 11 October 2026: [current BIOS initialization/vector table](https://github.com/MicroLind-Developers/microlind-sw/blob/main/bios/src/init.asm), blob 2082e95801b22ee9d4cbd2aad1ac217ddd2a9d43; [current serial timer-mask routine](https://github.com/MicroLind-Developers/microlind-sw/blob/main/bios/driver/serial_xr88c92.asm), blob 55c8e5369a2c6bd5fa08263d535554c46fe06b8a. Primary-document background: [Motorola MC6809/MC6809E manual, section 1.11.8](https://www.maddes.net/m6809pm/sections.htm) and [Exar XR88C92/192 datasheet, page 7](https://www.alldatasheet.net/html-pdf/101279/EXAR/XR88C92/708/7/XR88C92.html). These sources do not substitute for the user's actual GAL equations, board clock configuration, or native 6309 bus measurements.

Timer timing analysis for revision 0.12: [Exar XR88C92/192 datasheet, page 13](https://www.alldatasheet.net/html-pdf/101279/EXAR/XR88C92/1320/13/XR88C92.html) describes the doubled preload period and timer interrupt acknowledgement; [page 20](https://www.alldatasheet.net/html-pdf/101279/EXAR/XR88C92/2034/20/XR88C92.html) specifies crystal/16 selection and rising-edge timer interrupts. Calculations use the user-confirmed crystal, not a measured rate.

Additional inspection on 11 October 2026 for reclamation: current [simulator mapper](https://github.com/MicroLind-Developers/microlind-sim/blob/main/src/devices/memory_mapper.cpp), blob 7513d3c397cecd832ecf79e0ba80253ec765d34a, and [hardware configuration](https://github.com/MicroLind-Developers/microlind-sim/blob/main/examples/hw.cfg), blob 9c9176ca46d7ff0b4634352285ded901d73f8e8f. The model masks bank numbers and has no vacant-window disable setting; these files do not establish the actual GAL's RAM-enable behavior.

Filesystem namespace inspection on 11 October 2026: current [MLFS API](https://github.com/MicroLind-Developers/microlind-sw/blob/main/mlfs/lib/include/mlfs.h), blob b536c145d040c2527a1cbce9fd2740aa496bd02c, exposes directory operations; [MLFS README](https://github.com/MicroLind-Developers/microlind-sw/blob/main/mlfs/README.md), blob 2c1621ca78110a7016ab720c08a80dc4ca704a79, describes subdirectory navigation. Documentation and declarations do not establish target runtime correctness.

Ordinary-file growth inspection on 11 October 2026: [mlfs_pwrite_file](https://github.com/MicroLind-Developers/microlind-sw/blob/main/mlfs/lib/src/mlfs.c), blob ccfd37154a67c9a749e19a7ec70c149f3bcba3d3, caps writes to the first extent's capacity and does not allocate additional backing blocks. No target growth implementation or test has been performed.

Terminal-profile reference inspected on 11 October 2026: [XTerm control sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html), maintained by the xterm project, defines the familiar ESC/CSI, cursor, erase, attributes, and keyboard conventions considered for section 8.4. The proposed MLOS subset and its memory calculations are design choices, not claims of full xterm/VT100 compatibility or measured performance.

Bootstrap inspection on 11 October 2026: [BIOS boot menu/stub](https://github.com/MicroLind-Developers/microlind-sw/blob/main/bios/src/mlbios.asm), blob 58dce75dcd42575ceafe69d6c73a684a32e7af8a, lines 385–402; [MLFS bootstrap format notes](https://github.com/MicroLind-Developers/microlind-sw/blob/main/docs/MLFS_BOOTLOADER_FORMAT.md), blob 1ce3f31ff4e9eb015b5c5f38d7922f1ed5d8f143; [CF BIOS driver header/API](https://github.com/MicroLind-Developers/microlind-sw/blob/main/bios/driver/compactflash.asm), blob ffda4b03f3f9ce86a70217f4239ed8cdf96bb033, lines 1–100. The driver describes byte-wide PIO and LBA28; target behavior has not been tested. Existing format notes' $8000 skeleton load address does not override the user's bank-0 design.

GAL-source inspection on 11 October 2026: [firmware address decoder](https://github.com/MicroLind-Developers/microlind-fw/blob/main/logic/address-logic/address-logic.pld), blob 7c685ba4f78eed2b0c17e376fed3f716a1771432, and [firmware signal logic](https://github.com/MicroLind-Developers/microlind-fw/blob/main/logic/signal-logic/SIGNAL-LOGIC.PLD), blob 12b5d1ad5d14a1fb38d8e99b76e251def384470c. These inspected files define decode/read-write/bus-availability logic and do not define the specified vector-unlock/F405-relock state machine. Searches did not identify its current source; that is not proof no such revision exists. The user's stated hardware contract remains authoritative. Subsequent user clarification confirms the board provisions this mechanism but the GAL logic revision has not yet been implemented; the missing equations are pending development rather than a source revision to locate.

Stage-3 wiring inspection on 11 October 2026: [address and signal logic schematic](https://github.com/MicroLind-Developers/microlind-hw/blob/main/motherboard/motherboard-stage3/address_logic.kicad_sch), blob 56040df27c7277b8794d6d8d73f882138ef71cb9; [root schematic](https://github.com/MicroLind-Developers/microlind-hw/blob/main/motherboard/motherboard-stage3/motherboard.kicad_sch), blob 24cc6907c9511627e0537dfe1da1ad14591d1923; [CPU/memory schematic](https://github.com/MicroLind-Developers/microlind-hw/blob/main/motherboard/motherboard-stage3/cpu_men.kicad_sch), blob 11b17bae5170ac4e08b8da5d33343d6a5ba3bd0e. Parsed component pin positions, wires and net labels ground section 5.2. Families and routing are observed; device-specific latch fit/timing and physical continuity are not verified. The published PDF was visually reviewed as an additional drawing snapshot; the current KiCad sources control the recorded pin routing.

NMI planning inspection on 11 October 2026: the stage-3 [CPU/memory schematic](https://github.com/MicroLind-Developers/microlind-hw/blob/main/motherboard/motherboard-stage3/cpu_men.kicad_sch), blob 11b17bae5170ac4e08b8da5d33343d6a5ba3bd0e, and [root schematic](https://github.com/MicroLind-Developers/microlind-hw/blob/main/motherboard/motherboard-stage3/motherboard.kicad_sch), blob 24cc6907c9511627e0537dfe1da1ad14591d1923, were fetched again with unchanged hashes. Parsed NMI net, R2/VCC connections and root no-connect marker ground section 5.4. [Motorola MC6809/MC6809E programming manual, section 1.11.10.1](https://www.maddes.net/m6809pm/sections.htm) describes non-maskability, falling-edge request, initial hardware-stack initialization and CPU stacking; this is family-reference information, not a native HD6309 target measurement.

Expansion-driver source inspection on 11 October 2026: [stage-3 expansion schematic](https://github.com/MicroLind-Developers/microlind-hw/blob/main/motherboard/motherboard-stage3/expansion.kicad_sch), blob 1c2b28d02c19cdc5a3288d92e9f5e1de853043db, and [IRQ-handler schematic](https://github.com/MicroLind-Developers/microlind-hw/blob/main/motherboard/motherboard-stage3/irq_handler.kicad_sch), blob 1c0c1e2b47375246fbf8a6c1a93a7059c3e2bee9. Parsed P3 pin routing grounds the single /IRQ8 observation and bus-signal provisions. Interrupt controller component/source labels were inspected, but shared-source dispatch timing and electrical behavior were not validated. The planned expansion board/card designs were not provided or inspected; bitmap/discovery/driver recommendations are proposals.

User-supplied document inspection on 11 October 2026: µLind Motherboard.pdf, 15 pages, SHA-256 7c1d7e26cd8b0440d0c4e929354da2c5fbb39f72e4c86bf4c60b146bf446066d. Read page 5's address/RAM tables and visually verified the page; page 13's card-ID note was also rendered/verified. Text from pages 3, 6 and 11 identifies the conflicting F405/connector/IRQ descriptions discussed in section 11.2. The user specifically supplies page 5 as the expansion address plan; source descriptions elsewhere do not replace later accepted MLOS ABI decisions automatically. Arithmetic confirms the labelled fixed ranges cover 256 bytes per board, while the slot-2 decode bit pattern covers only 16. These are source observations and design proposals, not programmed hardware behavior.

Source inspection is not hardware validation or a successful build/test claim. User decisions in this conversation override older source layouts and roadmap text.
