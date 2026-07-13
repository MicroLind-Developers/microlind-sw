# mlfs_info - MLFS Filesystem Analysis Tool

A command-line utility for analyzing MLFS (MicroLind File System) disk images and displaying detailed filesystem information.

## Overview

The `mlfs_info` tool provides comprehensive analysis of MLFS image files, including:
- Image file information and partition table details
- Filesystem superblock analysis
- Block allocation statistics  
- Directory structure visualization (when partition specified)

## Usage

```bash
mlfs_info <mlfs_image_file> [partition_number]
```

**Arguments:**
- `image_file`: Path to the MLFS image file to analyze
- `partition_number`: Optional partition number to analyze in detail

**Behavior:**
- **Without partition number**: Shows general image information and partition table overview
- **With partition number**: Additionally shows filesystem details and complete directory tree structure

## Example Output

**Overview Mode** (`mlfs_info test.img`):
```
Analyzing MLFS image: test.img (partition table overview)

MLFS Filesystem Information
===========================

General Information:
  Image File Size: 67108864 bytes (64.0 MB)
  Total Sectors:   131072 (512 bytes each)

Partition Table:
  Magic:           0x4D4C5054
  Version:         1.1.0
  Partitions:      2
  Partition 0:
    Type:          1 (MLFS)
    Start LBA:     1
    Block Count:   8192 blocks (32.0 MB)
    Block Size:    4096 bytes (log2: 12)
    Name:          main
    End LBA:       65536
    Sectors Used:  65536

  Partition 1:
    Type:          1 (MLFS)
    Start LBA:     65537
    Block Count:   8191 blocks (32.0 MB)
    Name:          backup
    End LBA:       131071
    Sectors Used:  65528

Use 'mlfs_info test.img <partition_number>' to analyze a specific partition's filesystem and directory structure.
```

**Detailed Mode** (`mlfs_info test.img 0`):
```
Analyzing MLFS image: test.img (partition 0)

[... same General Information and Partition Table as above ...]

Partition 0 Filesystem Details:
================================

Superblock:
  Magic:           0x4D4C4653
  Version:         1.1.0
  Block Size:      4096 bytes (log2: 12)
  Total Blocks:    8192 (32.0 MB)
  Bitmap Start:    block 1
  Bitmap Blocks:   1 (4.0 KB)
  Root Directory:  block 2, 1 blocks (4.0 KB)
  UUID:            a1b2c3d4-e5f6-7890-1234-567890abcdef

Block Allocation:
  Used Blocks:     3 (12.0 KB)
  Free Blocks:     8189 (32.0 MB)
  Total Capacity:  8192 blocks (32.0 MB)

Directory Structure:
===================
├── 📁 documents/ (0 B, 2024-11-05 12:30:15)
│   ├── 📁 reports/ (0 B, 2024-11-05 12:30:20)
│   │   ├── 📁 2024/ (0 B, 2024-11-05 12:30:25)
│   │   │   └── 📄 quarterly_report.txt (1.2 KB, 2024-11-05 12:30:30)
│   │   └── 📄 summary.txt (856 B, 2024-11-05 12:30:35)
│   └── 📁 presentations/ (0 B, 2024-11-05 12:30:40)
├── 📁 photos/ (0 B, 2024-11-05 12:30:45)
│   ├── 📁 vacation/ (0 B, 2024-11-05 12:30:50)
│   │   └── 📄 beach.jpg (2.1 MB, 2024-11-05 12:30:55)
│   └── 📁 work/ (0 B, 2024-11-05 12:31:00)
└── 📄 readme.txt (512 B, 2024-11-05 12:31:05)

Analysis complete.
```

## Building

The tool is automatically built when you build the MLFS project:

```bash
mkdir build && cd build
cmake ..
make mlfs_info
```

The `mlfs_info` executable will be created in `build/tools/mlfs_info/mlfs_info`.

## Use Cases

- **Quick Overview**: Get partition layout and general information (`mlfs_info image.img`)
- **Partition Inspection**: Browse files and directories in specific partitions (`mlfs_info image.img 0`)
- **Filesystem Debugging**: Analyze corrupted or problematic MLFS images
- **Capacity Planning**: Check disk usage and free space per partition
- **File Recovery**: Locate files and directories in damaged filesystems
- **Development**: Verify filesystem structure during MLFS development
- **Documentation**: Generate filesystem inventories and reports
- **Multi-Partition Analysis**: Compare contents across different partitions

## Technical Details

The tool uses the MLFS library in read-only mode to:
- Parse partition tables (MLPT format)
- Read superblock information
- Analyze block allocation bitmaps
- Traverse directory structures recursively
- Display file and directory metadata

The analysis is completely safe and read-only - it never modifies the source image file.

If an image contains an MLPT header with an unsupported version, `mlfs_info`
still displays the decoded partition table and prints the version expected by
the current build. Detailed filesystem analysis is disabled in that case because
`mlfs/lib` will not mount incompatible MLPT versions.

## Multi-Partition Support

The tool supports MLFS images with multiple partitions:

1. **Show All Partitions**: When run without a partition number, displays information about all partitions in the image
2. **Analyze Specific Partition**: When given a partition number, shows detailed filesystem information for that partition only
3. **Partition Table Details**: Always shows complete partition table with all partitions, their sizes, types, and layout

**Examples:**
```bash
# Quick overview - show partition table only
mlfs_info multi_part_image.img

# Detailed analysis - inspect files in partition 0
mlfs_info multi_part_image.img 0

# Detailed analysis - inspect files in partition 1
mlfs_info multi_part_image.img 1

# Compare directory structures between partitions
mlfs_info multi_part_image.img 0 > partition0_contents.txt
mlfs_info multi_part_image.img 1 > partition1_contents.txt
diff partition0_contents.txt partition1_contents.txt

# Quick partition layout check
mlfs_info disk.img | grep "Partition"
```

## Installation

After building, you can install the tool system-wide:

```bash
make install
# mlfs_info will be installed to /usr/local/bin/ (or your configured prefix)
```

## Dependencies

- MLFS library (built automatically as part of the project)
- C99-compatible compiler
- CMake 3.16+

## See Also

- [MLFS CLI Tool](../cli/README.md) - Interactive filesystem management
- [MLFS Library Documentation](../lib/README.md) - Core library API
- [Project README](../README.md) - Overall project information
