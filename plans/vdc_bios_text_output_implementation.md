# VDC BIOS Text Output Implementation Plan

## Goal

Add safe, optional MOS 8568 VDC text output to the BIOS utility menu. When a
VDC is detected and initialized, the menu is displayed on an 80x25 text
screen. When no VDC is present, or VDC initialization fails, the existing
serial menu remains available.

This first increment treats the VDC as an output device only. Menu input
continues to use the serial port because the PS/2 keyboard driver is not part
of the current BIOS build.

## Current State

- `bios/driver/vdc.asm` contains basic indirect register read/write routines
  and text/graphics mode bit selection.
- `VDC_READ` currently has no `RTS` and falls through into
  `VDC_INIT_TEXT`.
- Both VDC access routines wait forever for the ready bit. This prevents them
  from being used for safe hardware detection.
- `VDC_INIT_TEXT` only clears the graphics-mode bit. It does not configure
  display timing, video-memory locations, colors, the cursor, or character
  data.
- `bios/src/mlbios.asm` sends menu output directly to the serial routines.
- The VDC source is present in `bios/CMakeLists.txt`, but not in
  `bios/Makefile`.
- The current VDC, BIOS-menu, RAM-test, and MMU changes are uncommitted and
  must be preserved while implementing this feature.

## Scope

### Included

- Bounded VDC register access.
- Non-destructive VDC presence detection.
- Complete 80x25 text-mode initialization.
- A readable printable-ASCII character set in VDC-local RAM.
- Screen clear, character and string output, cursor control, CR/LF handling,
  line wrapping, and scrolling.
- Automatic VDC selection with serial fallback.
- Serial input for menu selection.
- CMake and Make build integration.
- Assembly and physical-hardware verification.

### Deferred

- Bitmap/graphics modes.
- PS/2 keyboard input and a complete screen editor.
- Per-character color APIs beyond what is needed for the initial menu.
- Public C wrappers or BIOS jump-table entries for VDC functions.
- Changing MLOS console syscalls from serial to a generic display console.

The BIOS jump table is append-only. This implementation will keep the VDC
driver internal rather than modifying the existing ABI.

## Design

### 1. Driver State

Use the video-driver area defined in `bios/include/memory.inc` for state such
as:

- VDC-present/initialized status.
- Logical cursor row and column, or an equivalent 16-bit screen offset.
- Current text color if per-character attributes are enabled.
- Temporary values needed by clear or scroll operations.

Add `CONFIG_VDC_PRESENT_FLAG` to the remaining configuration-data space so
boot code and the menu can make the same routing decision.

Review and correct the comments around the video and audio driver RAM ranges
while adding these definitions; the calculated addresses, rather than the
currently stale comments, must remain authoritative.

### 2. VDC-Local Memory Layout

Use a fixed, documented layout that also works with a 16 KiB VDC RAM
configuration. The proposed starting layout is:

| Region | Proposed base | Initial size |
|---|---:|---:|
| Character screen | `$0000` | 2000 bytes |
| Attribute screen | `$0800` | 2000 bytes |
| Character font | `$2000` | 4096 bytes for 256 glyphs |

Each 8x8 glyph will occupy the VDC's required character stride, with unused
scan lines padded as needed. The font will be indexed by ASCII value so menu
strings can be copied without a separate PETSCII/screen-code conversion.

Before implementation, confirm that these regions and the register-28 base
encoding match the installed 8568 and its VDC RAM wiring.

### 3. Low-Level Register API

Refactor `bios/driver/vdc.asm` around a bounded ready operation:

- `VDC_WAIT_READY`
  - Wait for status bit 7 with a finite loop count.
  - Carry clear: ready.
  - Carry set: timeout.
- `VDC_WRITE`
  - Input: `A` = internal register, `B` = value.
  - Carry clear: success.
  - Carry set: timeout.
- `VDC_READ`
  - Input: `A` = internal register.
  - Output: `B` = value.
  - Carry clear: success.
  - Carry set: timeout.
  - Return explicitly instead of falling through.

Register numbers, masks, screen dimensions, VRAM addresses, and timeout
values should use named constants rather than literals.

### 4. Presence Detection

Implement `VDC_DETECT` as a reversible probe:

