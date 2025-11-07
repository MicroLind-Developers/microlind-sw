#!/bin/bash
# Test script for MLFS kernel module

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_IMG="/tmp/mlfs_kmod_test.img"
LOOP_DEV="/dev/loop10"
MOUNT_POINT="/tmp/mlfs_test_mount"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    log_info "Cleaning up..."
    
    # Unmount if mounted
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        sudo umount "$MOUNT_POINT"
    fi
    
    # Detach loop device
    if [ -e "$LOOP_DEV" ]; then
        sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
    
    # Remove mount point
    [ -d "$MOUNT_POINT" ] && rmdir "$MOUNT_POINT" || true
    
    # Unload module
    if lsmod | grep -q "^mlfs "; then
        sudo rmmod mlfs
    fi
    
    # Remove test image
    [ -f "$TEST_IMG" ] && rm "$TEST_IMG"
}

# Trap cleanup on exit
trap cleanup EXIT

# Check if running as root for some operations
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run with sudo"
        exit 1
    fi
}

main() {
    log_info "MLFS Kernel Module Test Script"
    log_info "================================"
    echo ""
    
    # Step 1: Build module
    log_info "Step 1: Building kernel module..."
    cd "$SCRIPT_DIR"
    make clean
    make
    
    if [ ! -f "mlfs.ko" ]; then
        log_error "Failed to build mlfs.ko"
        exit 1
    fi
    log_info "✓ Module built successfully"
    echo ""
    
    # Step 2: Create test image
    log_info "Step 2: Creating test image..."
    dd if=/dev/zero of="$TEST_IMG" bs=1M count=64 2>/dev/null
    log_info "✓ Created 64MB test image"
    echo ""
    
    # Step 3: Format with MLFS
    log_info "Step 3: Formatting with MLFS..."
    
    # Find mlfs_blockdev tool
    BLOCKDEV_TOOL=""
    for path in "../build/tools/mlfs_blockdev/mlfs_blockdev" \
                "../build-coverage/tools/mlfs_blockdev/mlfs_blockdev"; do
        if [ -f "$path" ]; then
            BLOCKDEV_TOOL="$path"
            break
        fi
    done
    
    if [ -z "$BLOCKDEV_TOOL" ]; then
        log_error "mlfs_blockdev tool not found. Build it first:"
        log_error "  cd .. && mkdir build && cd build && cmake .. && make"
        exit 1
    fi
    
    # Format image
    echo "YES" | "$BLOCKDEV_TOOL" "$TEST_IMG" format
    "$BLOCKDEV_TOOL" "$TEST_IMG" mkpart 1 32 4096 test
    echo "YES" | "$BLOCKDEV_TOOL" "$TEST_IMG" mkfs 0
    
    "$BLOCKDEV_TOOL" -r "$TEST_IMG" info
    log_info "✓ Image formatted with MLFS"
    echo ""
    
    # Step 4: Setup loop device
    log_info "Step 4: Setting up loop device..."
    sudo losetup "$LOOP_DEV" "$TEST_IMG"
    log_info "✓ Loop device $LOOP_DEV created"
    echo ""
    
    # Step 5: Load module
    log_info "Step 5: Loading kernel module..."
    sudo insmod mlfs.ko debug=1
    
    if ! lsmod | grep -q "^mlfs "; then
        log_error "Failed to load module"
        exit 1
    fi
    log_info "✓ Module loaded"
    sudo dmesg | tail -5 | grep mlfs
    echo ""
    
    # Step 6: Create mount point
    log_info "Step 6: Creating mount point..."
    mkdir -p "$MOUNT_POINT"
    log_info "✓ Mount point created at $MOUNT_POINT"
    echo ""
    
    # Step 7: Mount filesystem
    log_info "Step 7: Mounting MLFS filesystem..."
    sudo mount -t mlfs -o partition=0 "$LOOP_DEV" "$MOUNT_POINT"
    
    if ! mountpoint -q "$MOUNT_POINT"; then
        log_error "Failed to mount filesystem"
        sudo dmesg | tail -20 | grep mlfs
        exit 1
    fi
    log_info "✓ Filesystem mounted"
    mount | grep mlfs
    echo ""
    
    # Step 8: Test filesystem
    log_info "Step 8: Testing filesystem access..."
    
    log_info "Listing root directory..."
    ls -la "$MOUNT_POINT/"
    
    log_info "Showing filesystem statistics..."
    df -h "$MOUNT_POINT"
    stat -f "$MOUNT_POINT"
    
    log_info "✓ Filesystem accessible"
    echo ""
    
    # Step 9: Check kernel messages
    log_info "Step 9: Kernel messages..."
    sudo dmesg | grep mlfs | tail -20
    echo ""
    
    # Success
    log_info "================================"
    log_info "✓ All tests passed!"
    log_info "================================"
    echo ""
    log_info "The filesystem is mounted at: $MOUNT_POINT"
    log_info "You can now:"
    log_info "  - List files: ls -la $MOUNT_POINT"
    log_info "  - Show info: stat -f $MOUNT_POINT"
    log_info "  - Watch logs: sudo dmesg -w | grep mlfs"
    echo ""
    log_warn "Press Enter to cleanup and exit..."
    read
}

# Run main function
main

