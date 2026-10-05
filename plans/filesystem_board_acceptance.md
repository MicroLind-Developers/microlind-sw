# Filesystem board acceptance

Gameplay implementation is waiting for this hardware checkpoint. Simulator
validation is complete; physical board results have not been reported yet.

## Build and prepare the images

Run from the repository root:

```sh
make -C bios all
mkdir -p bios/build/board-acceptance
cp bios/build/bios.ihex bios/build/biosfs.mlp bios/build/fsdiag.mlp \
    bios/build/board-acceptance/
for block_log2 in 9 10 11 12 13 14 15 16; do
    block_bytes=$((1 << block_log2))
    python3 bios/tools/make_boot_image.py \
        --filesystem bios/build/board-acceptance/biosfs.mlp \
        --diagnostic bios/build/board-acceptance/fsdiag.mlp \
        --log2 "$block_log2" \
        --output "bios/build/board-acceptance/cf-${block_bytes}.img"
done
sed 's|../../build/board-acceptance/cf-512.img|cf-512.img|' \
    bios/tests/simulator/board_no_vdc.cfg \
    > bios/build/board-acceptance/simulator-no-vdc.cfg
(cd bios/build/board-acceptance && sha256sum bios.ihex biosfs.mlp fsdiag.mlp cf-*.img simulator-no-vdc.cfg > SHA256SUMS)
```

The image builder refuses to overwrite an existing image. To regenerate a
test image deliberately, add `--force` to its invocation. The bundle manifest
identifies the exact artifacts tested; check it before writing the images:

```sh
(cd bios/build/board-acceptance && sha256sum -c SHA256SUMS)
```

Each image contains the filesystem and diagnostic modules in partition 0,
sample files including `/data.bin`, and a separate diagnostic partition 1
containing `/other.txt`. The eight filenames identify the filesystem block size
in bytes. The BIOS and the module files are shared across all eight images.

## Run on the board

1. Install the bundle's `bios.ihex` using the board's normal ROM programming
   procedure. Write `cf-512.img` to a test CF card using the normal image writer.
2. Start the board with the CF card inserted and use the serial terminal for
   input. Select BIOS menu **7**. Confirm that the MLFS console appears.
3. Enter `l /` and confirm that `biosfs.mlp`, `fsdiag.mlp`, `data.bin`, and
   `docs` appear. Enter `c /data.bin`; expect
   `Microlind filesystem read test.`.
4. Enter `t`. Expect `FS diagnostic PASS (allocation balanced)`.
5. Enter `t` again. Expect the same PASS message. This checks that cleanup
   allows a second complete run without resetting or rewriting the card.
6. Enter `c /data.bin` again to confirm that the console restored partition 0.
   Enter `m 1`, then `c /other.txt`; expect `partition1`. Enter `m 0`.
7. Enter `q` and confirm return to the BIOS menu. Select **7** again and
   confirm that the filesystem console still works, then `q`.
8. Repeat with the other block-size images to cover all supported layouts.
   Use the same BIOS throughout; power down before replacing the card/image.

For simulator GUI checks, use HD6309 mode and the Serial TX pane. Type `7` in
RX text and press Enter to send the terminating CR; the Send button sends the
text alone. The filesystem console uses serial even when VDC is configured.
The BIOS menu input discards LF, including the LF left after CRLF input, so a
preceding terminal line cannot hide the next menu choice. Reload the ROM after
rebuilding; an already-running GUI keeps its loaded ROM image.

For a prepared serial-only setup, load the bundle's `simulator-no-vdc.cfg`,
then its `bios.ihex` in Intel HEX/HD6309 mode and start execution. This config
explicitly attaches the accompanying `cf-512.img`. The equivalent tracked
config is `bios/tests/simulator/board_no_vdc.cfg`.

`Module load error: 0x02` means the loader rejected MLPT/MLFS metadata. Check
the CF pane's actual image path: loading a hardware config replaces a previously
attached image with that config's `IMAGE` setting. The sibling simulator's older
`examples/sim.img` starts with `TPLM` and is incompatible with the current
MLFS 1.1.0 loader; the generated fixtures start with `MLPT`. Attach the intended
acceptance image after changing configurations, or use the explicit config above.

The diagnostic owns `/fsdiag` on partition 1. A successful run removes it.
A failed run prints its stage and hexadecimal status and leaves that namespace
for inspection. Preserve the failure output and image; another `t` intentionally
refuses the existing namespace. Start with a fresh test image for a new run.

The diagnostic transfers across sector boundaries and checks zero-filled gaps,
stat, rename/move, file/directory removal, and allocation balance. Its 1,111-byte
test file forces growth at 512- and 1,024-byte block sizes; larger-block runs
check the same operations within their initial allocation. The existing
simulator suite separately covers allocation growth across all block sizes.

## Record results

Record the board revision, CF model, serial settings, and the bundle's
`SHA256SUMS` alongside the terminal log. Leave rows pending until actually run.

| Image | First `t` | Second `t` | Partition checks | Return/re-entry | Result |
|---|---|---|---|---|---|
| `cf-512.img` | Pending | Pending | Pending | Pending | Pending |
| `cf-1024.img` | Pending | Pending | Pending | Pending | Pending |
| `cf-2048.img` | Pending | Pending | Pending | Pending | Pending |
| `cf-4096.img` | Pending | Pending | Pending | Pending | Pending |
| `cf-8192.img` | Pending | Pending | Pending | Pending | Pending |
| `cf-16384.img` | Pending | Pending | Pending | Pending | Pending |
| `cf-32768.img` | Pending | Pending | Pending | Pending | Pending |
| `cf-65536.img` | Pending | Pending | Pending | Pending | Pending |

Report any failure with the command, stage/status, block size, and whether it
happened before or after a successful run. Once the agreed board checks pass,
continue with the game stages in [the implementation plan](mlfs_bios_extension_and_tetris.md).
