#/******************************************************************************
#*
#* Copyright (C)  2020  Shiril Tichkule.
#*
#* Permission is granted to copy, distribute and/or modify this document
#* under the terms of the GNU Free Documentation License, Version 1.3
#* or any later version published by the Free Software Foundation;
#* with no Invariant Sections, no Front-Cover Texts, and no Back-Cover
#* Texts.  A copy of the license is included in the section entitled ``GNU
#* Free Documentation License''.
#*
#/******************************************************************************

SHELL := /bin/bash

# Xilinx tool version
VERSION ?= 2019.2

# Path to Xilinx System Command-line Tool (XSCT); IMPORTANT -- replace with your own Vitis installation path, for example /opt/Xilinx/Vitis/$(VERSION)/bin/xsct
XSCT=<Vitis_Installation_Path>/Vitis/$(VERSION)/bin/xsct

# Xilinx Support Archive (XSA) file containing hardware description
XSA_FILE ?= system.xsa

# Linux Root File System to be built into the FIT image
ROOTFS ?= rootfs.cpio.gz

# Targets
dtb: dts copy_dtsi run_dtc
image: rootfs kernel generate_its fit_image
all: get_sources boot_dir fsbl pmufw dtb uboot atf generate_boot image

# Clone required repositories from GIT
get_sources:
	# Xilinx device tree source and include files
	if [ ! -d "./repo" ];then \
		mkdir -p repo/my_dtg; \
		cd repo/my_dtg && git clone https://github.com/Xilinx/device-tree-xlnx; \
		cd device-tree-xlnx && git checkout xilinx-v$(VERSION); \
	fi
	# Xilinx fork of Das U-boot (second-stage bootloader for Linux)
	if [ ! -d "./u-boot-xlnx" ];then \
		git clone https://github.com/Xilinx/u-boot-xlnx; \
		cd u-boot-xlnx && git checkout xilinx-v$(VERSION); \
	fi
	# Xilinx ARM Trusted Firmware (required for running non-secure EL3 Linux on the A53 core)
	if [ ! -d "./arm-trusted-firmware" ];then \
		git clone https://github.com/Xilinx/arm-trusted-firmware; \
		cd arm-trusted-firmware && git checkout xilinx-v$(VERSION); \
	fi
	# Device Tree Compiler (dtc) to build the Device Tree Blob
	if [ ! -d "./dtc" ];then \
		git clone https://git.kernel.org/pub/scm/utils/dtc/dtc.git; \
		$(MAKE) -C dtc; \
	fi
	# Xilinx fork of the mainline Linux kernel
	if [ ! -d "./linux-xlnx" ];then \
		git clone https://github.com/Xilinx/linux-xlnx; \
		cd linux-xlnx && git checkout xilinx-v$(VERSION).01; \
	fi

# Create directory to hold boot images
boot_dir:
	$(RM) -r boot_files
	mkdir boot_files

# Some targets below invoke XSCT; see corresponding function in xsct_utils.tcl
# Build First Stage Boot Loader (FSBL) as a Vitis project
fsbl:
	$(RM) -r workspace_fsbl
	$(XSCT) -eval "source xsct_utils.tcl; build_fsbl $(XSA_FILE)"

# Build PMU Firmware (PMUFW) as a Vitis project
pmufw:
	$(RM) -r workspace_pmufw
	$(XSCT) -eval "source xsct_utils.tcl; build_pmufw $(XSA_FILE)"

# Genrate device-tree sources based on the XSA file
dts:
	$(RM) -r my_dts
	$(XSCT) -eval "source xsct_utils.tcl; build_dts $(XSA_FILE)"

# Copy board device-tree include (dtsi) file based on tool version	    
copy_dtsi:
	cp -rf linux-xlnx/include/ my_dts/include/
	$(XSCT) -eval "source xsct_utils.tcl; copy_dtsi $(VERSION)"

# Invoke devive-tree compiler (DTC) to build the device-tree blob (DTB)
run_dtc:
	$(RM) -r my_dts/system-top.dts.tmp
	$(RM) -r boot_files/zcu102.dtb
	gcc -I my_dts -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -o my_dts/system-top.dts.tmp my_dts/system-top.dts
	export PATH=$$PATH:$(shell pwd)/dtc && dtc -I dts -O dtb -o boot_files/zcu102.dtb my_dts/system-top.dts.tmp

# Build u-boot binary
uboot:
	$(MAKE) -C u-boot-xlnx clean
	export PATH=$$PATH:$(shell pwd)/dtc && export CROSS_COMPILE=aarch64-linux-gnu- && export ARCH=aarch64 && $(MAKE) -C u-boot-xlnx xilinx_zynqmp_zcu102_rev1_0_defconfig && $(MAKE) -C u-boot-xlnx all -j 16
	cp -f u-boot-xlnx/u-boot.elf boot_files

# Build ATF binary
atf:
	$(MAKE) -C arm-trusted-firmware CROSS_COMPILE=aarch64-linux-gnu- ARCH=aarch64 DEBUG=0 RESET_TO_BL31=1 PLAT=zynqmp bl31
	cp -f arm-trusted-firmware/build/zynqmp/release/bl31/bl31.elf boot_files

# Generate boot image (BOOT.BIN) using bootgen tool	
generate_boot:
	cp -f *.bit boot_files/system.bit
	$(XSCT) -eval "source xsct_utils.tcl; generate_boot"

# Copy rootfs archive to boot_files directory
rootfs:
	cp -f $(ROOTFS) boot_files

# Build the linux kernel image
kernel:
	$(MAKE) -C linux-xlnx clean
	export CROSS_COMPILE=aarch64-linux-gnu- && export ARCH=arm64 && $(MAKE) -C linux-xlnx xilinx_zynqmp_defconfig && $(MAKE) -C linux-xlnx all -j 32
	cp -f linux-xlnx/arch/arm64/boot/Image boot_files

# Create file to define components of the FIT image (kernel image, device-tree blob, and rootfs)
generate_its:
	$(RM) -r boot_files/fitimage.its
	$(XSCT) -eval "source xsct_utils.tcl; generate_its -image_dir boot_files"

# Build the FIT image (image.ub)	
fit_image:
	$(RM) -r boot_files/image.ub
	export PATH=$$PATH:$(shell pwd)/dtc && cd boot_files && ../u-boot-xlnx/tools/mkimage -f fitimage.its image.ub

# Clean build artifacts
clean:
	$(RM) -r boot_files repo workspace_* .Xil my_dts *.bit *.c *.h *.html psu_*
	if [ -d "./arm-trusted-firmware" ];then \
	$(MAKE) -C arm-trusted-firmware clean; \
	fi
	if [ -d "./u-boot-xlnx" ];then \
	$(MAKE) -C u-boot-xlnx clean; \
	fi
	if [ -d "./linux-xlnx" ];then \
	$(MAKE) -C linux-xlnx clean; \
	fi

# Delete cloned source repositories
remove_sources:
	$(RM) -r device-tree-xlnx u-boot-xlnx arm-trusted-firmware linux-xlnx dtc

# Clean build artifacts and delete sources
cleanall: clean remove_sources
