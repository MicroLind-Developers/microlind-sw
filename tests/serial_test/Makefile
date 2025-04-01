DRIVER_SRC = ../../driver/init.asm ../../driver/serial_xr88c92.asm ../../driver/mmu.asm ../../driver/parallel_6522.asm ../../driver/irq.asm 
FORMAT = ihex
BUILD = build

SERIAL_TEST_SRC = $(DRIVER_SRC) start.asm
SERIAL_TEST_OBJ = $(SERIAL_TEST_SRC:.asm=.o)
SERIAL_TEST_BIN = $(BUILD)/start.$(FORMAT)

all: start

start:
	lwasm -3 -f $(FORMAT) -o $(SERIAL_TEST_BIN) $(SERIAL_TEST_SRC)

clean:
	rm -f $(SERIAL_TEST_OBJ) $(SERIAL_TEST_BIN)