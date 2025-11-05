# MLFS Coverage Analysis Example

This example demonstrates how to use the automated code coverage analysis for MLFS.

## Method 1: Using the Coverage Script (Recommended)

The easiest way to get started:

```bash
# From the mlfs directory
./run_coverage.sh
```

This script will:
1. Check all prerequisites
2. Set up a coverage build directory  
3. Configure CMake with coverage enabled
4. Build the project
5. Run all tests with coverage collection
6. Generate both HTML and text reports
7. Automatically open the HTML report in your browser

## Method 2: Manual Step-by-Step

### Step 1: Install Prerequisites

**Ubuntu/Debian:**
```bash
sudo apt-get install cmake gcc lcov libcheck-dev
```

**macOS:**
```bash
brew install cmake lcov check
```

### Step 2: Configure and Build

```bash
# Create coverage build directory
mkdir build-coverage && cd build-coverage

# Configure with coverage enabled
cmake -DENABLE_COVERAGE=ON ..

# Build
make
```

### Step 3: Run Coverage Analysis

```bash
# Complete coverage analysis (recommended)
make coverage-report
```

This runs all tests and generates both HTML and text reports.

### Step 4: View Results

**HTML Report (detailed):**
```bash
# Linux
xdg-open coverage/html/index.html

# macOS  
open coverage/html/index.html

# Or manually open: build-coverage/coverage/html/index.html
```

**Text Summary (quick):**
```bash
make coverage-summary
```

## Understanding the Results

### Example Coverage Output

```
Overall coverage rate:
  lines......: 89.2% (315 of 353 lines)
  functions..: 100.0% (23 of 23 functions)  
  branches...: 82.5% (66 of 80 branches)
```

### What the Numbers Mean

- **Line Coverage**: Percentage of code lines executed by tests
- **Function Coverage**: Percentage of functions called by tests  
- **Branch Coverage**: Percentage of decision branches taken by tests

### Coverage Goals

- **Line Coverage**: Aim for >90% (excellent: >95%)
- **Function Coverage**: Aim for 100% (all public APIs tested)
- **Branch Coverage**: Aim for >80% (good: >85%)

## Improving Coverage

### Finding Uncovered Code

1. Open the HTML report (`coverage/html/index.html`)
2. Click on `mlfs.c` to see the source code
3. Look for red highlighted lines (uncovered code)
4. Write tests that exercise those code paths

### Example: Adding a Test for Uncovered Code

If you see an uncovered error handling branch like:
```c
if (block_size == 0) {
    return -1;  // <-- This line is red (uncovered)
}
```

Add a test to cover it:
```c
START_TEST(test_zero_block_size)
{
    mlfs_t fs;
    int result = mlfs_some_function(&fs, 0);  // Pass zero block size
    ck_assert_int_eq(result, -1);             // Verify error return
}
END_TEST
```

## Advanced Usage

### Individual Coverage Targets

```bash
# Just collect coverage data (no reports)
make coverage

# Generate only HTML report
make coverage-html

# Show only text summary  
make coverage-summary

# Clean coverage data
make coverage-clean
```

### Filtering Coverage

The coverage analysis automatically excludes:
- Test code (`tests/`)
- CLI code (`cli/`)
- Tool code (`tools/`)
- System headers (`/usr/*`)

Only the core MLFS library (`lib/src/mlfs.c`) is included in coverage metrics.

### Coverage During Development

**Workflow for maintaining coverage:**

1. Write new code
2. Run `make coverage-summary` to check coverage
3. If coverage drops, add tests for the new code
4. Repeat until coverage targets are met

**Quick coverage check:**
```bash
cd build-coverage
make coverage-summary
```

## Troubleshooting

### "No coverage data found"

**Cause**: Coverage wasn't enabled during build

**Solution**:
```bash
rm -rf build-coverage
mkdir build-coverage && cd build-coverage
cmake -DENABLE_COVERAGE=ON ..  # Make sure this flag is set
make coverage-report
```

### "lcov: command not found"

**Cause**: lcov is not installed

**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get install lcov

# macOS
brew install lcov
```

### Very Low Coverage Numbers

**Cause**: Tests aren't running or coverage data isn't being collected

**Investigation**:
```bash
# Check if tests pass
make check

# Check if .gcda files are created
find . -name "*.gcda" | head -5

# Look for .gcno files (created at compile time)
find . -name "*.gcno" | head -5
```

If no `.gcda` files exist, the tests aren't running. If no `.gcno` files exist, coverage wasn't enabled during compilation.

## Integration with Development

### Pre-commit Coverage Check

Add to your development workflow:
```bash
#!/bin/bash
# pre-commit-coverage.sh

cd build-coverage
make coverage-summary

# Extract line coverage percentage
COVERAGE=$(lcov --summary coverage/coverage_cleaned.info | grep "lines" | grep -o '[0-9]*\.[0-9]*%' | grep -o '[0-9]*\.[0-9]*')

if (( $(echo "$COVERAGE < 90.0" | bc -l) )); then
    echo "Coverage too low: ${COVERAGE}% (minimum: 90%)"
    exit 1
fi

echo "Coverage check passed: ${COVERAGE}%"
```

### Continuous Integration

Example GitHub Actions workflow:
```yaml
- name: Run Coverage Analysis
  run: |
    mkdir build && cd build
    cmake -DENABLE_COVERAGE=ON ..
    make coverage-report
    
- name: Upload Coverage
  uses: codecov/codecov-action@v3
  with:
    file: build/coverage/coverage_cleaned.info
```

This comprehensive coverage system helps ensure the quality and reliability of your MLFS implementation!
