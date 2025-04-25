FORMAT = ihex
BUILD = build

INTERRUPT_SRC = ../../bios/init.asm  ../../driver/serial_xr88c92.asm ../../driver/mmu.asm ../../driver/led.asm ../../driver/parallel_6522.asm ../../driver/irq.asm ../../bios/memory.asm  interrupt.asm
INTERRUPT_OBJ = $(INTERRUPT_SRC:.asm=.o)
INTERRUPT_BIN = $(BUILD)/interrupt.$(FORMAT)

all: interrupt

build: 
	mkdir -p $(BUILD)

interrupt: build 
	lwasm -3 -f $(FORMAT) -o $(INTERRUPT_BIN) $(INTERRUPT_SRC) 

clean:
	rm -f $(INTERRUPT_OBJ) $(INTERRUPT_BIN)