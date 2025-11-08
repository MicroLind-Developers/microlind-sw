FORMAT = ihex
BUILD = build

BIOS_SRC = 	../../bios/init.asm  \
			../../bios/mlbios.asm \
			../../driver/serial_xr88c92.asm \
			../../driver/mmu.asm \
			../../driver/rtc.asm \
			../../driver/ps2.asm \
			../../driver/parallel_6522.asm \
			../../driver/irq.asm \
			../../bios/memory.asm
			
BIOS_OBJ = $(BIOS_SRC:.asm=.o)
BIOS_BIN = $(BUILD)/bios.$(FORMAT)
BIOS_HEADER = ../../driver

all: serial

build: 
	mkdir -p $(BUILD)

serial: build 
	lwasm -3 -f $(FORMAT) -I $(BIOS_HEADER) -o $(BIOS_BIN) $(BIOS_SRC)  

clean:
	rm -f $(BIOS_OBJ) $(BIOS_BIN)