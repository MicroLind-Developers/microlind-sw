FORMAT = ihex
BUILD = build

SRC = src/kernel.asm src/memory_manager.asm src/syscall_dispatch.asm src/syscall_c_shim.asm
BIN = $(BUILD)/mlos.$(FORMAT)

all: $(BIN)

$(BUILD):
	mkdir -p $(BUILD)

$(BIN): $(BUILD) $(SRC) include/mlos.inc include/syscall.inc
	lwasm -3 -f $(FORMAT) -Iinclude -o $(BIN) $(SRC)

clean:
	rm -f $(BIN)
