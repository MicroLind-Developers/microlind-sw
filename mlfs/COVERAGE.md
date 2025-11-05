# MLFS Code Coverage Analysis

This document explains how to use the automated code coverage analysis for the MLFS test suite.

## Prerequisites

### Install Coverage Tools

**Ubuntu/Debian:**
```bash
sudo apt-get install lcov gcov
```

**RHEL/CentOS/Fedora:**
```bash
sudo yum install lcov gcc  # or dnf install lcov gcc
```

**macOS:**
```bash
brew install lcov
# gcov comes with Xcode command line tools
```

### Requirements
- GCC or Clang compiler (for gcov support)
- lcov (for report generation)
- CMake 3.16+

## Quick Start

### 1. Enable Coverage and Build

```bash
# Configure with coverage enabled
mkdir build-coverage && cd build-coverage
cmake -DENABLE_COVERAGE=ON ..

# Build the project
make
```

### 2. Run Coverage Analysis

```bash
# Generate complete coverage report (HTML + summary)
make coverage-report
```

This will:
- Clean old coverage data
- Run all tests
- Collect coverage information
- Generate both HTML report and text summary

### 3. View Results

**HTML Report:**
```bash
# Open in browser
firefox build-coverage/coverage/html/index.html
# or
xdg-open build-coverage/coverage/html/index.html
```

**Text Summary:**
The coverage summary is displayed in the terminal after running `make coverage-report`.

## Available Coverage Targets

| Target | Description |
|--------|-------------|
| `coverage` | Run tests and collect coverage data |
| `coverage-html` | Generate HTML coverage report |
| `coverage-summary` | Display text coverage summary |
| `coverage-report` | Generate both HTML report and summary |
| `coverage-clean` | Clean all coverage data |

### Detailed Usage

**Basic coverage collection:**
```bash
make coverage
```

**Generate only HTML report:**
```bash
make coverage-html  # Requires 'coverage' to be run first
```

**Show only text summary:**
```bash
make coverage-summary  # Requires 'coverage' to be run first
```

**Clean coverage data:**
```bash
make coverage-clean
```

## Understanding Coverage Reports

### HTML Report Features

The HTML report (`build-coverage/coverage/html/index.html`) provides:
- **Overall coverage statistics** (line, function, branch coverage)
- **File-by-file breakdown** with clickable file names
- **Source code view** with color-coded coverage:
  - 🟢 **Green lines**: Executed by tests
  - 🔴 **Red lines**: Not executed by tests
  - 🟡 **Orange lines**: Partially executed (branches)
- **Function coverage details**
- **Branch coverage analysis**

### Text Summary Format

```
Overall coverage rate:
  lines......: 87.5% (350 of 400 lines)
  functions..: 95.2% (20 of 21 functions)
  branches...: 78.3% (47 of 60 branches)
```

### Coverage Scope

The coverage analysis includes:
- ✅ **Library code** (`lib/src/mlfs.c`)
- ❌ **Test code** (excluded from coverage)
- ❌ **CLI code** (excluded from coverage)
- ❌ **Tools code** (excluded from coverage)
- ❌ **System headers** (excluded from coverage)

This focuses coverage on the core MLFS library implementation.

## Coverage Goals

### Recommended Coverage Targets

- **Line Coverage**: > 90%
- **Function Coverage**: > 95%
- **Branch Coverage**: > 80%

### What Good Coverage Looks Like

**High Coverage Indicators:**
- All public API functions are tested
- Error handling paths are covered
- Edge cases and boundary conditions are tested
- Both success and failure scenarios are covered

**Areas That May Have Lower Coverage:**
- Error handling for truly exceptional cases
- Defensive programming assertions
- Platform-specific code paths

## Troubleshooting

### Coverage Not Working

**Problem**: No coverage data generated
```bash
# Check if gcov files are created
find . -name "*.gcno" -o -name "*.gcda"
```

**Solutions**:
1. Ensure you built with `-DENABLE_COVERAGE=ON`
2. Make sure GCC or Clang is being used
3. Verify lcov is installed and in PATH