1. Confirm that the ready bit becomes set within the timeout.
2. Read and save a safe, fully read/write internal register, initially
   register 27 (address increment per row).
3. Write and read back two distinct values.
4. Restore the original value.
5. Return carry clear only if both values read back correctly.

The two-pattern test prevents a floating bus that always reads `$FF` from
being treated as a VDC. Any wait, read, write, or verification failure reports
the device as absent without hanging the BIOS.

### 5. 80x25 Text Initialization

`VDC_INIT_TEXT` will perform complete initialization rather than only
changing register 25:

1. Program an 80-column RGBI timing table.
2. Select non-interlaced text mode.
3. Set 80 displayed columns and 25 displayed rows.
4. Set character height and horizontal character width for an 8x8 font.
5. Configure the display, attribute, and character-memory base addresses.
6. Set address increment to one byte.
7. Select initial foreground and background colors.
8. Configure hardware cursor start/end scan lines and make it visible.
9. Upload the printable-ASCII font to VDC-local RAM.
10. Clear screen and attribute memory.
11. Set the logical and hardware cursor to row 0, column 0.

The register timing table depends on the board's VDC clock and monitor
interface. Unless the hardware design says otherwise, implementation will
start from the standard C128-compatible 80-column RGBI timing values and
validate the result on the MicroLind hardware.

### 6. VDC Memory and Text Primitives

Add the following internal routines with documented register preservation
and carry behavior:

- `VDC_SET_UPDATE_ADDRESS`
- `VDC_READ_VRAM_BYTE`
- `VDC_WRITE_VRAM_BYTE`
- `VDC_CLEAR_SCREEN`
- `VDC_HOME`
- `VDC_SET_CURSOR`
  - Proposed input: `A` = row, `B` = column.
- `VDC_GET_CURSOR`
- `VDC_PRINT_CHAR`
  - Input: `A` = ASCII character.
- `VDC_PRINT`
  - Input: `X` = NUL-terminated string.
- `VDC_PRINT_CRLF`
- `VDC_SCROLL_UP`

`VDC_PRINT_CHAR` must support:

- Printable ASCII.
- Carriage return: move to column zero without advancing the row.
- Line feed: advance one row without changing the column.
- Automatic wrap after column 79.
- Scroll when output moves beyond row 24.
- Updating VDC cursor registers 14 and 15 after cursor movement.

Handling CR and LF independently is required because current BIOS strings
contain both LF/CR and CR/LF orderings.

Start with straightforward, reliable VRAM operations. The VDC block-copy
engine can be used for clearing or scrolling only after the basic byte access
path is working and separately verified.

### 7. Font Data

Add a ROM-resident 8x8 font table, either in a dedicated assembly source or
alongside the VDC driver. Requirements:

- Cover printable ASCII `$20` through `$7E` at minimum.
- Keep control-code entries blank.
- Store glyphs at their ASCII indices in VDC-local character memory.
- Use a source with a project-compatible license and record its attribution.
- Make the font source an explicit dependency in both build systems.

### 8. Boot Integration

Update `bios/src/init.asm` after MMU and stack initialization:

1. Keep serial initialization first so early diagnostics are always possible.
2. Call `VDC_DETECT`.
3. Clear `CONFIG_VDC_PRESENT_FLAG` on failure.
4. On detection success, call `VDC_INIT_TEXT`.
5. Set the flag only after complete initialization succeeds.
6. Print a concise serial diagnostic indicating whether VDC output is active
   or serial fallback is being used.

A failed or absent VDC must not prevent RAM detection, CompactFlash
initialization, or entry into the BIOS menu.

### 9. BIOS Menu Routing

Add a small output-only console layer for `bios/src/mlbios.asm`, for example:

- `BIOS_CONSOLE_PRINT`
- `BIOS_CONSOLE_PRINT_CHAR`
- `BIOS_CONSOLE_PRINT_CRLF`
- `BIOS_CONSOLE_CLEAR`

These routines check `CONFIG_VDC_PRESENT_FLAG` and call the VDC output path
when it is set, otherwise the serial path. Menu drawing will use this layer
instead of calling `SERIAL_PRINT_A` directly.

On the VDC path, clear/home the screen before redrawing the main menu. On the
serial path, preserve current behavior.

