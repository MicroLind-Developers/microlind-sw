#!/bin/bash
# MLFS Coverage Analysis Script
# Automates the setup and execution of code coverage analysis

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}MLFS Code Coverage Analysis${NC}"
echo "============================="

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

# Check for required tools
MISSING_TOOLS=""

if ! command -v cmake &> /dev/null; then
    MISSING_TOOLS="${MISSING_TOOLS} cmake"
fi

if ! command -v gcc &> /dev/null && ! command -v clang &> /dev/null; then
    MISSING_TOOLS="${MISSING_TOOLS} gcc/clang"
fi

if ! command -v lcov &> /dev/null; then
    MISSING_TOOLS="${MISSING_TOOLS} lcov"
fi

if ! command -v genhtml &> /dev/null; then
    MISSING_TOOLS="${MISSING_TOOLS} genhtml"
fi

if [ -n "$MISSING_TOOLS" ]; then
    echo -e "${RED}Missing required tools:${MISSING_TOOLS}${NC}"
    echo -e "${YELLOW}Install with:${NC}"
    echo "  Ubuntu/Debian: sudo apt-get install cmake gcc lcov"
    echo "  RHEL/CentOS:   sudo yum install cmake gcc lcov"
    echo "  macOS:         brew install cmake lcov"
    exit 1
fi

echo -e "${GREEN}All prerequisites found!${NC}"

# Setup build directory
BUILD_DIR="build-coverage"
echo -e "\n${YELLOW}Setting up build directory: ${BUILD_DIR}${NC}"

if [ -d "$BUILD_DIR" ]; then
    echo "Cleaning existing build directory..."
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure with coverage
echo -e "\n${YELLOW}Configuring CMake with coverage enabled...${NC}"
cmake -DENABLE_COVERAGE=ON .. || {
    echo -e "${RED}CMake configuration failed!${NC}"
    exit 1
}

# Build
echo -e "\n${YELLOW}Building project...${NC}"
make -j$(nproc) || {
    echo -e "${RED}Build failed!${NC}"
    exit 1
}

# Run coverage analysis
echo -e "\n${YELLOW}Running coverage analysis...${NC}"
make coverage-report || {
    echo -e "${RED}Coverage analysis failed!${NC}"
    echo -e "${YELLOW}Trying individual targets...${NC}"
    
    # Try just the basic coverage collection
    make coverage || {
        echo -e "${RED}Basic coverage collection failed!${NC}"
        exit 1
    }
    
    # Try HTML generation separately
    make coverage-html || {
        echo -e "${YELLOW}HTML generation failed, but coverage data was collected${NC}"
    }
    
    # Show summary even if HTML failed
    make coverage-summary || {
        echo -e "${YELLOW}Summary display failed, but coverage data was collected${NC}"
    }
}

# Display results
echo -e "\n${GREEN}Coverage analysis complete!${NC}"
echo "=============================="

# Check if HTML report was generated
HTML_REPORT="coverage/html/index.html"
if [ -f "$HTML_REPORT" ]; then
    echo -e "\n${GREEN}HTML Report:${NC} $PWD/$HTML_REPORT"
    
    # Try to open in browser
    if command -v xdg-open &> /dev/null; then
        echo -e "${BLUE}Opening in browser...${NC}"
        xdg-open "$HTML_REPORT" &
    elif command -v open &> /dev/null; then
        echo -e "${BLUE}Opening in browser...${NC}"
        open "$HTML_REPORT" &
    else
        echo -e "${YELLOW}To view the report, open:${NC} file://$PWD/$HTML_REPORT"
    fi
else
    echo -e "${RED}HTML report not found!${NC}"
fi

# Show coverage summary
echo -e "\n${GREEN}Quick Summary:${NC}"
if [ -f "coverage/coverage_cleaned.info" ]; then
    lcov --summary coverage/coverage_cleaned.info | grep -E "(lines|functions|branches)" || true
fi

echo -e "\n${BLUE}Available commands in build directory:${NC}"
echo "  make coverage         - Collect coverage data"
echo "  make coverage-html    - Generate HTML report"
echo "  make coverage-summary - Show text summary"
echo "  make coverage-clean   - Clean coverage data"

echo -e "\n${GREEN}Coverage analysis script completed successfully!${NC}"
