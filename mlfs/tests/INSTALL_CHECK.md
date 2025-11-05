# Installing Check Framework

The MLFS test suite uses the Check C unit testing framework. You need to install Check before building the tests.

## Installation Instructions

### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install libcheck-dev
```

### RHEL/CentOS/Fedora
```bash
# RHEL/CentOS
sudo yum install check-devel

# Fedora
sudo dnf install check-devel
```

### macOS
```bash
brew install check
```

### Arch Linux
```bash
sudo pacman -S check
```

### Building from Source
If Check is not available in your package manager:

```bash
# Download and build Check
wget https://github.com/libcheck/check/releases/download/0.15.2/check-0.15.2.tar.gz
tar xzf check-0.15.2.tar.gz
cd check-0.15.2
./configure
make
sudo make install
```

## Verifying Installation

You can verify Check is properly installed:
```bash
pkg-config --exists check && echo "Check is installed" || echo "Check not found"
pkg-config --modversion check  # Show version
```

## Building MLFS Tests

Once Check is installed:
```bash
cd mlfs/
mkdir build && cd build
cmake ..
make
ctest --output-on-failure --verbose
```

## Troubleshooting

### Check not found during CMake configuration
- Make sure Check development packages are installed (not just runtime)
- Verify pkg-config can find Check: `pkg-config --libs --cflags check`
- On some systems, you may need to update PKG_CONFIG_PATH

### Runtime errors
- Ensure Check shared libraries are in your library path
- On Linux: `sudo ldconfig` after installing Check
- On macOS: Check if Homebrew paths are in your environment

### Permission errors during testing
- Tests create temporary files and may need write permissions
- Run tests from a writable directory
- Check that `/tmp` or equivalent is writable
