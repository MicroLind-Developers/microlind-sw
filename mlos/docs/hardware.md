# MLOS stage-3 hardware profile

Software-facing S00–S09 profile, based on architecture revision 0.44 and local
`../microlind-hw/motherboard/motherboard-stage3/` at commit
`017c4cd0f0aae78c3626594b962fac656d738bb5`. Hardware facts below distinguish
schematic provisions from the implemented simulator contract. No board tests
or GAL compilation/programming have been performed.

## Memory and devices

| Range/resource | Selected profile and evidence |
| --- | --- |
| CPU | HD6309, native MD=1 throughout; board target candidate 3 MHz; both current foundation/runtime profiles explicitly select a 3 MHz simulator model |
| Physical RAM | 512 KiB / 32 whole 16 KiB frames; no RAM-size inference from expansion capacity |
| 0000–3FFF | MMU0, core frame0 while in core, application's resident frame otherwise |
| 4000–7FFF,8000–BFFF | MMU1/2, application maps or bounded kernel scratch mapping |
| C000–DFFF | MMU3 permanently selects frame1, only its lower 8 KiB exposed |
| E000–F3FF,F800–FFFF | 7168 usable ROM bytes; vectors at FFF0–FFFF |
| F400–F7FF | 1024-byte I/O overlay inside the 8 KiB ROM address range |
| F400–F403 | Four byte-wide mapping registers; simulator readback; actual timing/encoding remains a board check |
| F404 | IRQ priority filter in high nibble, pending level in low nibble in existing simulator; serial level1, VIA level2 |
| F405 | Write relock, read bit7=privileged; mask $80, ignore bits0–6 |
| F410–F411 | PS/2 keyboard/mouse; transport not modeled/used by this stage |
| F412–F417 | RTC reservation, unused |
| F418–F41F | CompactFlash byte PIO; CF bootstrap and runtime use 512-byte sectors |
| F420–F42F | VIA/parallel; unused by this bootstrap |
| F430–F43F | XR88C92 UART/timer; UART A interactive, UART B independent output-only logs |
| F440–F47F | VDC range; current simulator exposes register/data ports at F440/F441; omitted from the serial-only harness configuration |
| F480–F4BF | Sound reservation, unused |
| F600–F7FF | Expansion slots; explicit polled CF1 simulator binding F640–F647; physical offsets/IRQ qualification open |

`mlos/hardware.cfg` is the executable simulator profile. All vacant windows map
to discard frame2. There is no vacant-window disable or general RAM protection.
Ordinary/common RAM writes remain possible while the I/O gate is locked.
Applications conventionally use MLOS APIs for device reads even though hardware
allows direct reads and their side effects.

## Implemented simulator latch

The banked-motherboard builder enables the gate; a generic flat CPU-test bus
retains its previous behavior unless `Bus::enable_privilege_gate(true)` is
called. Enabling begins locked; reset vector fetch establishes privilege before
ROM's first stackless map write. This is a behavioral model of the agreed
contract, independent of the unfinished PLD equations.

| Event | Result |
| --- | --- |
| Read with VectorRead, BA=0/BS=1, address FFFA–FFFF | Unlock on either vector byte: plain SWI, NMI, reset |
| IRQ/FIRQ/trap/SWI2/SWI3 vector | No unlock |
| Ordinary read/peek of a vector address; low-byte alias; idle cycle | No unlock |
| Privileged F400–F7FF write | Device effect; F405 consumes the write and relocks for any payload |
| Locked F400–F7FF write | Ignored; no device effect or new fault |
| Read in either mode | Normal device behavior, including FIFO drain and timer acknowledgement |
| F405 read/peek | Bit7 reflects retained mode; model chooses zero for unspecified lower bits |
| Ordinary RAM write | Remains writable in either mode |

The gate acts at the committing E-high/Q-low phase for microcycle/deferred
accesses and in program order for instruction execution. CPU memory cycles use
BA/BS=0/0 normally and 0/1 for qualified vector fetches. Debug peeks never unlock.
Tests cover both phase settings and both CPU execution paths. This does not
model GAL propagation delay, electrical bus drive or every CPU BA/BS idle state.

