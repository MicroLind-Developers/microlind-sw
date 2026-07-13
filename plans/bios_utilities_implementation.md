# µLind BIOS Utilities Implementation

## Overview
This document outlines the detailed implementation of each BIOS utility function for the µLind system.

## 1. RAM Test Utility Function

### Purpose
Test the system's RAM for basic functionality and detect errors.

### Implementation Plan
- Initialize memory test at various addresses or load in all available memory banks in bank 1 and test all of them. 
  To be able to test all banks the currently loaded bank (that has the stack and usage variables in it) needs to be swapped during the test execution. 
- Write test patterns (0x00, 0xFF, 0x55, 0xAA)
- Read back and verify patterns
- Report any errors found
- Display test results

### Key Functions
```assembly
_RAM_TEST_FUNCTION:
    ; Initialize test
    ; Test one bank and swap with current bank for stack and variables.
    ; Repeat for all banks
    ;       Load next bank
    ;       Write test patterns to memory
    ;       Read back and verify

    ; Report results
    rts
```

## 2. Serial Port Test Utility Function

### Purpose
Verify that the serial communication is working properly.

### Implementation Plan
- Send a test message to serial port
- Wait for user input to confirm receipt
- Verify communication is functional
- Report test status

### Key Functions
```assembly
_SERIAL_TEST_FUNCTION:
    ; Send test message
    ; Wait for input
    ; Verify communication
    rts
```

## 3. Memory Dump Utility Function

### Purpose
Display memory contents at specified addresses.

### Implementation Plan
- Accept memory address input from user
- Read memory contents
- Display in hex format
- Allow navigation through memory
- Provide user-friendly interface

### Key Functions
```assembly
_MEMORY_DUMP_FUNCTION:
    ; Get address input
    ; Read memory
    ; Display in hex format
    ; Handle user navigation
    rts
```

## 4. Joystick Test Utility Function

### Purpose
Test joystick input functionality.

### Implementation Plan
- Read joystick input from parallel port
- Display current joystick state
- Test all directions
- Report joystick status

### Key Functions
```assembly
_JOYSTICK_TEST_FUNCTION:
    ; Read joystick 1
    ; Read joystick 2
    ; Display states
    ; Test directions
    rts
```

## 5. WozMon Integration

### Purpose
Provide access to the WozMon ROM monitor.

### Implementation Plan
- Load WozMon from ROM area ($E000 - $F3FF)
- Set up proper entry point
- Provide access to monitor
- Handle monitor exit

### Key Functions
```assembly
_WOZMON_FUNCTION:
    ; Load WozMon
    ; Jump to monitor
    ; Handle exit
    rts
```

## 6. Boot MLOS from CF Utility Function

### Purpose
Load and execute the MLOS kernel from CompactFlash.

### Implementation Plan
- Initialize CompactFlash driver
- Read MLOS kernel from specific sector
- Load kernel into memory
- Jump to kernel entry point
- Handle error conditions

### Key Functions
```assembly
_BOOT_MLOS_FUNCTION:
    ; Initialize CF
    ; Read MLOS from CF
    ; Load into memory
    ; Jump to kernel
    rts
```

## Integration with BIOS System

### BIOS Function Calls Available
- `SERIAL_PRINT_A` - Print string from X
- `SERIAL_INPUT_A` - Read input to buffer
- `MMU_SET_REGISTER` - Set MMU registers
- `READ_JOY1` - Read joystick 1
- `READ_JOY2` - Read joystick 2
- `CF_READ_SECTOR` - Read from CompactFlash
- `CF_INIT` - Initialize CompactFlash

### Memory Layout
- ROM area: $E000 - $F3FF (for WozMon)
- RAM area: $0000 - $DFFF (for system use)
- Stack: $E000 (initialized in init.asm)

## Error Handling
- All functions should handle errors gracefully
- Provide meaningful error messages
- Return to main menu on error
- Ensure system stability

## User Interface
- Clear prompts for user actions
- Visual feedback for operations
- Consistent formatting
- Help information where appropriate

## Testing Approach
- Unit test each utility function
- Integration test with BIOS system
- Verify all menu options work
- Test error conditions
- Validate memory usage