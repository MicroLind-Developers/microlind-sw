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
TETRIS_RULES = modules/tetris/game.c modules/tetris/game.h tests/tetris_rules.c

.PHONY: all serial filesystem diagnostic tetris check test test-sim test-sim-sex test-fs test-tetris-rules test-tetris clean
all: serial filesystem diagnostic tetris

filesystem: $(BUILD)/biosfs.mlp
diagnostic: $(BUILD)/fsdiag.mlp
tetris: $(BUILD)/tetris.mlp

$(BUILD)/tetris_controls.o: modules/tetris/controls.c modules/tetris/controls.h modules/tetris/game.h include/integer.h
	mkdir -p $(BUILD)
	$(CMOC) -Werror --void-target -DTETRIS_TARGET -Iinclude -Imodules/tetris -c -o $@ $<

$(BUILD)/tetris_save.o: modules/tetris/save.c modules/tetris/save.h modules/tetris/game.h include/integer.h
	mkdir -p $(BUILD)
	$(CMOC) -Werror --void-target -DTETRIS_TARGET -Iinclude -Imodules/tetris -c -o $@ $<

$(BUILD)/tetris_platform.o: modules/tetris/platform.asm include/module.inc include/filesystem.inc include/io.inc include/memory.inc
	mkdir -p $(BUILD)
	$(LWASM) -3 -f obj -o $@ $<

$(BUILD)/tetris_entry.ihex: modules/tetris/entry.asm include/module.inc
	mkdir -p $(BUILD)
	$(LWASM) -3 -f ihex -o $@ $<

$(BUILD)/tetris.srec: modules/tetris/application.c $(wildcard modules/tetris/*.h) include/filesystem.h $(BUILD)/tetris_game.o $(BUILD)/tetris_controls.o $(BUILD)/tetris_save.o $(BUILD)/tetris_platform.o $(BUILD)/filesystem_c_shim.o Makefile
	$(CMOC) -Werror --void-target --srec --org=0500 --limit=4000 --no-relocate -DTETRIS_TARGET -Iinclude -Imodules/tetris --intermediate --intdir=$(BUILD) -o $@ $< $(BUILD)/tetris_game.o $(BUILD)/tetris_controls.o $(BUILD)/tetris_save.o $(BUILD)/tetris_platform.o $(BUILD)/filesystem_c_shim.o

$(BUILD)/tetris.mlp: $(BUILD)/tetris.srec $(BUILD)/tetris_entry.ihex tools/pack_module.py tools/module_format.py tools/image_formats.py
	$(PYTHON) tools/pack_module.py $< $@ --overlay $(BUILD)/tetris_entry.ihex --kind application --memory-size 0x3C00

$(BUILD)/tetris_game.o: modules/tetris/game.c modules/tetris/game.h include/integer.h
	mkdir -p $(BUILD)
	$(CMOC) -Werror --void-target -DTETRIS_TARGET -Iinclude -Imodules/tetris -c -o $@ $<

$(BUILD)/tetris_rules_host: $(TETRIS_RULES) Makefile
	mkdir -p $(BUILD)
	$(CC) -std=c99 -Wall -Wextra -Werror -Imodules/tetris tests/tetris_rules.c modules/tetris/game.c -o $@

$(BUILD)/tetris_rules.srec: $(TETRIS_RULES) $(BUILD)/tetris_game.o $(BUILD)/diagnostic_serial.o Makefile
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=4000 --no-relocate -DTETRIS_TARGET -Iinclude -Imodules/tetris -o $@ tests/tetris_rules.c $(BUILD)/tetris_game.o $(BUILD)/diagnostic_serial.o

$(BUILD)/tetris_rules.mlp: $(BUILD)/tetris_rules.srec $(BUILD)/fsdiag_entry.ihex tools/pack_module.py tools/module_format.py tools/image_formats.py
	$(PYTHON) tools/pack_module.py $< $@ --overlay $(BUILD)/fsdiag_entry.ihex --kind application --memory-size 0x3C00

$(BUILD)/tetris_io_host: tests/tetris_io.c modules/tetris/controls.c modules/tetris/controls.h modules/tetris/save.c modules/tetris/save.h modules/tetris/game.h Makefile
	mkdir -p $(BUILD)
	$(CC) -std=c99 -Wall -Wextra -Werror -Imodules/tetris tests/tetris_io.c modules/tetris/controls.c modules/tetris/save.c -o $@

$(BUILD)/tetris_io.srec: tests/tetris_io.c $(wildcard modules/tetris/*.h) $(BUILD)/tetris_controls.o $(BUILD)/tetris_save.o $(BUILD)/diagnostic_serial.o Makefile
	$(CMOC) -Werror --void-target --srec --org=0420 --limit=4000 --no-relocate -DTETRIS_TARGET -Iinclude -Imodules/tetris -o $@ $< $(BUILD)/tetris_controls.o $(BUILD)/tetris_save.o $(BUILD)/diagnostic_serial.o

$(BUILD)/tetris_io.mlp: $(BUILD)/tetris_io.srec $(BUILD)/fsdiag_entry.ihex tools/pack_module.py tools/module_format.py tools/image_formats.py
	$(PYTHON) tools/pack_module.py $< $@ --overlay $(BUILD)/fsdiag_entry.ihex --kind application --memory-size 0x3C00

test-tetris-rules: test-sim-sex filesystem $(BUILD)/tetris_rules_host $(BUILD)/tetris_rules.mlp
	$(BUILD)/tetris_rules_host
	$(PYTHON) tools/test_tetris.py --simulator $(SIMULATOR) --rom $(BIOS_CHECK_IMAGE) --symbols $(BIOS_SYMBOLS) --filesystem $(BUILD)/biosfs.mlp --rules $(BUILD)/tetris_rules.mlp --cc $(CC)

test-tetris: test-sim-sex filesystem diagnostic tetris $(BUILD)/tetris_rules_host $(BUILD)/tetris_rules.mlp $(BUILD)/tetris_io_host $(BUILD)/tetris_io.mlp
	$(BUILD)/tetris_rules_host
	$(BUILD)/tetris_io_host
	$(PYTHON) tools/test_tetris.py --simulator $(SIMULATOR) --rom $(BIOS_CHECK_IMAGE) --symbols $(BIOS_SYMBOLS) --filesystem $(BUILD)/biosfs.mlp --rules $(BUILD)/tetris_rules.mlp --io-tests $(BUILD)/tetris_io.mlp --game $(BUILD)/tetris.mlp --game-map $(BUILD)/tetris.map --diagnostic $(BUILD)/fsdiag.mlp --cc $(CC)

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

$(BUILD)/biosfs.ihex: $(FS_SOURCES) $(wildcard ../mlfs/target/*.asm) Makefile
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
	rm -f $(BUILD)/tetris_game.o $(BUILD)/tetris_rules.o $(BUILD)/tetris_rules.srec $(BUILD)/tetris_rules.mlp $(BUILD)/tetris_rules_host
	rm -f $(BUILD)/tetris.mlp $(BUILD)/tetris.srec $(BUILD)/tetris.map $(BUILD)/tetris.link $(BUILD)/tetris_entry.ihex $(BUILD)/tetris_platform.o $(BUILD)/tetris_controls.o $(BUILD)/tetris_save.o $(BUILD)/application.o $(BUILD)/application.s
	rm -f $(BUILD)/tetris_io.srec $(BUILD)/tetris_io.mlp $(BUILD)/tetris_io_host
