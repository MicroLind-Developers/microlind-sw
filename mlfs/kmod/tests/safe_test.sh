#!/bin/bash
# Safe MLFS kernel module testing using loopback devices
# This avoids touching real hardware!

set -e  # Exit on error

TESTDIR="/tmp/mlfs_test"
IMGFILE="$TESTDIR/test.img"
MOUNTPOINT="$TESTDIR/mnt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== MLFS Safe Kernel Module Test ===${NC}"
echo "This test uses loopback devices, NOT real hardware"
echo ""

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    sudo umount "$MOUNTPOINT" 2>/dev/null || true
    sudo losetup -d /dev/loop20 2>/dev/null || true
    sudo rmmod mlfs 2>/dev/null || true
}

trap cleanup EXIT

# Step 1: Create test directory
echo -e "${GREEN}[1/8] Creating test directory...${NC}"
mkdir -p "$TESTDIR"
mkdir -p "$MOUNTPOINT"

# Step 2: Create a small test image (10MB)
echo -e "${GREEN}[2/8] Creating test image (10MB)...${NC}"
dd if=/dev/zero of="$IMGFILE" bs=1M count=10 status=none
echo "Created: $IMGFILE"

# Step 3: Format the image with MLFS using the CLI
echo -e "${GREEN}[3/8] Formatting image with MLFS...${NC}"
cd ../../  # Go to mlfs root (from kmod/tests)
if [ ! -f "build/tools/cli/mlfs" ]; then
    echo -e "${RED}ERROR: CLI tool not built. Run 'cmake --build build' first${NC}"
    exit 1
fi

# Create a partition and filesystem
./build/tools/cli/mlfs << 'EOF'
format /tmp/mlfs_test/test.img 10
mkpart 1 8 4096 testpart
mkfs 0
mount /tmp/mlfs_test/test.img 0
exit
EOF

echo "Image formatted successfully!"

# Step 4: Setup loopback device
echo -e "${GREEN}[4/8] Setting up loopback device...${NC}"
sudo losetup /dev/loop20 "$IMGFILE"
echo "Loopback device: /dev/loop20"

# Step 5: Load the kernel module
echo -e "${GREEN}[5/8] Loading MLFS kernel module...${NC}"
cd mlfs/kmod
sudo insmod mlfs.ko debug=1
lsmod | grep mlfs
echo "Module loaded successfully!"

# Step 6: Check kernel messages
echo -e "${GREEN}[6/8] Checking kernel messages...${NC}"
sudo dmesg | tail -3

# Step 7: Try to mount (THIS IS THE CRITICAL TEST)
echo -e "${GREEN}[7/8] Attempting to mount filesystem...${NC}"
echo -e "${YELLOW}If this crashes, the kernel will panic!${NC}"
sleep 1

if sudo mount -t mlfs -o partition=0 /dev/loop20 "$MOUNTPOINT"; then
    echo -e "${GREEN}SUCCESS: Filesystem mounted!${NC}"
    
    # Step 8: Test basic operations
    echo -e "${GREEN}[8/8] Testing filesystem operations...${NC}"
    
    echo "Listing root directory:"
    ls -la "$MOUNTPOINT" || true
    
    echo ""
    echo "Reading file (if any):"
    cat "$MOUNTPOINT"/* 2>/dev/null || echo "No files in root"
    
    echo ""
    echo "Filesystem stats:"
    df -h "$MOUNTPOINT"
    
    echo ""
    echo -e "${GREEN}=== Test completed successfully! ===${NC}"
else
    echo -e "${RED}FAILED: Could not mount filesystem${NC}"
    echo "Check dmesg for errors:"
    sudo dmesg | tail -20
    exit 1
fi

