FORMAT = ihex
BUILD = build

SERIAL_SRC = ../../bios/init.asm  ../../driver/serial_xr88c92.asm ../../driver/mmu.asm ../../driver/led.asm ../../driver/parallel_6522.asm ../../driver/irq.asm ../../bios/memory.asm serial.asm
SERIAL_OBJ = $(SERIAL_SRC:.asm=.o)
SERIAL_BIN = $(BUILD)/serial.$(FORMAT)

all: serial

build: 
	mkdir -p $(BUILD)

serial: build 
	lwasm -3 -f $(FORMAT) -o $(SERIAL_BIN) $(SERIAL_SRC) 

clean:
	rm -f $(SERIAL_OBJ) $(SERIAL_BIN)