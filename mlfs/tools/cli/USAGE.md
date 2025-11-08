# MLFS CLI Enhanced Usage Guide

This document describes the enhanced CLI functionality including subdirectory navigation and quoted string handling.

## New Features

### 1. Quoted String Support for File Content

The CLI now properly handles quoted strings, allowing spaces and special characters in file content:

```bash
# Write content with spaces
write myfile.txt "Hello World with spaces!"

# Write content with special characters  
write config.txt "key=value\nport=8080\ndebug=true"

# Use escape sequences
write formatted.txt "Line 1\nLine 2\tTabbed content"
```

**Supported escape sequences:**
- `\n` → newline
- `\t` → tab
- `\r` → carriage return
- `\\` → backslash
- `\"` → quote mark

### 2. Directory Navigation

#### Change Directory (`cd`)
Navigate between directories in the filesystem:

```bash
# Go to root directory
cd /

# Enter a directory (from root)
cd mydir

# Go to parent directory  
cd ..

# Stay in current directory
cd .
```

#### Print Working Directory (`pwd`)
Display the current directory path:

```bash
pwd
# Output: /mydir
```

### 3. Enhanced Prompt

The CLI prompt now shows both the image file and current directory:

```
# When not mounted
mlfs> 

# When mounted in root directory
mlfs:disk.img:/> 

# When mounted in subdirectory
mlfs:disk.img:/mydir>
```

## Updated Command Usage

### File Operations with Directory Context

All file operations now work relative to the current directory:

```bash
# Create file in current directory
touch readme.txt

# Create file in root (absolute path)
touch /global.txt

# Write to file in current directory
write config.ini "setting=value"

# Read file in current directory
cat readme.txt

# Remove file in current directory
rm config.ini
```

### Directory Operations

```bash
# List current directory contents
ls

# List specific directory
ls /
ls mydir

# Create directory in current location
mkdir newdir

# Remove empty directory
rmdir olddir
```

## Complete Workflow Example

```bash
# 1. Create and mount a filesystem
format test.img 32 4096
mount test.img

# 2. Create directories and nested subdirectories
mkdir documents
mkdir photos  
mkdir config
cd documents
mkdir reports
mkdir presentations
mkdir drafts
cd reports
mkdir 2023
mkdir 2024
cd ..

# 3. Create files with spaces in content using absolute paths
write /readme.txt "Welcome to MLFS!\nThis filesystem now supports nested directories!"
write /config/settings.ini "app_name=MyApp\nversion=2.0\nnested_dirs=true"

# 4. Navigate nested directories
cd /documents/reports/2024
pwd  # Shows: /documents/reports/2024

# 5. Create files in deep subdirectory
touch quarterly_report.txt
write quarterly_report.txt "Q1 2024 Report\n==============\nSubdirectory support is working perfectly!"

# 6. Test relative navigation
cd ../../presentations  # Go up 2 levels then down to presentations
pwd  # Shows: /documents/presentations
touch slides.ppt
cd ../reports/2023      # Relative navigation between subdirs
touch annual_report.txt

# 7. List contents at various levels
ls /                    # Root directory
ls /documents          # Documents directory  
ls /documents/reports  # Reports subdirectory
ls .                   # Current directory (2023)

# 8. Read files from different locations
cat /readme.txt                           # Absolute path
cat ../2024/quarterly_report.txt         # Relative path up and down
cd /
cat documents/reports/2024/quarterly_report.txt  # Absolute nested path

# 9. Create files in subdirectories from root using relative paths
cd photos
mkdir vacation
mkdir work
cd vacation
mkdir beach
mkdir mountains
cd beach
write sunset.jpg "Beautiful sunset photo metadata"
cd /photos/work
write meeting.jpg "Team meeting photo"

# 10. Test path resolution and navigation
pwd
cd ../vacation/mountains
pwd  # Shows: /photos/vacation/mountains
cd /documents/reports
pwd  # Shows: /documents/reports
cd ../../config
pwd  # Shows: /config
```

## Current Limitations

1. **File Size**: The `cat` command is limited to displaying files up to 4KB in size.

2. **Directory Depth**: Supports up to 16 levels of nested directories.

## Error Messages

The CLI provides helpful error messages for common issues:

- `"Error: Directory 'name' not found"` - Trying to cd into non-existent directory  
- `"Error: 'name' is not a directory"` - Trying to cd into a file
- `"Error: Invalid path 'path'"` - Malformed path string
- `"Error: Path too long"` - Path exceeds maximum length limit
- `"Error: Failed to create directory/file 'name' (error N)"` - Various filesystem errors

## Technical Implementation

### Quoted String Parsing
- Uses manual parsing instead of `strtok()` to preserve spaces
- Supports escape sequence processing
- Handles unterminated quotes gracefully

### Directory Context
- CLI state tracks current working directory
- Path resolution handles both absolute and relative paths  
- Commands use `resolve_path()` to convert user input to MLFS-compatible paths
- Current directory initialized to "/" on mount

### Command Integration
- All file operations (`touch`, `cat`, `write`, `rm`) support path resolution
- Directory operations (`ls`, `mkdir`, `rmdir`, `cd`) work with current context
- Consistent error handling across all commands
