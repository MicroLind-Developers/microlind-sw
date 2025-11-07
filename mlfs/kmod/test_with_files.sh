#!/bin/bash
# Create MLFS image with test files, write to CompactFlash, and test reading

set -e

TESTDIR="/tmp/mlfs_test"
IMGFILE="$TESTDIR/mlfs_with_files.img"
MOUNTPOINT="$TESTDIR/mnt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== MLFS CompactFlash Test with Files ===${NC}"
echo ""

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    sudo umount "$MOUNTPOINT" 2>/dev/null || true
    sudo rmmod mlfs 2>/dev/null || true
    sudo rm -rf "$TESTDIR"
}

trap cleanup EXIT

# Step 1: Create test directory
echo -e "${GREEN}[1/7] Creating test environment...${NC}"
sudo mkdir -p "$TESTDIR"
sudo mkdir -p "$MOUNTPOINT"
sudo chmod 777 "$TESTDIR"

# Step 2: Create image with files
echo -e "${GREEN}[2/7] Creating MLFS image with test files...${NC}"
cd ../  # Go to mlfs root

cat > /tmp/test_setup.mlfs << 'MLFS_EOF'
format /tmp/mlfs_test/mlfs_with_files.img 32
mkpart 1 30 4096 data
mkfs 0
mount /tmp/mlfs_test/mlfs_with_files.img 0
mkdir documents
mkdir programs
mkdir data
touch documents/readme.txt 1
write documents/readme.txt "Welcome to MLFS!\nThis is the MicroLind File System.\nRunning on a 6809 CPU!\n\nFeatures:\n- Subdirectories\n- Extent-based storage\n- Multiple partitions\n- Linux kernel module support\n"
touch documents/hello.txt 1
write documents/hello.txt "Hello from MLFS!"
touch programs/test.asm 1
write programs/test.asm "; 6809 Assembly Test Program\n        ORG     $E000\nSTART   LDA     #$FF\n        STA     $8000\n        RTS\n        END     START\n"
touch data/config.cfg 1
write data/config.cfg "[system]\nname=microlind\narch=6809\nram=512KB\n\n[display]\nwidth=80\nheight=25\n"
touch root_info.txt 1
write root_info.txt "MLFS Root Directory\nCreated for CompactFlash test\n"
ls
ls documents
ls programs  
ls data
info
exit
MLFS_EOF

echo "Running CLI to create filesystem with test files..."
./build/cli/mlfs < /tmp/test_setup.mlfs

echo ""
echo -e "${BLUE}Image created successfully!${NC}"
echo "Location: $IMGFILE"
ls -lh "$IMGFILE"

# Step 3: Show what we created
echo ""
echo -e "${GREEN}[3/7] Image contents summary:${NC}"
../../build/tools/mlfs_info/mlfs_info "$IMGFILE" 0 | head -40

# Step 4: Identify CompactFlash device
echo ""
echo -e "${GREEN}[4/7] Identifying CompactFlash device...${NC}"
echo -e "${YELLOW}IMPORTANT: Please verify the device carefully!${NC}"
echo ""
echo "Looking for removable storage devices..."
echo ""

# List all block devices
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL | grep -E "(NAME|disk|part)" || true

echo ""
echo -e "${RED}⚠️  WARNING: Writing to the wrong device will destroy data!${NC}"
echo ""
read -p "Enter the CompactFlash device path (e.g., /dev/sdb): " CF_DEVICE

# Validate device exists
if [ ! -b "$CF_DEVICE" ]; then
    echo -e "${RED}ERROR: $CF_DEVICE is not a block device!${NC}"
    exit 1
fi

# Show device info
echo ""
echo "Device information for $CF_DEVICE:"
sudo fdisk -l "$CF_DEVICE" 2>/dev/null || true
echo ""

# Final confirmation
echo -e "${RED}⚠️  FINAL WARNING ⚠️${NC}"
echo "About to write to: $CF_DEVICE"
echo "This will DESTROY ALL DATA on this device!"
echo ""
read -p "Type 'YES' in capital letters to continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

# Step 5: Write image to CompactFlash
echo ""
echo -e "${GREEN}[5/7] Writing image to CompactFlash...${NC}"
echo "This may take a minute..."
sudo dd if="$IMGFILE" of="$CF_DEVICE" bs=1M status=progress
sudo sync
echo "Write completed!"

# Wait for device to settle
sleep 2

# Step 6: Load kernel module and mount
echo ""
echo -e "${GREEN}[6/7] Loading kernel module and mounting CompactFlash...${NC}"
cd kmod
sudo insmod mlfs.ko debug=1

echo "Mounting $CF_DEVICE..."
if sudo mount -t mlfs -o partition=0 "$CF_DEVICE" "$MOUNTPOINT"; then
    echo -e "${GREEN}SUCCESS: CompactFlash mounted!${NC}"
else
    echo -e "${RED}FAILED: Could not mount${NC}"
    sudo dmesg | tail -20
    exit 1
fi

# Step 7: Test reading files
echo ""
echo -e "${GREEN}[7/7] Testing file operations on CompactFlash...${NC}"
echo ""

echo -e "${BLUE}=== Root Directory ===${NC}"
ls -la "$MOUNTPOINT"

echo ""
echo -e "${BLUE}=== Reading root_info.txt ===${NC}"
cat "$MOUNTPOINT/root_info.txt"

echo ""
echo -e "${BLUE}=== Documents Directory ===${NC}"
ls -l "$MOUNTPOINT/documents/"

echo ""
echo -e "${BLUE}=== Reading documents/readme.txt ===${NC}"
cat "$MOUNTPOINT/documents/readme.txt"

echo ""
echo -e "${BLUE}=== Reading documents/hello.txt ===${NC}"
cat "$MOUNTPOINT/documents/hello.txt"

echo ""
echo -e "${BLUE}=== Programs Directory ===${NC}"
ls -l "$MOUNTPOINT/programs/"

echo ""
echo -e "${BLUE}=== Reading programs/test.asm ===${NC}"
cat "$MOUNTPOINT/programs/test.asm"

echo ""
echo -e "${BLUE}=== Data Directory ===${NC}"
ls -l "$MOUNTPOINT/data/"

echo ""
echo -e "${BLUE}=== Reading data/config.cfg ===${NC}"
cat "$MOUNTPOINT/data/config.cfg"

echo ""
echo -e "${BLUE}=== Filesystem Statistics ===${NC}"
df -h "$MOUNTPOINT"

echo ""
echo -e "${BLUE}=== Kernel Messages ===${NC}"
sudo dmesg | grep mlfs | tail -15

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}║   🎉  MLFS COMPACTFLASH TEST SUCCESSFUL! 🎉          ║${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}║   ✓ Created filesystem with files and directories    ║${NC}"
echo -e "${GREEN}║   ✓ Wrote to CompactFlash successfully               ║${NC}"
echo -e "${GREEN}║   ✓ Loaded kernel module without crashes             ║${NC}"
echo -e "${GREEN}║   ✓ Mounted CompactFlash device                      ║${NC}"
echo -e "${GREEN}║   ✓ Read all files successfully                      ║${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}║   Your MicroLind filesystem is working on real       ║${NC}"
echo -e "${GREEN}║   hardware with Linux kernel integration!            ║${NC}"
echo -e "${GREEN}║                                                       ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# Keep mounted for inspection
echo -e "${YELLOW}Filesystem is still mounted at: $MOUNTPOINT${NC}"
echo -e "${YELLOW}CompactFlash device: $CF_DEVICE${NC}"
echo ""
read -p "Press ENTER to unmount and cleanup..."

