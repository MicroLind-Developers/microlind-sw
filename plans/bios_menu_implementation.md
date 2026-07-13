# µLind BIOS Menu System Implementation Plan

## Overview
This document outlines the complete implementation of the BIOS menu system for the µLind embedded operating system with all required utilities.

## Current State Analysis
The current `bios/src/mlbios.asm` file appears to be incomplete. It contains the menu structure but lacks the implementation of the actual menu choices and utilities.

## Implementation Requirements

### 1. Complete BIOS Menu System
- Implement the full menu with all 6 options:
  1. RAM test utility
  2. Serial port test utility
  3. Memory dump utility
  4. Joystick ports test utility
  5. Boot MLOS from CF
  6. WozMon (ROM monitor)

### 2. RAM Test Utility
- Implement memory testing functionality
- Write and read back test patterns
- Report test results

### 3. Serial Port Test Utility
- Test serial communication
- Send test messages
- Accept user input

### 4. Memory Dump Utility
- Implement memory reading functionality
- Display memory contents in hex format

### 5. Joystick Test Utility
- Read joystick input
- Display joystick states

### 6. Boot MLOS from CF Utility
- Implement CompactFlash boot functionality
- Load MLOS kernel from CompactFlash

### 7. WozMon Integration
- Integrate WozMon monitor in ROM area ($E000 - $F3FF)
- Provide access to ROM monitor

## File Structure
The implementation will be in `bios/src/mlbios.asm` with the following sections:
1. Header and includes
2. Variables and constants
3. Main entry point and menu logic
4. Individual utility functions
5. String tables

## Implementation Details

### Main Menu Structure
```
╒═══════════════════════════════════════╕
│    »»» µLind BIOS Utility Menu «««    │
╞═══════════════════════════════════════╡
│ 1. Ram test utility                   │
│ 2. Serial port test utility           │
│ 3. Memory dump utility                │
│ 4. Joystick ports test utility        │
│ 5. WozMon (ROM monitor)               │
│ 6. Boot MLOS from CF                  │
╘═══════════════════════════════════════╛
```

### Utility Function Requirements

#### RAM Test Utility
- Test memory at various addresses
- Write test patterns and verify
- Report success/failure

#### Serial Port Test Utility
- Send test message
- Wait for user input
- Verify communication

#### Memory Dump Utility
- Read memory locations
- Display in hex format
- Allow user navigation

#### Joystick Test Utility
- Read joystick input
- Display current state
- Test all directions

#### Boot MLOS from CF Utility
- Initialize CompactFlash
- Load MLOS from specific sector
- Jump to loaded code

#### WozMon Integration
- Load WozMon from ROM
- Provide monitor access
- Handle monitor exit

## Implementation Approach
1. Create complete menu system with all options
2. Implement each utility function
3. Integrate with existing BIOS functions
4. Ensure proper error handling
5. Add user-friendly prompts and messages

## Next Steps
1. Implement the complete `mlbios.asm` file
2. Implement individual utility functions
3. Integrate with existing BIOS drivers
4. Test all functionality