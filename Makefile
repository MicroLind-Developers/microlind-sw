DRIVER_SRC = driver/serial_6552.asm
FORMAT = ihex
BUILD = build

IRQ_SRC = $(DRIVER_SRC) proto/irq_proto_test.asm driver/irq.asm
IRQ_OBJ = $(IRQ_SRC:.asm=.o)
IRQ_BIN = $(BUILD)/irq_test.$(FORMAT)

PARALLEL_SRC = $(DRIVER_SRC) driver/parallel_6522.asm proto/parallel_proto_test.asm
PARALLEL_OBJ = $(PARALLEL_SRC:.asm=.o)
PARALLEL_BIN = $(BUILD)/parallel_test.$(FORMAT)

PS2_SRC = $(DRIVER_SRC) proto/ps2_proto_test.asm driver/ps2.asm
PS2_OBJ = $(PS2_SRC:.asm=.o)
PS2_BIN = $(BUILD)/ps2_test.$(FORMAT)

all: irq_proto_test parallel_proto_test ps2_proto_test

irq_proto_test: 
	lwasm -3 -f $(FORMAT) -o $(IRQ_BIN) $(IRQ_SRC)

parallel_proto_test: 
	lwasm -3 -f $(FORMAT) -o $(PARALLEL_BIN) $(PARALLEL_SRC)

ps2_proto_test: 
	lwasm -3 -f $(FORMAT) -o $(PS2_BIN) $(PS2_SRC)

clean:
	rm -f $(IRQ_OBJ) $(IRQ_BIN) $(PARALLEL_BIN) $(PARALLEL_OBJ) $(PS2_BIN)