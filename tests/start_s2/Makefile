DRIVER_SRC = 
FORMAT = ihex
BUILD = build

BUS_CHECK_SRC = $(DRIVER_SRC) bus_check.asm
BUS_CHECK_OBJ = $(BUS_CHECK_SRC:.asm=.o)
BUS_CHECK_BIN = $(BUILD)/bus_check.$(FORMAT)

all: bus_check

bus_check:
	lwasm -3 -f $(FORMAT) -o $(BUS_CHECK_BIN) $(BUS_CHECK_SRC)

clean:
	rm -f $(BUS_CHECK_OBJ) $(BUS_CHECK_BIN)