### Low Coverage Numbers

**Problem**: Coverage seems too low

**Investigation Steps**:
1. Check if all tests are running: `make check`
2. Look at the HTML report to see which lines aren't covered
3. Consider adding tests for uncovered code paths

### Build Issues with Coverage

**Problem**: Linker errors with coverage enabled

**Solution**: Clean and rebuild completely:
```bash
rm -rf build-coverage
mkdir build-coverage && cd build-coverage  
cmake -DENABLE_COVERAGE=ON ..
make
```

### lcov Error: "exclude pattern is unused"

**Problem**: `lcov: ERROR: 'exclude' pattern '/usr/*' is unused`

**Cause**: No system headers are in the coverage data to exclude

**Solution**: The CMake configuration has been updated to handle this with `--ignore-errors unused`

### geninfo Warning: "unexecuted block"

**Problem**: `geninfo: WARNING: ... unexecuted block on non-branch line`

**Cause**: GCC coverage instrumentation quirk with certain code patterns

**Solution**: This is handled automatically with `--rc geninfo_unexecuted_blocks=1`

### Coverage Report Generation Fails

**Problem**: `make coverage-report` fails but tests run successfully

**Solutions**:
1. Try individual targets:
   ```bash
   make coverage          # Just collect data
   make coverage-summary  # Show text summary
   make coverage-html     # Generate HTML if data exists
   ```

2. Check if lcov version is compatible:
   ```bash
   lcov --version  # Should be 1.14 or later for best results
   ```

3. Use the robust script:
   ```bash
   ./run_coverage.sh  # Handles errors gracefully
   ```

## Integration with CI/CD

### Example GitHub Actions Integration

```yaml
- name: Run Coverage Analysis
  run: |
    mkdir build-coverage && cd build-coverage
    cmake -DENABLE_COVERAGE=ON ..
    make coverage-report

- name: Upload Coverage to Codecov
  uses: codecov/codecov-action@v3
  with:
    file: build-coverage/coverage/coverage_cleaned.info
    format: lcov
```

### Coverage Badge

The generated `coverage_cleaned.info` file can be uploaded to services like:
- Codecov
- Coveralls  
- SonarQube

## Best Practices

### Writing Coverage-Friendly Tests

1. **Test all public API functions**
2. **Test error conditions** - don't just test happy paths
3. **Test boundary values** - zero, maximum, minimum values
4. **Test invalid inputs** - ensure error handling works
5. **Use meaningful assertions** - verify actual behavior

### Improving Coverage

**Focus on uncovered lines:**
1. Run `make coverage-html`
2. Open the HTML report
3. Click on files with low coverage
4. Look for red (uncovered) lines
5. Write tests that exercise those code paths

**Common uncovered areas:**
- Error handling branches
- Edge case validations  
- Resource cleanup paths
- Defensive programming checks

### Maintaining Coverage

- **Run coverage regularly** during development
- **Set coverage requirements** in your development process
- **Review coverage reports** before merging changes
- **Add tests** when coverage drops below targets

## Advanced Usage

### Custom Coverage Filters

Edit the `LCOV_PATH --remove` section in `CMakeLists.txt` to customize what's excluded:

```cmake
COMMAND ${LCOV_PATH} --remove ${COVERAGE_INFO_FILE} 
    '/usr/*'           # System headers
    '*/tests/*'        # Test code
    '*/third_party/*'  # Third party code
    --output-file ${COVERAGE_CLEANED_FILE}
```

### Branch Coverage Analysis

Enable branch coverage for more detailed analysis:
```bash
# Add to CMakeLists.txt coverage flags:
set(COVERAGE_FLAGS "-fprofile-arcs -ftest-coverage --coverage -fprofile-generate")
```

### Integration with IDEs

Many IDEs can display coverage information:
- **Visual Studio Code**: Coverage Gutters extension
- **CLion**: Built-in coverage support
- **Eclipse CDT**: gcov integration

Load the generated `.gcda` files or lcov reports in your IDE for inline coverage display.
