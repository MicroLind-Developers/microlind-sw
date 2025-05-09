FORMAT = ihex
BUILD = build

INTERRUPT_SRC = ../../driver/serial_xr88c92.asm	../../driver/led.asm ../../bios/init.asm

INTERRUPT_OBJ = $(INTERRUPT_SRC:.asm=.o)
INTERRUPT_BIN = $(BUILD)/interrupt.$(FORMAT)

all: interrupt

build: 
	mkdir -p $(BUILD)

interrupt: build 
	lwasm -3 -f $(FORMAT) -o $(INTERRUPT_BIN) $(INTERRUPT_SRC) 

clean:
	rm -f $(INTERRUPT_OBJ) $(INTERRUPT_BIN)