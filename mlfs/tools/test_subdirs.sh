#!/bin/bash

# Test script for MLFS subdirectory functionality
# This script demonstrates the new nested directory support

echo "MLFS Subdirectory Test Script"
echo "============================="
echo ""

# Build the CLI if it doesn't exist
if [ ! -f "./build/cli/mlfs" ]; then
    echo "Building MLFS CLI..."
    mkdir -p build
    cd build
    cmake ..
    make
    cd ..
    echo ""
fi

# Create test commands in a temporary file
cat > test_commands.txt << 'EOF'
# Create and format a test filesystem
format test_subdirs.img 16 4096

# Mount the filesystem
mount test_subdirs.img

# Show we start in root
pwd

# Create some directories
mkdir documents
mkdir photos
mkdir config

# List root directory
ls

# Enter documents directory
cd documents

# Show current location
pwd

# Create subdirectories within documents
mkdir reports
mkdir presentations
mkdir drafts

# List documents directory contents
ls

# Create some files with spaces in content
touch readme.txt
write readme.txt "Welcome to the documents folder!\nThis demonstrates nested directory support."

# Enter reports subdirectory
cd reports

# Show we're now in nested directory
pwd

# Create files in nested directory
touch monthly_report.txt
write monthly_report.txt "Monthly Report\n=============\n\nAll systems operational.\nSubdirectory support is working!"

# Show file contents
cat monthly_report.txt

# Create another nested directory
mkdir archived

# Go deeper
cd archived
pwd
touch old_report.txt
write old_report.txt "This file is in /documents/reports/archived/"

# Test navigation
ls
cd ..
pwd
ls
cd ..
pwd
ls
cd /
pwd
ls

# Test absolute paths
write documents/reports/summary.txt "This was created using an absolute path!"
cat documents/reports/summary.txt

# Test relative paths from root
cd documents
write reports/final.txt "Created with relative path from documents directory"
cat reports/final.txt

# Navigate around and test more operations
cd /photos
pwd
mkdir vacation
mkdir work
ls
cd vacation
mkdir 2023
mkdir 2024
cd 2024
touch beach.jpg
touch mountain.jpg
ls
pwd

# Go back to root and show final structure
cd /
echo ""
echo "Final filesystem structure:"
echo "==========================="
ls
cd documents
echo "documents/:"
ls
cd reports  
echo "documents/reports/:"
ls
cd archived
echo "documents/reports/archived/:"
ls

# Test cleanup
cd /
rm documents/reports/archived/old_report.txt
rmdir documents/reports/archived
ls documents/reports/

# Exit
quit
EOF

echo "Running MLFS subdirectory tests..."
echo "=================================="
echo ""

# Run the CLI with the test commands
if [ -f "./build/cli/mlfs" ]; then
    ./build/cli/mlfs < test_commands.txt
else
    echo "Error: MLFS CLI not found. Please build the project first."
    exit 1
fi

echo ""
echo "Test completed!"
echo ""
echo "The test demonstrated:"
echo "- Creating nested directories (mkdir)"
echo "- Navigating with cd (., .., absolute paths, relative paths)"  
echo "- Creating files in subdirectories (touch)"
echo "- Writing content with spaces (write \"content with spaces\")"
echo "- Reading files from subdirectories (cat)"
echo "- Listing directory contents (ls)"
echo "- Using absolute and relative paths"
echo "- Removing files and directories from nested locations"

# Cleanup
# rm -f test_commands.txt test_subdirs.img
