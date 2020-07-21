# Makefile-based flow for generating Xilinx ZynqMP boot images

This repository provides a comprehensive methodology to generate boot images for boards based on the Xilinx ZynqMP architecture. The provided Makefile-based approach encapsulates steps that are typically executed in different Xilinx software environments (for example, Vitis, Petalinux, etc.), after the hardware design has been generated via Vivado. This encapsulation allows the user to generate the boot image (BOOT.BIN) and the Flexible-Image-Transport (FIT) file (image.ub) containing the Linux kernel image, simply by issuing a single `make` command. Details on the boot image components and the boot process can be found in [Xilinx UG1209](https://www.xilinx.com/support/documentation/sw_manuals/xilinx2019_2/ug1209-embedded-design-tutorial.pdf).

In this flow, bare-metal components (FSBL, PMUFW, ATF), bootloader (u-boot), and the linux-xlnx kernel image are built from their respective GIT sources. Hardware (design) specific information is parsed by XSCT utilities (found under the host machine's Vivado/Vitis installation), which is then combined with board-specific information by the open-source device-tree-compiler to yield the device-tree blob. Although this method produces generic boot images, the user can still modify/patch the individual software components and build them as individual targets using the Makefile, and then combine them to generate the final customized boot images.

## Prerequisites and host-machine setup

1. A Linux host machine installed with 2019.2 versions of Xilinx Vivado and Vitis softwares.
2. A Xilinx ZCU102 board
3. 2019.2 version of the Xilinx [ZCU102 BSP](https://www.xilinx.com/member/forms/download/xef.html?filename=xilinx-zcu102-v2019.2-final.bsp)

    **NOTE**: In case there are build errors due to missing packages on your host machine, it is recommended to install all packages listed on p. 10 of the document [UG1144](https://www.xilinx.com/support/documentation/sw_manuals/xilinx2019_2/ug1144-petalinux-tools-reference-guide.pdf)

## How to run

1. Extract the downloaded ZCU102 BSP
    ```
    $ tar -xvzf <zcu102_bsp>.bsp
    ```

2. Source Vivado and Vitis initialization scripts
    ```
    $ source <path_to_vivado>/Vivado/2019.2/settings64.sh
    $ source <path_to_vitis>/Vitis/2019.2/settings64.sh
    ```
    **NOTE**: Ensure to invoke `make` from the same shell in which the above two scripts have been sourced.

3. Clone the repository and checkout the `v2019.2` tag
    ```
    $ git clone https://github.com/stichkule/Xilinx_ZynqMP_boot_images.git && cd Xilinx_ZynqMP_boot_images
    $ git checkout v2019.2
    ```

4. Copy over the RootFS archive and hardware design (XSA file) from the extracted ZCU102 BSP to the repository
    ```
    $ cp <extracted_zcu102_bsp>/pre-built/linux/images/rootfs.cpio.gz ./
    $ cp <extracted_zcu102_bsp>/project-spec/hw-description/system.xsa ./
    ```
    **NOTE**: The user can choose to provide their own hardware design file (renamed as system.xsa) instead of the pre-built version from the BSP.

5. ***IMPORTANT***: Open the Makefile in a text-editor of your choice, and provide the correct Vitis installation path for the defined variable `XSCT`

6. We are now ready to generate the boot components. The following are a few examples:
	* Build the full set of boot images
    	```
    	make all
    	```
	* Clean ONLY the build artifacts
    	```
    	make clean
    	```
	* Clean everything (including cloned sources)
    	```
    	make cleanall
    	```

    After invoking `make`, and a successful build, the images can be found under the <boot_files> folder.

## Boot into a ZCU102 board via JTAG

The following sequence of steps can be used to boot a ZCU102 board in JTAG mode, by utilizing boot images generated above. Prior to this being done, ensure that the prerequisites listed below have been satisfied.

### Setup

1. Power up a ZCU102 board in JTAG mode (for DIP switch settings, refer to p. 30 of the UG1209 document above). Also make sure that both, the USB-to-JTAG and USB-to-UART connections are made between the board and the host machine.

2. Open up a serial connection into the board's 'Interface 0' port using a utility like Putty or TeraTerm (details and serial port settings can be found on p. 32 of UG1209).

3. In a different shell on the Linux host machine, invoke XSCT and launch the utility 'hw_server'. Note the URL displayed when this runs, since it will be used to communicate with the board via JTAG
    ```
    $ source <path_to_vitis>/Vitis/2019.2/settings64.sh
    $ xsct
    xsct% hw_server
    ```
    **NOTE**: Do not exit from or close this shell since 'hw_server' needs to be running continuously throughout the JTAG boot process.
4. ***IMPORTANT***: Open up the TCL script jtag_boot.tcl in a text-editor. Replace `<YOUR_URL>` in the `connect` command, with what was indicated by 'hw_server' in step 3 above.

### Running the boot script

1. Make sure that you are in the root directory of this repository, and then launch XSCT
    ```
    $ xsct
    ```
2. Source the boot script from the XSCT terminal
    ```
    xsct% source jtag_boot.tcl
    ```
3. On the board UART terminal, make sure to halt at uboot (prevent autoboot by pressing any key)
4. From the u-boot prompt, execute the following
    ```
    ZynqMP> bootm 0x10000000
    ```
The above command will load the FIT image that was downloaded into the DDR address 0x10000000, and will proceed to boot into Linux on your ZCU102 board.