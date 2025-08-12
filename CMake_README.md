# Microlind Software - CMake Build System

This directory now uses CMake instead of Makefiles for building the microlind software components.

## Prerequisites

- CMake 3.16 or higher
- LWTOOLS (lwasm assembler) - must be available in your PATH
- CMOC (Color Computer C compiler) - for C test compilation
- A C++ compiler (for CMake itself)

## Building

### Basic Build

```bash
# Create a build directory
mkdir build
cd build

# Configure the project
cmake ..

# Build all targets using make
make

# Or alternatively using cmake
cmake --build .
```

### Building Specific Targets

You can build specific targets using:

```bash
# Build the stage3 test (serial BIOS)
cmake --build . --target serial

# Build the main BIOS
cmake --build . --target bios

# Build the wozmon BIOS
cmake --build . --target wozmon

# Build prototype tests
cmake --build . --target irq_proto_test
cmake --build . --target parallel_proto_test
cmake --build . --target ps2_proto_test

# Build stage2 blink test
cmake --build . --target blink

# Build C test (using cmoc compiler)
cmake --build . --target c-test

### Clean Build

```bash
# Clean build artifacts
cmake --build . --target clean

# Or remove the entire build directory
rm -rf build
```

## Project Structure

The CMake build system is organized as follows:

- **Root CMakeLists.txt**: Main configuration and prototype test builds
- **bios/CMakeLists.txt**: BIOS builds (serial, etc.)
- **wozmon/CMakeLists.txt**: Wozmon monitor builds
- **tests/stage3_test/CMakeLists.txt**: Stage 3 test builds
- **tests/stage2_blink/CMakeLists.txt**: Stage 2 blink test
- **tests/c-test/CMakeLists.txt**: C test using cmoc compiler
- **Other test directories**: Placeholder CMakeLists.txt files for future implementation

## Output Format

All builds produce Intel HEX format files (`.ihex`) using the LWTOOLS `lwasm` assembler with the following flags:
- `-3`: 6309 mode
- `-f ihex`: Intel HEX output format
- `-I <include_dir>`: Include directories for assembly files

C tests produce S-Record format files (`.srec`) using the CMOC compiler with the following flags:
- `--srec`: S-Record output format
- `--org=<address>`: Application origin address
- `--data=<address>`: Data segment address
- `-I <include_dir>`: Include directories for C files

## Build Container Usage

When building in a container with all tools available:

```bash
# In your build container
cd /workspace/microlind-sw
mkdir build && cd build
cmake ..

# Build everything with make
make

# Or build specific targets
make serial
make c-test
make bios-build
make wozmon-build
```

The build system will automatically:
- Create necessary build directories
- Find and use the `lwasm` assembler and `cmoc` compiler
- Generate Intel HEX and S-Record output files
- Handle dependencies between source files
- Allow you to use `make` for building after running `cmake`

## Converting More Makefiles

To convert additional Makefiles to CMake:

1. Create a `CMakeLists.txt` in the target directory
2. Use `add_custom_command()` for the build steps
3. Use `add_custom_target()` for the targets
4. Add the directory to the parent `CMakeLists.txt` with `add_subdirectory()`

## Troubleshooting

- **lwasm not found**: Ensure LWTOOLS is installed and in your PATH
- **cmoc not found**: Ensure CMOC is installed and in your PATH for C test compilation
- **Build errors**: Check that all source files exist and paths are correct
- **CMake version**: Ensure you have CMake 3.16 or higher
