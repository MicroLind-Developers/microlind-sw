FORMAT = ihex
BUILD = build

SERIAL_SRC = src/mlbios.asm src/config.asm src/mlfs.asm driver/compactflash.asm driver/serial_xr88c92.asm driver/mmu.asm driver/parallel_6522.asm driver/vdc.asm driver/vdc_font.asm driver/irq.asm src/memory.asm src/init.asm
SERIAL_RESOURCES = resources/petscii-swe.bin
SERIAL_OBJ = $(SERIAL_SRC:.asm=.o)
SERIAL_BIN = $(BUILD)/bios.$(FORMAT)

all: serial

build: 
	mkdir -p $(BUILD)

serial: build $(SERIAL_RESOURCES)
	lwasm -3 -f $(FORMAT) -Iinclude -Idriver -o $(SERIAL_BIN) $(SERIAL_SRC)

clean:
	rm -f $(SERIAL_OBJ) $(SERIAL_BIN)
