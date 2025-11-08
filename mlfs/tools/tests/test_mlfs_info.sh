#!/bin/bash

# Test script for mlfs_info tool
# Creates a test MLFS image and analyzes it with mlfs_info

echo "MLFS Info Tool Test Script"
echo "========================="
echo ""

# Build the tools if they don't exist
if [ ! -f "../../build/tools/mlfs_info/mlfs_info" ]; then
    echo "Building MLFS tools..."
    cd ../..
    mkdir -p build
    cd build
    cmake ..
    make tools
    cd tools/tests
    echo ""
fi

# Create a test filesystem using the CLI
echo "Creating test filesystem..."
cat > test_commands.txt << 'EOF'
format test_info.img 8 4096
mount test_info.img

# Create directory structure for testing
mkdir documents
mkdir photos
mkdir config

cd documents
mkdir reports
mkdir presentations
cd reports
mkdir 2024
mkdir archived

# Create some files with content
cd /
write readme.txt "Welcome to MLFS!\nThis is a test filesystem for demonstrating mlfs_info tool."
write documents/overview.txt "Documents directory overview\nContains reports and presentations."
write documents/reports/summary.txt "Summary Report\n==============\nQuarterly analysis complete."
write documents/reports/2024/q1_report.txt "Q1 2024 Report\nRevenue: $1M\nGrowth: 15%"

cd photos
mkdir vacation
mkdir work
write vacation/beach.jpg "Beach photo metadata (simulated)"
write work/meeting.jpg "Team meeting photo metadata"

cd /config
write settings.ini "app_name=MLFS Demo\nversion=1.0\nlog_level=INFO"
write database.conf "host=localhost\nport=5432\ndatabase=mlfs_test"

# Show final structure
cd /
ls
ls documents
ls documents/reports

quit
EOF

if [ -f "../../build/tools/cli/mlfs" ]; then
    echo "Running CLI to create test filesystem..."
    ../../build/tools/cli/mlfs < test_commands.txt > /dev/null 2>&1
    echo ""
else
    echo "Error: MLFS CLI not found. Building entire project..."
    cd ../..
    mkdir -p build
    cd build  
    cmake ..
    make
    cd tools/tests
    echo ""
    
    # Try again
    ../../build/tools/cli/mlfs < test_commands.txt > /dev/null 2>&1
fi

# Test the mlfs_info tool
if [ -f "../../build/tools/mlfs_info/mlfs_info" ] && [ -f "test_info.img" ]; then
    echo "Running mlfs_info analysis..."
    echo "============================="
    echo ""
    ../../build/tools/mlfs_info/mlfs_info test_info.img
    echo ""
    echo "Test completed successfully!"
    echo ""
    echo "The mlfs_info tool displayed:"
    echo "- Partition table information"
    echo "- Superblock details"
    echo "- Block allocation statistics"
    echo "- Complete directory tree with files and metadata"
else
    echo "Error: mlfs_info tool or test image not found."
    echo "Please ensure the project builds successfully."
fi

# Cleanup
rm -f test_commands.txt test_info.img

echo ""
echo "Try running mlfs_info on your own MLFS images:"
echo "  ../../build/tools/mlfs_info/mlfs_info <your_image_file.img>"