`SERIAL_INPUT_A` remains the input path. Its existing `>` prompt and echo stay
on the serial terminal. The serial-test utility must continue to call serial
routines directly because it is explicitly testing the UART.

Keep the current "Initialize Graphics" menu item as a VDC reinitialize/test
command during bring-up. Once automatic initialization is stable, removing
or repurposing that item can be handled separately.

Routing all utility output and `MEMORY_DUMP` through a generic console is a
follow-up change. The first increment guarantees VDC display of the menu and
provides the driver primitives needed for that later conversion.

## Expected File Changes

| File | Planned change |
|---|---|
| `bios/driver/vdc.asm` | Safe access, probe, initialization, VRAM, text, cursor, and scroll routines |
| `bios/driver/vdc_font.asm` or equivalent | ROM-resident ASCII font data |
| `bios/include/memory.inc` | VDC driver-state definitions |
| `bios/src/config.asm` | VDC presence configuration flag if kept with other configuration symbols |
| `bios/src/init.asm` | Automatic detection, initialization, and serial diagnostic |
| `bios/src/mlbios.asm` | Output dispatcher and VDC menu routing |
| `bios/CMakeLists.txt` | Font/source dependencies and any added VDC source |
| `bios/Makefile` | Add VDC and font sources to the Make build |

No jump-table, C header, MLOS, or bitmap-mode changes are planned in this
increment.

## Implementation Sequence

1. Add constants, state definitions, and documented ABI/error conventions.
2. Correct `VDC_READ` and add bounded ready/read/write operations.
3. Add and validate non-destructive VDC detection.
4. Implement raw VDC RAM addressing and byte transfer.
5. Add the font and font-upload routine.
6. Implement the complete 80x25 initialization table.
7. Implement clear, cursor, character, string, wrapping, and scrolling
   operations.
8. Integrate detection and initialization into reset handling.
9. Route BIOS menu output through the selected console.
10. Synchronize both build systems and perform assembly/static checks.
11. Perform the hardware acceptance tests below.

Each stage should leave the serial console usable so hardware debugging does
not depend on the unfinished VDC path.

## Verification

### Assembly and Static Checks

- Assemble the BIOS with `lwasm` through the CMake target.
- Assemble through `bios/Makefile` and confirm both paths use the same VDC
  sources.
- Check the generated image for ROM overlap and unexpected origin changes.
- Confirm all VDC wait loops are bounded.
- Confirm all detection-time register changes are restored.
- Confirm the screen, attribute, and font regions do not overlap.
- Confirm driver-state addresses remain within the allocated video-driver
  RAM region.

### Hardware: VDC Absent

- BIOS reaches the menu without a long delay or hang.
- Serial initialization and boot diagnostics remain readable.
- The serial menu and all existing selections still work.
- Repeated warm and cold resets continue to fall back correctly.

### Hardware: VDC Present

- The BIOS reports successful detection over serial.
- The monitor locks to a stable 80x25 image.
- The complete menu is readable using the uploaded font.
- Foreground/background colors and hardware cursor are visible.
- Menu redraw clears stale content.
- CR/LF in both existing byte orders produces correct line starts.
- Column wrapping and bottom-of-screen scrolling work.
- Reinitializing the VDC does not corrupt BIOS RAM or hang the machine.
- Warm and cold resets both initialize the display reliably.

### Failure Injection

- Use an intentionally short/forced ready timeout during bring-up and verify
  serial fallback.
- Make one register-probe comparison fail and verify that the VDC-present
  flag stays clear.
- Make text initialization return an error and verify that the BIOS still
  reaches the serial menu.

## Completion Criteria

The initial feature is complete when:

- A MicroLind system without a VDC behaves as it did before this change.
- A system with an operational MOS 8568 automatically displays the BIOS menu
  as readable 80x25 text.
- Menu selection remains usable through the serial port.
- VDC absence or failure cannot trap the CPU in an infinite ready loop.
- Both supported BIOS build paths assemble successfully.
- No existing BIOS jump-table addresses change.

## References

- Commodore 128 Programmer's Reference Guide, Chapter 10, "Programming the
  80-Column (8563) Chip," and the 8563/8568 hardware register description.
- Commodore TechTopics Issue 22 notes concerning MOS 8568 register state
  after power cycling.

