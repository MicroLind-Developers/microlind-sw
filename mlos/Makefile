BUILD ?= build
LWASM ?= lwasm
CMOC ?= cmoc
PYTHON ?= python3
SIMULATOR ?= ../../microlind-sim/build/microlind-sim-cli
ASMFLAGS = -3 -p autobranchlength -Iinclude -Isrc -I../bios/mlos -I$(BUILD)
CORE_SOURCES = $(filter-out src/syscall_c_shim.asm,$(wildcard src/*.asm)) $(wildcard include/*.inc)
ROM_SOURCES = $(wildcard ../bios/mlos/*.asm ../bios/mlos/*.inc)
.PHONY: all check test clean fixtures provenance tools-check
all: tools-check $(BUILD)/mlos.ihex provenance runtime-check

tools-check:
	$(PYTHON) tools/check_tools.py --assembler $(LWASM) --cmoc $(CMOC)

$(BUILD):
	mkdir -p $@

$(BUILD)/core.raw: $(CORE_SOURCES) ../bios/mlos/hardware.inc | $(BUILD) tools-check
	$(LWASM) $(ASMFLAGS) -f raw --list=$(BUILD)/core.lst --symbol-dump=$(BUILD)/core.sym -o $@ src/kernel.asm

$(BUILD)/app.raw: tests/application.asm include/layout.inc include/syscalls.inc ../bios/mlos/hardware.inc | $(BUILD) tools-check
	$(LWASM) $(ASMFLAGS) -f raw --list=$(BUILD)/app.lst --symbol-dump=$(BUILD)/app.sym -o $@ $<

$(BUILD)/mlos.ihex: $(BUILD)/core.raw $(BUILD)/app.raw $(ROM_SOURCES) | $(BUILD)
	$(LWASM) $(ASMFLAGS) -f ihex --list=$(BUILD)/rom.lst --symbol-dump=$(BUILD)/rom.sym -o $@ ../bios/mlos/rom.asm
	$(PYTHON) tools/check_image.py --build $(BUILD)

provenance: $(BUILD)/mlos.ihex runtime-check tools/provenance.py
	$(PYTHON) tools/provenance.py --build $(BUILD) --assembler $(LWASM) --cmoc $(CMOC) --simulator $(SIMULATOR)

check: all
	$(PYTHON) tools/gen_abi.py --check
	$(PYTHON) tools/check_image.py --build $(BUILD)

fixtures: | $(BUILD)
	$(PYTHON) tools/fixtures.py --output $(BUILD)/fixtures

test: check fixtures $(BUILD)/cmoc_client.srec $(BUILD)/cmoc_entry.ihex
	$(PYTHON) tools/smoke.py --simulator $(SIMULATOR) --build $(BUILD)

clean:
	rm -rf $(BUILD)

$(BUILD)/syscall_c_shim.o: src/syscall_c_shim.asm include/syscalls.inc | $(BUILD) tools-check
	$(LWASM) -3 -Iinclude -f obj -o $@ $<

$(BUILD)/cmoc_client.srec: tests/cmoc_client.c include/syscalls.h $(BUILD)/syscall_c_shim.o
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=3A00 --no-relocate -Iinclude --intermediate --intdir=$(BUILD) -o $@ $< $(BUILD)/syscall_c_shim.o

$(BUILD)/cmoc_entry.ihex: tests/cmoc_entry.asm | $(BUILD)
	$(LWASM) -3 -f ihex -o $@ $<

# Production stages S03-S09 keep the original S00-S02 harness as a regression.
RUNTIME_FLAGS = $(ASMFLAGS) -I.
.PHONY: runtime runtime-test
runtime: $(BUILD)/boot.ihex $(BUILD)/console.img
$(BUILD)/runtime.raw: $(wildcard runtime/*.asm runtime/*.inc) $(CORE_SOURCES) | $(BUILD) tools-check
	$(LWASM) $(RUNTIME_FLAGS) -f raw --list=$(BUILD)/runtime.lst --symbol-dump=$(BUILD)/runtime.sym -o $@ runtime/kernel.asm
$(BUILD)/mlos.bin: $(BUILD)/runtime.raw tools/images.py
	$(PYTHON) tools/images.py $< $@
$(BUILD)/boot.ihex: $(ROM_SOURCES) include/images.inc include/layout.inc | $(BUILD)
	$(LWASM) $(RUNTIME_FLAGS) -f ihex --list=$(BUILD)/boot.lst --symbol-dump=$(BUILD)/boot.sym -o $@ ../bios/mlos/boot.asm
$(BUILD)/mkimage: tests/runtime/mkimage.c ../mlfs/lib/src/mlfs.c | $(BUILD)
	$(CC) -std=c99 -Wall -Wextra -Werror -Dtime=fixture_time -Dclock=fixture_clock -Drand=fixture_rand -I../mlfs/lib/include $^ -o $@
$(BUILD)/diagnostic.img: $(BUILD)/mkimage $(BUILD)/mlos.bin $(BUILD)/boundary.mlx
	$(BUILD)/mkimage $@ mlos.bin $(BUILD)/mlos.bin init.mlx $(BUILD)/init.mlx worker.mlx $(BUILD)/worker.mlx boundary.mlx $(BUILD)/boundary.mlx bad-checksum.mlx $(BUILD)/bad-checksum.mlx bad-layout.mlx $(BUILD)/bad-layout.mlx delay.mld $(BUILD)/delay.mld broken.mld $(BUILD)/bad-module.mld

$(BUILD)/%.ihex: programs/%.asm include/syscalls.inc | $(BUILD)
	$(LWASM) $(RUNTIME_FLAGS) -f ihex --symbol-dump=$(BUILD)/$*.sym -o $@ $<
$(BUILD)/%.mlx: $(BUILD)/%.ihex tools/pack_app.py tools/images.py
	$(PYTHON) tools/pack_app.py $< $@
$(BUILD)/diagnostic.img: $(BUILD)/init.mlx $(BUILD)/worker.mlx $(BUILD)/delay.mld
runtime-test: $(BUILD)/boot.ihex $(BUILD)/diagnostic.img
	$(PYTHON) tools/runtime_tests.py --build $(BUILD) --simulator $(SIMULATOR)

$(BUILD)/fs0.ihex: services/mlfs/worker.asm services/mlfs/validate.asm $(wildcard ../mlfs/target/*.asm) include/syscalls.inc | $(BUILD)
	$(LWASM) $(RUNTIME_FLAGS) -I../mlfs/target -f ihex --symbol-dump=$(BUILD)/fs0.sym -o $@ $<
$(BUILD)/fs0.mlx: $(BUILD)/fs0.ihex tools/pack_app.py tools/images.py
	$(PYTHON) tools/pack_app.py $< $@ --resident 7 --fill-gap 128 --zero 0x1000:0x2100 --bss-start 0xB600 --bss-size 0xA00
$(BUILD)/sdk.o: sdk/mlos.c sdk/mlos.h include/syscalls.h | $(BUILD)
	$(CMOC) -Werror --void-target -Isdk -Iinclude -c -o $@ $<
$(BUILD)/sdk_start.ihex: sdk/start.asm | $(BUILD)
	$(LWASM) -3 -f ihex -o $@ $<

$(BUILD)/filesystem.srec: services/filesystem.c sdk/fs.h $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=B000 --no-relocate -Isdk -Iinclude --intermediate --intdir=$(BUILD) -o $@ $< $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
$(BUILD)/filesystem.mlx: $(BUILD)/filesystem.srec $(BUILD)/sdk_start.ihex tools/pack_app.py
	$(PYTHON) tools/pack_app.py $< $@ --overlay $(BUILD)/sdk_start.ihex --cmoc-map $(BUILD)/filesystem.map --resident 3 --stack 0x7F80 --stack-size 2048

$(BUILD)/fs_sdk.o: sdk/fs.c sdk/fs.h | $(BUILD)
	$(CMOC) -Werror --void-target -Isdk -Iinclude -c -o $@ $<
$(BUILD)/console_init.srec: programs/console_init.c $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=3700 --no-relocate -Isdk -Iinclude --intermediate --intdir=$(BUILD) -o $@ $< $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
$(BUILD)/shell.srec: programs/shell.c $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=7700 --no-relocate -Isdk -Iinclude --intermediate --intdir=$(BUILD) -o $@ $< $(BUILD)/fs_sdk.o $(BUILD)/sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
$(BUILD)/command.srec: programs/command.c $(BUILD)/terminal.o $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=7700 --no-relocate -Isdk -Iinclude --intermediate --intdir=$(BUILD) -o $@ $< $(BUILD)/terminal.o $(BUILD)/fs_sdk.o $(BUILD)/sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
$(BUILD)/console_init.mlx: $(BUILD)/console_init.srec $(BUILD)/sdk_start.ihex tools/pack_app.py
	$(PYTHON) tools/pack_app.py $< $@ --overlay $(BUILD)/sdk_start.ihex --cmoc-map $(BUILD)/console_init.map
$(BUILD)/shell.mlx: $(BUILD)/shell.srec $(BUILD)/sdk_start.ihex tools/pack_app.py
	$(PYTHON) tools/pack_app.py $< $@ --overlay $(BUILD)/sdk_start.ihex --cmoc-map $(BUILD)/shell.map --resident 3 --stack 0x7F80 --stack-size 2048
$(BUILD)/command.mlx: $(BUILD)/command.srec $(BUILD)/sdk_start.ihex tools/pack_app.py
	$(PYTHON) tools/pack_app.py $< $@ --overlay $(BUILD)/sdk_start.ihex --cmoc-map $(BUILD)/command.map --resident 3 --stack 0x7F80 --stack-size 2048
# Compile common commands separately from the same guarded implementation.
# Keep the complete image for diagnostics and less frequent commands.
SMALL_COMMANDS = echo pwd ls cat cp mem
$(BUILD)/echo.srec: COMMAND_DEFINE = ECHO
$(BUILD)/pwd.srec: COMMAND_DEFINE = PWD
$(BUILD)/ls.srec: COMMAND_DEFINE = LS
$(BUILD)/cat.srec: COMMAND_DEFINE = CAT
$(BUILD)/cp.srec: COMMAND_DEFINE = CP
$(BUILD)/mem.srec: COMMAND_DEFINE = MEM
$(addprefix $(BUILD)/,$(addsuffix .srec,$(SMALL_COMMANDS))): $(BUILD)/%.srec: programs/command.c $(BUILD)/terminal.o $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=7700 --no-relocate -DMLOS_SINGLE_COMMAND -DMLOS_ONLY_$(COMMAND_DEFINE) -Isdk -Iinclude --intermediate --intdir=$(BUILD) -o $@ $< $(BUILD)/terminal.o $(BUILD)/fs_sdk.o $(BUILD)/sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
$(addprefix $(BUILD)/,$(addsuffix .mlx,$(SMALL_COMMANDS))): $(BUILD)/%.mlx: $(BUILD)/%.srec $(BUILD)/sdk_start.ihex tools/pack_app.py
	$(PYTHON) tools/pack_app.py $< $@ --overlay $(BUILD)/sdk_start.ihex --cmoc-map $(BUILD)/$*.map --resident 3 --stack 0x7F80 --stack-size 2048
CONSOLE_COMMANDS = dualtest staletest key recover unmount fstest echo pwd ls cat cp mkdir rm rmdir mv ps mem sleep yield mounts help
$(BUILD)/console.img: $(BUILD)/drivewait.mlx $(BUILD)/argtest.mlx $(BUILD)/fs1.mlx $(BUILD)/delay.mld $(BUILD)/mkimage $(BUILD)/mlos.bin $(BUILD)/console_init.mlx $(BUILD)/filesystem.mlx $(BUILD)/fs0.mlx $(BUILD)/shell.mlx $(BUILD)/command.mlx $(addprefix $(BUILD)/,$(addsuffix .mlx,$(SMALL_COMMANDS)))
	$(BUILD)/mkimage $@ mlos.bin $(BUILD)/mlos.bin init.mlx $(BUILD)/console_init.mlx filesystem.mlx $(BUILD)/filesystem.mlx fs0.mlx $(BUILD)/fs0.mlx fs1.mlx $(BUILD)/fs1.mlx shell.mlx $(BUILD)/shell.mlx delay.mld $(BUILD)/delay.mld argtest.mlx $(BUILD)/argtest.mlx drivewait.mlx $(BUILD)/drivewait.mlx $(foreach name,$(CONSOLE_COMMANDS),$(name).mlx $(if $(filter $(name),$(SMALL_COMMANDS)),$(BUILD)/$(name).mlx,$(BUILD)/command.mlx))

.PHONY: console-test
console-test: runtime
	$(PYTHON) tools/console_tests.py --build $(BUILD) --simulator $(SIMULATOR)

$(BUILD)/delay.raw: modules/delay.asm include/syscalls.inc runtime/state.inc | $(BUILD)
	$(LWASM) $(RUNTIME_FLAGS) -f raw --symbol-dump=$(BUILD)/delay.sym -o $@ $<
$(BUILD)/delay.mld: $(BUILD)/delay.raw tools/pack_module.py
	$(PYTHON) tools/pack_module.py $< $@ --bind 0x4000 --poll 0x401E --stop 0x4039

$(BUILD)/fs1.ihex: services/mlfs/worker.asm services/mlfs/validate.asm $(wildcard ../mlfs/target/*.asm) include/syscalls.inc | $(BUILD)
	$(LWASM) $(RUNTIME_FLAGS) -DFW_DEVICE=1 -I../mlfs/target -f ihex --symbol-dump=$(BUILD)/fs1.sym -o $@ $<
$(BUILD)/fs1.mlx: $(BUILD)/fs1.ihex tools/pack_app.py tools/images.py
	$(PYTHON) tools/pack_app.py $< $@ --resident 7 --fill-gap 128 --zero 0x1000:0x2100 --bss-start 0xB600 --bss-size 0xA00

.PHONY: boot-test
boot-test: $(BUILD)/boot.ihex $(BUILD)/diagnostic.img
	$(PYTHON) tools/boot_tests.py --build $(BUILD) --simulator $(SIMULATOR)

$(BUILD)/terminal.o: sdk/terminal.c sdk/terminal.h | $(BUILD)
	$(CMOC) -Werror --void-target -Isdk -Iinclude -c -o $@ $<

$(BUILD)/heap.o: sdk/heap.c sdk/mlos.h | $(BUILD)
	$(CMOC) -Werror --void-target -Isdk -Iinclude -c -o $@ $<
$(BUILD)/argtest.srec: programs/argtest.c $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=3700 --no-relocate -Isdk -Iinclude --intermediate --intdir=$(BUILD) -o $@ $< $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
$(BUILD)/argtest.mlx: $(BUILD)/argtest.srec $(BUILD)/sdk_start.ihex tools/pack_app.py
	$(PYTHON) tools/pack_app.py $< $@ --overlay $(BUILD)/sdk_start.ihex --cmoc-map $(BUILD)/argtest.map

$(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/terminal.o: $(wildcard sdk/*.h include/*.h)
$(BUILD)/boot.ihex: ../bios/driver/compactflash.asm

$(BUILD)/bad-checksum.mlx: $(BUILD)/worker.mlx
	$(PYTHON) -c 'from pathlib import Path; p=bytearray(Path("$<").read_bytes()); p[24]^=1; Path("$@").write_bytes(p)'
$(BUILD)/bad-layout.mlx: $(BUILD)/worker.mlx
	$(PYTHON) -c 'from pathlib import Path; p=bytearray(Path("$<").read_bytes()); p[32:34]=bytes.fromhex("3F80"); Path("$@").write_bytes(p)'
$(BUILD)/bad-module.mld: $(BUILD)/delay.mld
	$(PYTHON) -c 'from pathlib import Path; p=bytearray(Path("$<").read_bytes()); p[24]^=1; Path("$@").write_bytes(p)'
$(BUILD)/diagnostic.img: $(BUILD)/bad-checksum.mlx $(BUILD)/bad-layout.mlx $(BUILD)/bad-module.mld

.PHONY: image-test acceptance
image-test: runtime
	$(PYTHON) tests/test_images.py --build $(BUILD)
acceptance:
	$(MAKE) test
	$(MAKE) runtime-test
	$(MAKE) boot-test
	$(MAKE) console-test
	$(MAKE) image-test
	$(MAKE) runtime-check
	$(MAKE) session-test

.PHONY: runtime-check
runtime-check: runtime
	$(PYTHON) tools/gen_abi.py --check
	$(PYTHON) tools/runtime_budget.py --build $(BUILD)

.PHONY: session-test
session-test: runtime-check
	$(PYTHON) tools/session_test.py --build $(BUILD) --simulator $(SIMULATOR)

# Opt-in benchmark; runs real UART commands on private CF copies.
.PHONY: response-profile
response-profile: runtime-check
	$(PYTHON) tools/response_profile.py --build $(BUILD) --simulator $(SIMULATOR)

$(BUILD)/drivewait.srec: programs/drivewait.c $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=3700 --no-relocate -Isdk -Iinclude --intermediate --intdir=$(BUILD) -o $@ $< $(BUILD)/sdk.o $(BUILD)/fs_sdk.o $(BUILD)/heap.o $(BUILD)/syscall_c_shim.o
$(BUILD)/drivewait.mlx: $(BUILD)/drivewait.srec $(BUILD)/sdk_start.ihex tools/pack_app.py
	$(PYTHON) tools/pack_app.py $< $@ --overlay $(BUILD)/sdk_start.ihex --cmoc-map $(BUILD)/drivewait.map

$(BUILD)/fs0.ihex $(BUILD)/fs1.ihex: ../mlfs/lib/include/mlfs_types.inc ../bios/include/filesystem.inc ../bios/include/module.inc

$(BUILD)/boundary.mlx: $(BUILD)/boundary.ihex tools/pack_app.py tools/images.py
	$(PYTHON) tools/pack_app.py $< $@ --resident 7 --stack 0xBF80 --stack-size 1024 --zero 0x3FF0:32
