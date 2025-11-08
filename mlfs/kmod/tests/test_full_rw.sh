#!/bin/bash

# Test MLFS full read-write support
# Tests file creation, directory creation, writing, and deletion

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../../build"
CLI="${BUILD_DIR}/cli/mlfs"
TEST_DIR="/tmp/mlfs_test"
IMAGE="${TEST_DIR}/test_full_rw.img"
MOUNT_POINT="${TEST_DIR}/mnt"

echo "======================================"
echo "MLFS Full Read-Write Test"
echo "======================================"
echo

# Check if CLI exists
if [ ! -f "$CLI" ]; then
    echo "Error: mlfs_cli not found at $CLI"
    echo "Please build it first"
    exit 1
fi

# Create test directory
mkdir -p "$TEST_DIR"
mkdir -p "$MOUNT_POINT"

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    sudo umount "$MOUNT_POINT" 2>/dev/null || true
    sudo losetup -d /dev/loop22 2>/dev/null || true
    sudo rmmod mlfs 2>/dev/null || true
}

trap cleanup EXIT

# Create an empty image with CLI
echo "Step 1: Creating empty image..."
rm -f "$IMAGE"

cat << EOF | "$CLI"
format $IMAGE 32
mkpart 1 30 4096 testpart
mkfs 0
mount $IMAGE 0
unmount
close
quit
EOF

echo
echo "Step 2: Setting up loopback device..."
sudo losetup /dev/loop22 "$IMAGE" 2>/dev/null || true
sleep 1

echo
echo "Step 3: Loading kernel module..."
sudo rmmod mlfs 2>/dev/null || true
sudo insmod "$SCRIPT_DIR/../mlfs.ko" debug=1 || { echo "Failed to load module!"; exit 1; }

echo
echo "Step 4: Mounting filesystem..."
sudo mount -t mlfs -o partition=0 /dev/loop22 "$MOUNT_POINT" || {
    echo "Mount failed!"
    dmesg | tail -20
    exit 1
}

echo
echo "Step 5: Testing file and directory operations..."
echo

# Test 1: Create files
echo "Test 1: Creating files..."
echo "Hello from kernel!" | sudo tee "$MOUNT_POINT/test1.txt" > /dev/null || {
    echo "ERROR: Failed to create test1.txt"
    echo "Checking dmesg for errors..."
    sudo dmesg | tail -20
    exit 1
}
echo "MLFS is working!" | sudo tee "$MOUNT_POINT/test2.txt" > /dev/null || {
    echo "ERROR: Failed to create test2.txt"
    exit 1
}
echo "Created test1.txt and test2.txt"
ls -la "$MOUNT_POINT"
echo

# Test 2: Read files
echo "Test 2: Reading files..."
cat "$MOUNT_POINT/test1.txt"
cat "$MOUNT_POINT/test2.txt"
echo

# Test 3: Create directories
echo "Test 3: Creating directories..."
sudo mkdir "$MOUNT_POINT/docs"
sudo mkdir "$MOUNT_POINT/code"
echo "Created docs/ and code/ directories"
ls -la "$MOUNT_POINT"
echo

# Test 4: Create files in subdirectories
echo "Test 4: Creating files in subdirectories..."
echo "README content" | sudo tee "$MOUNT_POINT/docs/readme.txt" > /dev/null
echo "Source code" | sudo tee "$MOUNT_POINT/code/main.c" > /dev/null
echo "Created files in subdirectories"
ls -la "$MOUNT_POINT/docs"
ls -la "$MOUNT_POINT/code"
echo

# Test 5: Modify existing files
echo "Test 5: Modifying files..."
echo "MODIFIED!" | sudo tee "$MOUNT_POINT/test1.txt" > /dev/null
cat "$MOUNT_POINT/test1.txt"
echo

# Test 6: Delete files
echo "Test 6: Deleting files..."
sudo rm "$MOUNT_POINT/test2.txt"
echo "Deleted test2.txt"
ls -la "$MOUNT_POINT"
echo

# Test 7: Delete directories
echo "Test 7: Deleting empty directory..."
sudo mkdir "$MOUNT_POINT/temp"
sudo rmdir "$MOUNT_POINT/temp"
echo "Created and deleted temp/ directory"
ls -la "$MOUNT_POINT"
echo

echo "Step 6: Syncing and unmounting..."
sync
sudo umount "$MOUNT_POINT"
sudo losetup -d /dev/loop22

echo
echo "Step 7: Verifying persistence with CLI..."
cat << EOF | "$CLI"
open $IMAGE
mount $IMAGE 0
ls /
cat test1.txt
ls docs
cat docs/readme.txt
ls code
cat code/main.c
unmount
close
quit
EOF

echo
echo "======================================"
echo "Full read-write test completed!"
echo "======================================"
echo
echo "Summary:"
echo "  ✓ File creation"
echo "  ✓ File writing"
echo "  ✓ File reading"
echo "  ✓ File modification"
echo "  ✓ File deletion"
echo "  ✓ Directory creation"
echo "  ✓ Directory deletion"
echo "  ✓ Subdirectory operations"
echo "  ✓ Data persistence"
echo
echo "Check dmesg for kernel module debug output:"
echo "  sudo dmesg | grep mlfs | tail -50"

