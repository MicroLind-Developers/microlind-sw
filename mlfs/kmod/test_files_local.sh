#!/bin/bash
# Test MLFS with files locally (no hardware) using loopback device

set -e

TESTDIR="/tmp/mlfs_test"
IMGFILE="$TESTDIR/mlfs_with_files.img"
MOUNTPOINT="$TESTDIR/mnt"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== MLFS Local Test with Files ===${NC}"
echo ""

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    sudo umount "$MOUNTPOINT" 2>/dev/null || true
    sudo losetup -d /dev/loop20 2>/dev/null || true
    sudo rmmod mlfs 2>/dev/null || true
    sudo rm -rf "$TESTDIR"
}

trap cleanup EXIT

# Create test environment
echo -e "${GREEN}[1/5] Creating test environment...${NC}"
sudo mkdir -p "$TESTDIR"
sudo mkdir -p "$MOUNTPOINT"
sudo chmod 777 "$TESTDIR"
cd ../  # Go to mlfs root

# Create image with files
echo -e "${GREEN}[2/5] Creating MLFS image with test files...${NC}"

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
write root_info.txt "MLFS Root Directory\nCreated for testing\n"
info
exit
MLFS_EOF

./build/cli/mlfs < /tmp/test_setup.mlfs

echo ""
echo -e "${BLUE}Image created: $IMGFILE${NC}"
ls -lh "$IMGFILE"

# Setup loopback
echo ""
echo -e "${GREEN}[3/5] Setting up loopback device...${NC}"
sudo losetup /dev/loop20 "$IMGFILE"
cd kmod
sudo insmod mlfs.ko debug=1
echo "Module loaded"

# Mount
echo ""
echo -e "${GREEN}[4/5] Mounting filesystem...${NC}"
sudo mount -t mlfs -o partition=0 /dev/loop20 "$MOUNTPOINT"
echo -e "${GREEN}Mounted successfully!${NC}"

# Test reading
echo ""
echo -e "${GREEN}[5/5] Testing file operations...${NC}"
echo ""

echo -e "${BLUE}Root directory:${NC}"
ls -la "$MOUNTPOINT"

echo ""
echo -e "${BLUE}All directories:${NC}"
find "$MOUNTPOINT" -type d

echo ""
echo -e "${BLUE}All files:${NC}"
find "$MOUNTPOINT" -type f

echo ""
echo -e "${BLUE}File: root_info.txt${NC}"
cat "$MOUNTPOINT/root_info.txt"

echo ""
echo -e "${BLUE}File: documents/readme.txt${NC}"
cat "$MOUNTPOINT/documents/readme.txt"

echo ""
echo -e "${BLUE}File: documents/hello.txt${NC}"
cat "$MOUNTPOINT/documents/hello.txt"

echo ""
echo -e "${BLUE}File: programs/test.asm${NC}"
cat "$MOUNTPOINT/programs/test.asm"

echo ""
echo -e "${BLUE}File: data/config.cfg${NC}"
cat "$MOUNTPOINT/data/config.cfg"

echo ""
echo -e "${GREEN}✓ All files read successfully!${NC}"
echo ""
echo "Image ready for CompactFlash: $IMGFILE"
echo ""
read -p "Press ENTER to cleanup..."

