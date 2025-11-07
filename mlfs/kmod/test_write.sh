#!/bin/bash

# Test MLFS write support
# Tests basic file writing and modification

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../build"
CLI="${BUILD_DIR}/cli/mlfs"
TEST_DIR="/tmp/mlfs_test"
IMAGE="${TEST_DIR}/test_write.img"
MOUNT_POINT="${TEST_DIR}/mnt"

echo "======================================"
echo "MLFS Write Support Test"
echo "======================================"
echo

# Check if CLI exists
if [ ! -f "$CLI" ]; then
    echo "Error: mlfs_cli not found at $CLI"
    echo "Please build it first: cd $CLI_DIR && mkdir -p build && cd build && cmake .. && make"
    exit 1
fi

# Create test directory
mkdir -p "$TEST_DIR"
mkdir -p "$MOUNT_POINT"

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
    sudo losetup -d /dev/loop21 2>/dev/null || true
    sudo rmmod mlfs 2>/dev/null || true
}

trap cleanup EXIT

# Create a test image with some files
echo "Step 1: Creating test image with CLI..."
rm -f "$IMAGE"

cat << EOF | "$CLI"
format $IMAGE 32
mkpart 1 30 4096 testpart
mkfs 0
mount $IMAGE 0
touch root_test.txt
write root_test.txt "This is the original content of the file."
mkdir data
touch data/config.txt
write data/config.txt "Initial config: debug=false"
ls /
cat root_test.txt
cat data/config.txt
unmount
close
quit
EOF

echo
echo "Step 2: Setting up loopback device..."
sudo losetup /dev/loop21 "$IMAGE" 2>/dev/null || true
sleep 1

echo
echo "Step 3: Loading kernel module..."
sudo rmmod mlfs 2>/dev/null || true
sudo insmod mlfs.ko || { echo "Failed to load module!"; exit 1; }

echo
echo "Step 4: Mounting filesystem..."
sudo mount -t mlfs -o partition=0 /dev/loop21 "$MOUNT_POINT" || {
    echo "Mount failed!"
    dmesg | tail -20
    exit 1
}

echo
echo "Step 5: Testing file writes..."
echo

# Test 1: Read original content
echo "Test 1: Reading original file content..."
cat "$MOUNT_POINT/root_test.txt"
echo

# Test 2: Modify existing file
echo "Test 2: Modifying file content..."
echo "MODIFIED: This text was written by the kernel module!" | sudo tee "$MOUNT_POINT/root_test.txt"
echo "New content:"
cat "$MOUNT_POINT/root_test.txt"
echo

# Test 3: Modify config file
echo "Test 3: Modifying config file..."
echo "Modified config: debug=true" | sudo tee "$MOUNT_POINT/data/config.txt"
echo "New config:"
cat "$MOUNT_POINT/data/config.txt"
echo

# Test 4: Append to file (if file is large enough)
echo "Test 4: Overwriting part of file..."
echo -n "PARTIAL" | sudo dd of="$MOUNT_POINT/root_test.txt" bs=1 seek=0 conv=notrunc 2>/dev/null
echo "After partial overwrite:"
cat "$MOUNT_POINT/root_test.txt"
echo

echo "Step 6: Unmounting and verifying with CLI..."
sudo umount "$MOUNT_POINT"
sudo losetup -d /dev/loop21

# Verify with CLI
cat << EOF | "$CLI"
open $IMAGE
mount $IMAGE 0
ls /
cat root_test.txt
cat data/config.txt
unmount
close
quit
EOF

echo
echo "======================================"
echo "Write test completed successfully!"
echo "======================================"
echo
echo "Check dmesg for kernel module debug output:"
echo "  sudo dmesg | tail -50"

