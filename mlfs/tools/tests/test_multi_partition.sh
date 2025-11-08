#!/bin/bash

# Test script for multiple partition support in MLFS
# Demonstrates creating multi-partition images and using both CLI and mlfs_info tools

echo "MLFS Multiple Partition Support Test"
echo "==================================="
echo ""

# Build the project if needed
if [ ! -f "../../build/tools/cli/mlfs" ] || [ ! -f "../../build/tools/mlfs_info/mlfs_info" ]; then
    echo "Building MLFS project..."
    cd ../..
    mkdir -p build
    cd build
    cmake ..
    make
    cd tools/tests
    echo ""
fi

# Create a test script for the CLI to create a multi-partition image
echo "Creating multi-partition test image..."
cat > test_multi_commands.txt << 'EOF'
format test_multi.img 64
info
mkpart 1 24 4096 main
info
mkpart 49153 16 2048 backup
info
mkpart 81921 8 1024 logs
info
mkfs 0
mkfs 1
mkfs 2
info
mount test_multi.img 0
info
mkdir partition0_data
write partition0_data/info.txt "This is partition 0 - the main partition"
write readme.txt "Main partition README"
ls
cat readme.txt
unmount
mount test_multi.img 1
write backup_info.txt "This is the backup partition"
ls
unmount
info
close
quit
EOF

# Run the CLI commands
if [ -f "../../build/tools/cli/mlfs" ]; then
    echo "Running CLI to create test filesystem..."
    echo "----------------------------------------"
    ../../build/tools/cli/mlfs < test_multi_commands.txt
    echo ""
    echo "Filesystem creation completed."
    echo ""
else
    echo "Error: CLI not found. Please build the project first."
    exit 1
fi

# Test mlfs_info tool with different partition numbers
if [ -f "../../build/tools/mlfs_info/mlfs_info" ] && [ -f "test_multi.img" ]; then
    echo "Testing mlfs_info tool..."
    echo "========================="
    echo ""
    
    echo "1. Overview mode (no partition specified - shows partition table only):"
    echo "-----------------------------------------------------------------------"
    ../../build/tools/mlfs_info/mlfs_info test_multi.img
    echo ""
    
    echo "2. Detailed analysis of partition 0 (shows filesystem + directory tree):"
    echo "------------------------------------------------------------------------"
    ../../build/tools/mlfs_info/mlfs_info test_multi.img 0
    echo ""
    
    echo "3. Detailed analysis of partition 1 (shows filesystem + directory tree):"
    echo "------------------------------------------------------------------------"
    ../../build/tools/mlfs_info/mlfs_info test_multi.img 1
    echo ""
    
    echo "4. Detailed analysis of partition 2 (shows filesystem + directory tree):"
    echo "------------------------------------------------------------------------"
    ../../build/tools/mlfs_info/mlfs_info test_multi.img 2
    echo ""
    
    # Test with invalid partition
    echo "5. Testing with invalid partition 99 (should fail gracefully):"
    echo "--------------------------------------------------------------"
    ../../build/tools/mlfs_info/mlfs_info test_multi.img 99 2>/dev/null || echo "Failed as expected - partition 99 does not exist"
    echo ""
else
    echo "Error: mlfs_info tool or test image not found."
fi

# Test CLI partition commands
echo "Testing CLI partition commands..."
echo "================================"
cat > test_partition_commands.txt << 'EOF'
open test_multi.img
partitions
mkpart 131073 8 1024 extra
partitions
mkfs 3
partitions
mount test_multi.img 0
pwd
ls
cat readme.txt
unmount
mount test_multi.img 1
ls
unmount
close
quit
EOF

echo ""
echo "CLI session demonstrating partition commands:"
echo "--------------------------------------------"
../../build/tools/cli/mlfs < test_partition_commands.txt
echo ""

