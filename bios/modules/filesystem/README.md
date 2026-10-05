# RAM MLFS extension

`biosfs.mlp` is a 6309 assembly module loaded at `$4000`, reserving
`$4000–$BFFF` for code, fixed buffers, and state. It currently implements
mounting, stat, directory enumeration, reads/writes, file and directory
creation/removal, rename/move, allocation statistics, and a serial console.
Files retain one contiguous extent during automatic growth.

Build it and generate a development CF image from the repository root:

```sh
make -C bios
python3 bios/tools/make_boot_image.py --filesystem bios/build/biosfs.mlp \
    --diagnostic bios/build/fsdiag.mlp --output bios/build/cf.img
make -C bios test-fs
```

The Make build needs `lwasm`, Python 3, and CMOC. `make -C bios filesystem`
builds just the assembly extension. CMake builds the diagnostic when CMOC is
available. The image builder uses `cc` and the production host MLFS library.
Partition 0 contains `/biosfs.mlp`, `/fsdiag.mlp` (when supplied), `/data.bin`,
and `/docs/sub/data.bin`. Partition 1 contains `/other.txt` with `partition1`
as its contents, and is reserved for mutation diagnostics.
Use `--log2 9..16` for 512-byte through 64 KB
filesystem blocks, and `--data path` to replace the default sample contents.
Existing output images require `--force` to replace.

Configure the simulator's CF `IMAGE` to point at the generated image. Boot the
BIOS and select **7. Load MLFS extension** using serial input. The extension
uses serial for its console, including when the BIOS menu uses VDC output.

| Command | Action |
|---|---|
| `m [0..15]` | Mount a partition, default 0 |
| `l [path]` | List a directory, default root |
| `s path` | Print a directory entry and file size |
| `c path` | Stream file contents to serial |
| `i` | Show used/free filesystem blocks |
| `n file` | Create an empty file with one allocated block |
| `d dir` | Create a directory with one allocated block |
| `u file` | Remove a file and release its blocks |
| `r dir` | Remove an empty directory |
| `v source destination` | Rename or move without replacing an existing entry |
| `w file text` | Write text at byte 0, retaining any existing tail |
| `a file text` | Append text at EOF |
| `t` | Load and run `/fsdiag.mlp` on partition 1 |
| `h` | Show command help |
| `q` | Return to the BIOS menu |

Sizes, allocation counts, and negative error statuses print in hexadecimal.
The console edits at most 127 input characters; paths containing spaces are
accepted by single-argument commands. Two-argument commands split at the first
space, so their first path cannot contain spaces. Repeated slashes are accepted;
`.` and `..` components are rejected.
Paths have at most 16 components of 47 characters each. Applications can pass
longer paths than the console's input line, within these component limits.

## Service interface

The module entry at `$4000` receives the BIOS descriptor in X. Y=0 opens the
console; nonzero Y initializes, mounts partition 0, and returns status in D/C.
The descriptor at `$4010` contains `FSR1`, a big-endian version word (1), and
an entry-count word (11). The three-byte JMP entries follow at `$4018`. Entry
indices are append-only. `bios/include/filesystem.inc` defines the register ABI.

All services preserve X, Y, U, and DP, and clobber D, W, and CC. Success is
D=0/C clear; failure is a negative `FS_E*` status/C set. Mount takes a partition
index in B. Stat, list, read, and mutation calls take a request pointer in X:

| Offset | Field | Bytes |
|---|---|---|
| 0 | NUL-terminated path pointer | 2 |
| 2 | Read destination / write source / rename destination path | 2 |
| 4 | Buffer capacity / requested byte count | 2 |
| 6 | File byte offset / directory slot cursor | 4 |
| 10 | Transferred bytes / directory entries | 2 |

Stat copies one raw 128-byte MLFS directory entry and reports 128 transferred
bytes. List skips empty slots, copies at most one entry, and advances the slot
cursor; transferred=0 marks EOF. Read retains the requested file offset, caps
the count at EOF, and reports the actual byte count, including completed chunks
before an I/O error. Stats takes an eight-byte destination in X and returns
big-endian 32-bit used/free block counts, excluding bitmap padding bits.

Append-only service indices 5–10 are write, create, unlink, mkdir, rmdir, and
rename. Write retains the requested offset and reports confirmed chunks in
transferred, including on failure. Create/mkdir interpret offset as the initial
block count (0 means 1), ignoring buffer/count; their logical size starts at 0.
Unlink/rmdir use only path. Rename takes the source in path and a NUL-terminated
destination path in buffer, ignoring count/offset. These metadata calls leave
transferred=0. New errors are `FS_EEXIST` (-12), `FS_ENOSPC` (-13), and
`FS_ENOTEMPTY` (-14). Renaming an entry to itself succeeds. Moving a directory
under itself is rejected. Timestamps start at zero and existing timestamps are
preserved; this interface does not expose a clock.

