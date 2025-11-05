#!/bin/bash
# Example usage script for MLFS CLI

echo "MLFS CLI Example Usage"
echo "======================"

# Build the CLI (assuming we're in the mlfs directory)
echo "Building MLFS CLI..."
mkdir -p build
cd build
cmake ..
make mlfs_cli

if [ $? -eq 0 ]; then
    echo "✓ Build successful"
else
    echo "✗ Build failed"
    exit 1
fi

# Create example disk image
echo ""
echo "Creating example disk image..."
./cli/mlfs << EOF
format example.img 32 4096
mount example.img
mkdir documents
mkdir logs
touch readme.txt 1
write readme.txt "Welcome to MLFS - MicroLind File System!"
touch config.ini 1
write config.ini "[settings]\nversion=0.3\nblock_size=4096"
ls
cat readme.txt
cat config.ini
info
unmount
quit
EOF

echo ""
echo "Example completed! You can now run:"
echo "  ./cli/mlfs example.img"
echo ""
echo "Or interactively:"
echo "  ./cli/mlfs"
