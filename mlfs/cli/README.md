# MLFS CLI - Command Line Interface

A command-line interface for creating, mounting, and manipulating MLFS (MicroLind File System) disk images.

## Building

### Prerequisites

The CLI requires the readline library for enhanced command line editing:

```bash
# Ubuntu/Debian
sudo apt-get install libreadline-dev

# RHEL/CentOS/Fedora  
sudo yum install readline-devel  # or dnf install readline-devel

# macOS
brew install readline
```

### Build Instructions

From the main mlfs directory:

```bash
mkdir build && cd build
cmake ..
make mlfs_cli
```

The executable will be created as `build/cli/mlfs`.

## Usage

### Basic Usage

```bash
./mlfs                    # Start interactive CLI
./mlfs disk.img          # Start CLI and mount disk.img
```

### Available Commands

| Command | Usage | Description |
|---------|-------|-------------|
| `help` | `help` | Show all available commands |
| `format` | `format <file> [size_mb] [block_size]` | Create and format new disk image |
| `mount` | `mount <image_file>` | Mount a disk image |
| `unmount` | `unmount` | Unmount current disk image |
| `ls` | `ls [path]` | List directory contents |
| `mkdir` | `mkdir <name>` | Create directory |
| `rmdir` | `rmdir <name>` | Remove empty directory |
| `touch` | `touch <name> [blocks]` | Create empty file |
| `rm` | `rm <name>` | Remove file |
| `cat` | `cat <name>` | Display file contents |
| `write` | `write <name> <content>` | Write content to file |
| `info` | `info` | Show filesystem information |
| `quit` | `quit` or `exit` | Exit CLI |

## Example Workflow

### Creating a New Filesystem

```bash
$ ./mlfs
mlfs> format mydisk.img 128 4096    # Create 128MB disk with 4KB blocks
Creating mydisk.img: 128 MB, block size 4096 bytes...
Successfully created and formatted 'mydisk.img'

mlfs> mount mydisk.img
Successfully mounted 'mydisk.img'
Block size: 4096 bytes, Total blocks: 32768

mlfs:mydisk.img> info
Filesystem Information:
=======================
Image file: mydisk.img
Block size: 4096 bytes (log2: 12)
Total blocks: 32768
Bitmap start: block 1
Bitmap blocks: 1
Root directory: block 2 (2 blocks)
```

### Working with Files and Directories

```bash
mlfs:mydisk.img> ls
Contents of '/' (0 entries):
Name                 Type       Size Modified
----                 ----       ---- --------
(empty)

mlfs:mydisk.img> mkdir documents
Created directory 'documents'

mlfs:mydisk.img> touch readme.txt 2
Created file 'readme.txt' (2 blocks)

mlfs:mydisk.img> write readme.txt "Welcome to MLFS!"
Wrote 16 bytes to 'readme.txt'

mlfs:mydisk.img> ls
Contents of '/' (2 entries):
Name                 Type       Size Modified
----                 ----       ---- --------
documents            DIR            0 1699123456
readme.txt           FILE          16 1699123456

mlfs:mydisk.img> cat readme.txt
Contents of 'readme.txt' (16 bytes):
================================
Welcome to MLFS!
================================

mlfs:mydisk.img> rmdir documents
Removed directory 'documents'

mlfs:mydisk.img> quit
Unmounted 'mydisk.img'
Goodbye!
```

### Working with Existing Images

```bash
$ ./mlfs existing_disk.img
Attempting to mount 'existing_disk.img'...
Successfully mounted 'existing_disk.img'

mlfs:existing_disk.img> ls
Contents of '/' (3 entries):
Name                 Type       Size Modified  
----                 ----       ---- --------
config               DIR            0 1699120000
data.txt             FILE         256 1699120001
logs                 DIR            0 1699120002
```

## Features

### Command Line Editing

With readline support, the CLI provides:
- **Command history**: Use ↑/↓ arrows to navigate command history
- **Tab completion**: Basic command name completion
- **Line editing**: Standard emacs-style editing (Ctrl-A, Ctrl-E, etc.)
- **Interrupt handling**: Ctrl-C cleanly unmounts and exits

### File Operations

- **Create files**: `touch` creates empty files with specified block allocation
- **Write content**: `write` overwrites file content (limited to terminal-safe text)
- **Read content**: `cat` displays full file contents
- **File deletion**: `rm` removes files and frees their blocks

### Directory Operations

- **Create directories**: `mkdir` creates new directories
- **List contents**: `ls` shows directory entries with type and metadata
- **Remove directories**: `rmdir` removes empty directories only
- **Navigation**: Currently supports root-level operations only

### Disk Image Management

- **Create images**: `format` creates new disk images with customizable size and block size
- **Mount/unmount**: Safe mounting with error checking and validation
- **Multiple formats**: Supports block sizes from 512B to 64KB
- **Image validation**: Verifies filesystem integrity on mount

## Limitations

### Current Limitations

- **Root-level only**: No subdirectory navigation (paths with `/` not supported)
- **Single-extent files**: Files are limited to contiguous block allocation
- **Text content only**: Binary file support limited
- **No file copying**: Cannot copy files between locations
- **No permissions**: No file ownership or permission system

### Technical Constraints

- **Block sizes**: Must be power of 2, between 512 and 65536 bytes
- **Image size**: Limited by filesystem design and available disk space
- **Concurrent access**: Not designed for concurrent access to same image
- **Endianness**: Images created on different architectures may not be portable

## Error Codes

Common error codes returned by MLFS functions:

- `0`: Success
- `-1`: General error (I/O failure, invalid parameters)
- `-2`: Type mismatch (file vs directory)
- `-3`: Directory not empty (for rmdir)
- `-99`: Path contains unsupported subdirectories

## Troubleshooting

### Build Issues

**Readline not found:**
```bash
# Install readline development package
sudo apt-get install libreadline-dev
```

**Linking errors:**
```bash
# Ensure mlfs library is built first
make mlfs
make mlfs_cli
```

### Runtime Issues

**Cannot mount image:**
- Check file permissions and existence
- Verify image was created with `format` command
- Try creating new image: `format newdisk.img`

**Filesystem errors:**
- Check available disk space
- Verify image file integrity
- Unmount and remount if needed

**Command not found:**
- Type `help` to see all available commands
- Check command spelling and usage

### Performance

- **Large files**: Operations on large files may be slow due to single-extent limitation
- **Image size**: Very large images may have slower metadata operations
- **Block size**: Smaller block sizes increase overhead for large files
