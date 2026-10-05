FORMAT ?= ihex
BUILD ?= build
LWASM ?= lwasm
PYTHON ?= python3
SIMULATOR ?= ../../microlind-sim/build/microlind-sim-cli
CC ?= cc
CMOC ?= cmoc

BIOS_BIN = $(BUILD)/bios.$(FORMAT)
BIOS_SYMBOLS = $(BUILD)/bios.sym
BIOS_LISTING = $(BUILD)/bios.lst
BIOS_CHECK_IMAGE = $(BUILD)/bios.ihex
BIOS_SOURCES = $(wildcard src/*.asm driver/*.asm include/*.inc) ../mlfs/lib/include/mlfs_types.inc
BIOS_TOOLS = tools/check_rom.py tools/image_formats.py
BIOS_RESOURCES = resources/petscii-swe.bin
FS_SOURCES = $(wildcard modules/filesystem/*.asm include/*.inc) ../mlfs/lib/include/mlfs_types.inc

.PHONY: all serial filesystem diagnostic check test test-sim test-sim-sex test-fs clean
all: serial filesystem diagnostic

filesystem: $(BUILD)/biosfs.mlp
diagnostic: $(BUILD)/fsdiag.mlp

$(BUILD)/filesystem_c_shim.o: modules/filesystem/filesystem_c_shim.asm include/filesystem.inc
	mkdir -p $(BUILD)
	$(LWASM) -f obj -o $@ $<

$(BUILD)/diagnostic_serial.o: modules/diagnostic/serial_shim.asm
	mkdir -p $(BUILD)
	$(LWASM) -f obj -o $@ $<

$(BUILD)/fsdiag_entry.ihex: modules/diagnostic/entry.asm include/module.inc
	mkdir -p $(BUILD)
	$(LWASM) -3 -f ihex -o $@ $<

$(BUILD)/fsdiag.srec: modules/diagnostic/diagnostic.c include/filesystem.h $(BUILD)/filesystem_c_shim.o $(BUILD)/diagnostic_serial.o Makefile
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=4000 --no-relocate -Iinclude -o $@ $< $(BUILD)/filesystem_c_shim.o $(BUILD)/diagnostic_serial.o

$(BUILD)/fsdiag.mlp: $(BUILD)/fsdiag.srec $(BUILD)/fsdiag_entry.ihex tools/pack_module.py tools/module_format.py tools/image_formats.py
	$(PYTHON) tools/pack_module.py $< $@ --overlay $(BUILD)/fsdiag_entry.ihex --kind application --memory-size 0x3C00

$(BUILD)/biosfs.ihex: $(FS_SOURCES) Makefile
	mkdir -p $(BUILD)
	$(LWASM) -3 -f ihex -Imodules/filesystem --list=$(BUILD)/biosfs.lst --symbol-dump=$(BUILD)/biosfs.sym -o $@ modules/filesystem/filesystem.asm

$(BUILD)/biosfs.mlp: $(BUILD)/biosfs.ihex tools/pack_module.py tools/module_format.py tools/image_formats.py tools/check_filesystem.py
	$(PYTHON) tools/pack_module.py $< $@ --kind filesystem --memory-size 0x8000
	$(PYTHON) tools/check_filesystem.py $@ --symbols $(BUILD)/biosfs.sym

# Validate address records even when another output format is selected.
serial: $(BUILD)/bios-$(FORMAT).verified

$(BUILD)/bios-$(FORMAT).verified: $(BIOS_SOURCES) $(BIOS_TOOLS) $(BIOS_RESOURCES) Makefile
	mkdir -p $(BUILD)
	$(LWASM) -3 -f ihex -Iinclude -Idriver -Isrc --list=$(BIOS_LISTING) --symbol-dump=$(BIOS_SYMBOLS) -o $(BIOS_CHECK_IMAGE) src/bios.asm
	$(PYTHON) tools/check_rom.py $(BIOS_CHECK_IMAGE) --symbols $(BIOS_SYMBOLS)
ifneq ($(FORMAT),ihex)
	$(LWASM) -3 -f $(FORMAT) -Iinclude -Idriver -Isrc -o $(BIOS_BIN) src/bios.asm
endif
	touch $@

check: serial
	$(PYTHON) tools/check_rom.py $(BIOS_CHECK_IMAGE) --symbols $(BIOS_SYMBOLS)

test: check
	$(PYTHON) -m unittest discover -s tests -v

test-sim: check
	$(PYTHON) tools/test_simulator.py --simulator $(SIMULATOR) --rom $(BIOS_CHECK_IMAGE) --symbols $(BIOS_SYMBOLS) --assembler $(LWASM)

test-sim-sex: check
	$(PYTHON) tools/diagnose_simulator.py --simulator $(SIMULATOR) --rom $(BIOS_CHECK_IMAGE) --symbols $(BIOS_SYMBOLS) --assembler $(LWASM)

test-fs: test-sim-sex filesystem diagnostic
	$(PYTHON) tools/test_filesystem.py --simulator $(SIMULATOR) --rom $(BIOS_CHECK_IMAGE) --symbols $(BIOS_SYMBOLS) --filesystem $(BUILD)/biosfs.mlp --diagnostic $(BUILD)/fsdiag.mlp --assembler $(LWASM) --cc $(CC)

clean:
	rm -f $(BUILD)/bios.* $(BUILD)/bios-*.verified
	rm -f $(BUILD)/biosfs.*
	rm -f $(BUILD)/fsdiag.* $(BUILD)/fsdiag_entry.ihex $(BUILD)/filesystem_c_shim.o $(BUILD)/diagnostic_serial.o
