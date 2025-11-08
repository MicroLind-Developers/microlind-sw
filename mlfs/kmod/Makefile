# Makefile for MLFS kernel module

obj-m += mlfs.o
mlfs-objs := mlfs_module.o mlfs_proc.o

# Force use of system make (not any IDE/editor wrappers)
MAKE := /usr/bin/make

# Kernel source directory
KDIR ?= /lib/modules/$(shell uname -r)/build

# Current directory
PWD := $(shell pwd)

# Default target
all:
	@if [ ! -d "$(KDIR)" ]; then \
		echo ""; \
		echo "ERROR: Kernel headers not found!"; \
		echo ""; \
		echo "Kernel headers are required to build kernel modules."; \
		echo "Looking for: $(KDIR)"; \
		echo ""; \
		echo "Install them with:"; \
		echo "  Ubuntu/Debian:  sudo apt-get install linux-headers-$$(uname -r)"; \
		echo "  Arch Linux:     sudo pacman -S linux-headers"; \
		echo "  RHEL/CentOS:    sudo yum install kernel-devel"; \
		echo "  Fedora:         sudo dnf install kernel-devel"; \
		echo ""; \
		exit 1; \
	fi
	$(MAKE) -C $(KDIR) M=$(PWD) modules

# Clean target
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

# Install module
install: all
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install
	depmod -a

# Load module
load:
	sudo insmod mlfs.ko

# Unload module
unload:
	sudo rmmod mlfs

# Show module info
info:
	modinfo mlfs.ko

# Test with sample device
test: all
	@echo "Loading MLFS module..."
	-sudo rmmod mlfs 2>/dev/null
	sudo insmod mlfs.ko debug=1
	@echo "Module loaded. Check dmesg for messages."
	@echo ""
	@echo "To mount:"
	@echo "  sudo mount -t mlfs -o partition=0 /dev/sdb /mnt/mlfs"
	@echo ""
	@echo "To unmount:"
	@echo "  sudo umount /mnt/mlfs"
	@echo ""
	@echo "To unload:"
	@echo "  sudo rmmod mlfs"

.PHONY: all clean install load unload info test