# Show CLI usage examples
echo "CLI Usage Examples:"
echo "=================="
echo ""
echo "NEW WORKFLOW (with multiple partitions):"
echo ""
echo "1. Create empty image (keeps file open):"
echo "   format <image_file> [size_mb]"
echo "   Example: format disk.img 64"
echo "   → Prompt becomes: mlfs:disk.img>"
echo ""
echo "2. Create partitions (works on open file):"
echo "   mkpart <start_lba> <size_mb> <block_size> <name>"
echo "   Example: mkpart 1 32 4096 main"
echo "   Example: mkpart 65537 16 2048 backup"
echo ""
echo "3. Format partitions with filesystem:"
echo "   mkfs <partition_number>"
echo "   Example: mkfs 0"
echo "   Example: mkfs 1"
echo ""
echo "4. Mount and use partitions:"
echo "   mount <image_file> <partition_number>"
echo "   Example: mount disk.img 0"
echo "   → Prompt becomes: mlfs:disk.img[0]:/>>"
echo ""
echo "5. Check partition layout and free space:"
echo "   info"
echo "   Example output shows start/end LBAs and suggests next available LBA"
echo ""
echo "6. List all partitions:"
echo "   partitions"
echo ""
echo "7. Switch between mounted partitions:"
echo "   partition <number>"
echo "   Example: partition 1"
echo ""
echo "8. Unmount (keeps file open):"
echo "   unmount"
echo "   → Prompt becomes: mlfs:disk.img>"
echo ""
echo "9. Close image file completely:"
echo "   close"
echo "   → Prompt becomes: mlfs>"
echo ""
echo "10. Reopen existing image for more partition work:"
echo "    open <image_file>"
echo "    Example: open disk.img"
echo "    → Prompt becomes: mlfs:disk.img>"
echo ""

# Show mlfs_info usage examples
echo "mlfs_info Usage Examples:"
echo "========================"
echo ""
echo "1. Overview mode (partition table and general info only):"
echo "   mlfs_info <image_file>"
echo "   Example: mlfs_info test_multi.img"
echo "   → Shows image info, partition table, usage suggestions"
echo ""
echo "2. Detailed partition analysis (includes directory tree):"
echo "   mlfs_info <image_file> <partition_number>"
echo "   Example: mlfs_info test_multi.img 0"
echo "   → Shows everything from overview + filesystem details + directory tree"
echo ""
echo "Use case examples:"
echo "• mlfs_info disk.img        → Quick partition layout overview"
echo "• mlfs_info disk.img 0      → Inspect files/directories in partition 0"
echo "• mlfs_info disk.img 1      → Browse contents of partition 1"
echo ""

# Cleanup
rm -f test_multi_commands.txt test_partition_commands.txt # test_multi.img

echo "Test completed!"
echo ""
echo "NEW MULTI-PARTITION WORKFLOW:"
echo "============================="
echo ""
echo "The MLFS system now supports true multi-partition images:"
echo ""
echo "WORKFLOW COMMANDS:"
echo "• format: Creates empty images with no default partitions (keeps file open)"
echo "• open:   Reopens existing images for partition operations"
echo "• info:   Shows comprehensive partition layout, free space, and next available LBA"
echo "• mkpart: Adds individual partitions with custom sizes and block sizes"
echo "• mkfs:   Formats specific partitions with MLFS filesystem"
echo "• mount:  Mounts specific partitions for use (keeps file open on failure)"
echo "• partitions: Lists all partitions and their status"
echo "• partition: Switches between mounted partitions"
echo "• unmount: Unmounts filesystem but keeps image file open"
echo "• close:  Closes image file completely"
echo ""
echo "COMPLETE WORKFLOW:"
echo "1. format disk.img → creates image, keeps open"
echo "2. info → check available space and suggested start LBA"
echo "3. mkpart <start_lba> ... → add first partition"
echo "4. info → see updated layout and next available LBA"
echo "5. mkpart <next_lba> ... → add more partitions as needed"
echo "6. mkfs N → format partition N"
echo "7. mount disk.img N → mount partition N"
echo "8. work with files..."
echo "9. unmount → unmount but keep image open"
echo "10. mount disk.img M → switch to partition M"
echo "11. close → close image completely"
echo "12. Later: open disk.img → reopen for more partition work"
echo ""
echo "This allows for flexible partition layouts with different:"
echo "• Sizes (each partition can be a different size)"
echo "• Block sizes (optimized for different use cases)"
echo "• Names (for easy identification)"
echo "• Purposes (main data, backup, logs, etc.)"
echo "• Persistent workflow (can resume partition work after exit)"
