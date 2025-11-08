#!/bin/bash
# Test script for MLFS proc filesystem statistics
# This script demonstrates the proc filesystem feature

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}MLFS Proc Filesystem Statistics Test${NC}"
echo -e "${BLUE}==================================================${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
   echo -e "${RED}Error: This script must be run as root${NC}"
   echo "Usage: sudo $0 [device]"
   exit 1
fi

# Device argument (optional)
DEVICE=${1:-/dev/loop0}
MOUNT_POINT="/mnt/mlfs_test"
TEST_IMG="/tmp/mlfs_test.img"

echo -e "${YELLOW}Step 1: Checking if MLFS module is loaded...${NC}"
if lsmod | grep -q mlfs; then
    echo -e "${GREEN}✓ MLFS module is already loaded${NC}"
else
    echo -e "${YELLOW}→ Loading MLFS module...${NC}"
    if [ -f ../mlfs.ko ]; then
        insmod ../mlfs.ko debug=1
        echo -e "${GREEN}✓ MLFS module loaded${NC}"
    else
        echo -e "${RED}Error: mlfs.ko not found. Run 'make' first from the kmod directory.${NC}"
        exit 1
    fi
fi
echo

echo -e "${YELLOW}Step 2: Creating test image...${NC}"
dd if=/dev/zero of=$TEST_IMG bs=1M count=64 2>/dev/null
echo -e "${GREEN}✓ Created 64MB test image${NC}"
echo

echo -e "${YELLOW}Step 3: Setting up loop device...${NC}"
if losetup -l | grep -q $TEST_IMG; then
    echo -e "${YELLOW}→ Loop device already exists, detaching...${NC}"
    losetup -d $DEVICE 2>/dev/null || true
fi
losetup $DEVICE $TEST_IMG
echo -e "${GREEN}✓ Loop device $DEVICE created${NC}"
echo

echo -e "${YELLOW}Step 4: Formatting with MLFS...${NC}"
# Find mlfs_blockdev tool
MLFS_BLOCKDEV=""

# Try different possible locations (now in tests/ subdirectory)
if command -v mlfs_blockdev &> /dev/null; then
    MLFS_BLOCKDEV=mlfs_blockdev
elif [ -f ../../build/tools/mlfs_blockdev/mlfs_blockdev ]; then
    MLFS_BLOCKDEV=../../build/tools/mlfs_blockdev/mlfs_blockdev
elif [ -f ../../../build/tools/mlfs_blockdev/mlfs_blockdev ]; then
    MLFS_BLOCKDEV=../../../build/tools/mlfs_blockdev/mlfs_blockdev
elif [ -f ../../tools/mlfs_blockdev/mlfs_blockdev ]; then
    MLFS_BLOCKDEV=../../tools/mlfs_blockdev/mlfs_blockdev
fi

if [ -z "$MLFS_BLOCKDEV" ]; then
    echo -e "${RED}Error: mlfs_blockdev not found${NC}"
    echo
    echo -e "${YELLOW}The MLFS tools need to be built first. To build them:${NC}"
    echo
    echo -e "  ${BLUE}# From the mlfs directory:${NC}"
    echo -e "  cd /home/eln/data/Repos/microlind/microlind-sw/mlfs"
    echo -e "  mkdir -p build && cd build"
    echo -e "  cmake .."
    echo -e "  make"
    echo
    echo -e "  ${BLUE}# Or from the root of the project:${NC}"
    echo -e "  cd /home/eln/data/Repos/microlind/microlind-sw"
    echo -e "  mkdir -p build && cd build"
    echo -e "  cmake .."
    echo -e "  make"
    echo
    losetup -d $DEVICE
    rm -f $TEST_IMG
    exit 1
fi

echo -e "${GREEN}→ Found mlfs_blockdev at: $MLFS_BLOCKDEV${NC}"

$MLFS_BLOCKDEV $DEVICE format
$MLFS_BLOCKDEV $DEVICE mkpart 1 32 4096 test
$MLFS_BLOCKDEV $DEVICE mkfs 0
echo -e "${GREEN}✓ MLFS filesystem created${NC}"
echo

echo -e "${YELLOW}Step 5: Mounting filesystem...${NC}"
mkdir -p $MOUNT_POINT
mount -t mlfs -o partition=0 $DEVICE $MOUNT_POINT
echo -e "${GREEN}✓ Mounted at $MOUNT_POINT${NC}"
echo

echo -e "${YELLOW}Step 6: Checking proc filesystem entry...${NC}"
# Extract device name from loop device
PROC_DEVICE=$(basename $DEVICE)
PROC_PATH="/proc/fs/mlfs/$PROC_DEVICE/stats"

if [ -f "$PROC_PATH" ]; then
    echo -e "${GREEN}✓ Proc entry exists at $PROC_PATH${NC}"
else
    echo -e "${RED}Error: Proc entry not found at $PROC_PATH${NC}"
    umount $MOUNT_POINT
    losetup -d $DEVICE
    rm -f $TEST_IMG
    exit 1
fi
echo

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Filesystem Statistics (Initial State)${NC}"
echo -e "${BLUE}==================================================${NC}"
cat $PROC_PATH
echo

echo -e "${YELLOW}Step 7: Creating test files...${NC}"
echo "Hello, MLFS!" > $MOUNT_POINT/test1.txt
echo "This is a test file" > $MOUNT_POINT/test2.txt
mkdir $MOUNT_POINT/testdir
echo "File in directory" > $MOUNT_POINT/testdir/test3.txt
echo -e "${GREEN}✓ Created test files${NC}"
echo

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Filesystem Statistics (After Creating Files)${NC}"
echo -e "${BLUE}==================================================${NC}"
cat $PROC_PATH
echo

echo -e "${YELLOW}Step 8: Testing statistics monitoring...${NC}"
echo -e "${GREEN}→ Creating more files (you can monitor in another terminal with:${NC}"
echo -e "${GREEN}  watch -n 1 'cat $PROC_PATH')${NC}"
for i in {1..5}; do
    echo "Test data $i" > $MOUNT_POINT/file_$i.txt
    sleep 0.5
done
echo -e "${GREEN}✓ Created additional files${NC}"
echo

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}Filesystem Statistics (Final State)${NC}"
echo -e "${BLUE}==================================================${NC}"
cat $PROC_PATH
echo

echo -e "${YELLOW}Step 9: Testing specific value extraction...${NC}"
echo -e "${GREEN}Free Blocks:${NC}"
grep "Free Blocks:" $PROC_PATH
echo
echo -e "${GREEN}Usage:${NC}"
grep "Usage:" $PROC_PATH
echo

echo -e "${YELLOW}Step 10: Listing mounted files...${NC}"
ls -la $MOUNT_POINT
echo

echo -e "${YELLOW}Step 11: Cleanup...${NC}"
umount $MOUNT_POINT
echo -e "${GREEN}✓ Unmounted filesystem${NC}"

# Check if proc entry was removed
if [ -f "$PROC_PATH" ]; then
    echo -e "${RED}Warning: Proc entry still exists after unmount${NC}"
else
    echo -e "${GREEN}✓ Proc entry removed after unmount${NC}"
fi

losetup -d $DEVICE
echo -e "${GREEN}✓ Loop device detached${NC}"

rm -f $TEST_IMG
echo -e "${GREEN}✓ Test image removed${NC}"
echo

echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}✓ All tests passed!${NC}"
echo -e "${BLUE}==================================================${NC}"
echo
echo -e "${YELLOW}Note: The MLFS module is still loaded. To unload:${NC}"
echo -e "${YELLOW}  sudo rmmod mlfs${NC}"