Public requests, paths, and destinations must fit in application RAM
`$0400–$3FFF`, or in live caller stack storage above the service's entry frame
within `$DC00–$DFFF`. Buffer spans cannot cross these regions. Caller objects
must not overlap each other or active return addresses. Private console requests
also support its own input line and the BIOS serial buffer. Services are not
reentrant and must not be called from an interrupt handler.

`bios/include/filesystem.h` and `filesystem_c_shim.asm` expose these services
to CMOC programs. Link the shim into the application; its functions use CMOC's
stack arguments rather than the register ABI. `test-fs` checks real CMOC code
with stack-allocated requests, buffers, and statistics if CMOC is installed.

The module validates MLPT/MLFS 1.1.0, superblock checksums, LBA28 arithmetic,
bitmap capacity, and extent bounds. It accepts the host formatter's ordered
superblock/bitmap/root/data layout. Files and subdirectories must use one inline
contiguous extent with no indirect extents. Failed remounts invalidate the old
mount. Directory capacity is its initial extent; full directories return
`FS_ENOSPC`. The root extent is fixed by formatting. There is no truncate call.

## Growth and failure behavior

Writes first verify that the old extent's bitmap bits are allocated. If more
capacity is needed, the module claims adjacent free blocks when possible.
Otherwise it allocates a larger run, zeroes it, copies existing contents,
publishes the new extent, and releases the old run. Gaps between EOF and a write
are zero-filled. Allocation searches exclude metadata and bitmap padding.

Data and bitmap access stream 512-byte sectors, including filesystem blocks
larger than the buffers. Partial-sector writes preserve other bytes. Each chunk
that extends EOF has its new size committed before it is counted as transferred.
An I/O error can leave confirmed earlier chunks and prepared capacity in place.
New allocations are rolled back on failures before publication; metadata
readback distinguishes a rejected write from a lost completion status after a
successful write. Uncertain metadata or failed rollback invalidates the mount.

MLFS remains non-journaled. Interrupted multi-sector operations or a failed
post-publication release can leak allocation; a failed move rollback can leave
duplicate references. Metadata readback and update ordering prevent freeing a
known referenced extent on a recoverable write failure. Remounting validates
metadata structure, not every cross-reference; this is not a filesystem checker
or a power-loss atomicity guarantee.

`test-fs` executes the packaged module through the real ROM loader, using
production host-library fixtures across all eight block sizes. Coverage includes
nested directories, offsets above 64 KB, EOF and sector boundaries, partial I/O
failures, partition switching, metadata corruption, memory bounds, C wrappers,
and console entry/exit. Mutation checks cover adjacent/relocation growth,
zero-filled gaps, bitmap-sector boundaries, exhausted/fragmented space,
partial writes, full directories, nested removal, move conflicts/cycles,
read-only media, and injected write failures both before and after media
completion. Target-modified images are read with the production host library.

## Board acceptance check

Use this build's `bios/build/bios.ihex` and the generated development CF image.
Select BIOS menu **7**, then enter **t** in the serial console. It loads the real
CMOC application from `/fsdiag.mlp`; the diagnostic mounts partition 1 and
creates `/fsdiag`, refusing to proceed if that path already exists. It checks
writes/growth, contents, zero gaps, stat, rename/move, removal, and allocation
balance. Successful runs remove their own files and print:

```text
FS diagnostic PASS (allocation balanced)
```

The console restores its previous partition after the diagnostic. Run **t**
twice, then **q**, and confirm return to the BIOS menu. A failure prints its
stage and hexadecimal status and leaves the test namespace for inspection;
reruns refuse that existing namespace. `/other.txt` and partition 0 remain
untouched by the diagnostic. The simulator test checks two complete runs and
return paths. Physical CF timing and board behavior still need your results
before gameplay implementation, as agreed in the plan.

The simulator's corrected `SEX` instruction has been verified with
`bios/tests/simulator/sex_probe.asm`: positive and negative bytes produce
the expected words `0073 FF80`. The CMOC diagnostic uses ordinary C comparisons
without an emulator workaround. To check a simulator binary, run:

```sh
python3 bios/tools/diagnose_simulator.py \
    --simulator ../microlind-sim/build/microlind-sim-cli \
    --rom bios/build/bios.ihex --symbols bios/build/bios.sym
```

The check returns a failure status if SEX does not sign-extend B into A while
preserving B. Rebuild the simulator CLI after updating its source; an older
binary can still contain the original bug.
`make -C bios test-fs` and the CMake filesystem test run this check first.
Use `make -C bios test-sim-sex` to run only the instruction check.