The selected XR88C92 timer model implements ACR mode7 only: the 3.6864 MHz
crystal divided by 16, with a rising-edge interrupt every twice the preload.
Preload115 gives 1001.739130... Hz, not an exact millisecond tick. It accumulates
rational crystal/CPU time independent of simulation chunk size. The stop-command
read clears timer IRQ without stopping the periodic timer in mode7. Peeks have
no command effect. Other counter modes, current-counter readback and UART B RX
remain outside this minimal model. S04/S07 use only the modeled timer/output
subset; physical clock and UART timing still require audit.

The ROM backend owns combined IMR/ACR shadows. Timer setup replaces only
ACR[6:4], ORs IMR bit3, programs preload115, admits the serial IRQ at F404, and
starts through the read command. The test preserves unrelated mask/ACR bits
and demonstrates that acknowledging timer IRQ leaves RX IRQ pending. The normal
S02 bootstrap keeps the timer disabled; the contract runner enables it for IRQ
qualification. The production runtime enables the timer for scheduling/time
calls; `include/scheduling.inc` controls its preload and five-tick default quantum.

`runtime/backplane.asm` owns a version-1 two-controller pending/mask adaptation.
Bindings default to zero addresses and stay disabled. A configured controller
starts with a zero enable mask; reads preserve non-clearing pending bits and
mask out reserved bits6–7. Mock target tests cover independent controllers,
version rejection and normalization in both engines. No physical offset or
upstream IRQ number is inferred from the polled CF1 test. Card-specific cause
acknowledgement and real aggregate IRQ dispatch remain S15 hardware work.

## Physical gate work still open

The actual schematic has these provisions:

- U26 GAL22V10 receives A0–A9, IO_EN, WR and RD, and produces ENTER_PROT,
  EXIT_PROT and PROT_STATE. It has no retained PROT_MODE input.
- U27 GAL16V8 receives E/Q, pre-R/W, BA/BS, MEM_EN and ENTER/EXIT_PROT. It
  produces retained PROT_MODE and map read/write strobes.
- U23 GAL22V10 receives PROT_MODE and participates in RAM/ROM/I/O/map decode;
  it lacks a general R/W input in the inspected routing.
- U24/U25 74LS670 mapping write enables use U27 MEM_WR. U28 provides map readback.
- The PROT_STATE/Q1 circuit can sink D7, but does not establish reliable
  state-dependent high and low readback with the current described inputs.
- CPU NMI is pulled up; the inspected root sheet has no routed NMI source.

The schematic notes omit NMI from ENTER_PROT, underqualify the address match,
include an unwired RESET term, and omit retained privilege from MEM_WR/status
logic. All-I/O-write denial must reach devices using E/RW as well as WR, while
preserving reads and SRAM writes. Current pin assignments do not establish that
this can be solved by equations alone. The wiring/feedback/status route must be
resolved before selecting latch equations, part speed grades and fit settings.
No fitted `.jed` is provided, and no physical schematic was silently changed.

Physical acceptance procedure (owner/evidence: board/GAL implementation work):

1. Confirm installed parts, continuity, D7 driving, decoded selects and the
   actual signal roles. Resolve retained-status routing and all write paths.
2. Compile exact-vector decode/state equations for the installed parts; retain
   source, fitter report, pinout, resource use and programming checksum.
3. Use a logic analyzer to qualify both bytes of reset/SWI/NMI vectors at the
   selected bus phase. Verify ordinary reads and every excluded vector do not
   change retained mode; verify deterministic reset-to-first-map behavior.
4. In locked mode try writes to MMU, IRQ, UART/timer, CF, PS/2, VIA, VDC,
   sound and a representative expansion card. Prove no target write pulse or
   mutation. Separately prove reads/read side effects and SRAM writes survive.
5. In privileged mode prove map readback/update and peripheral writes. Read
   F405 with varying lower data bits; verify a reliable D7 in both modes,
   without contention. Any privileged F405 payload must relock.
6. Exercise the ROM register/map/stack sentinels and IRQ/SWI nested return on
   the board. Check no nested return withdraws an interrupted kernel's write
   permission. Measure entry/IRQ costs, UART readiness and timer frequency.

Physical qualification and the later CF/timer K1 gate remain open until these
artifacts and measurements exist. Simulator evidence permits further software
work under the staged plan but does not certify the GAL wiring or timing.
