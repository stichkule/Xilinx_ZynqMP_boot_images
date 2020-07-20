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

# Builds FSBL for ZynqMP as a Vitis project
proc build_fsbl {xsa} {
    setws workspace_fsbl
    app create -name fsbl -hw $xsa -os standalone -proc psu_cortexa53_0 -template {Zynq MP FSBL} -lang C
    app build -name fsbl
    file copy -force workspace_fsbl/fsbl/Debug/fsbl.elf boot_files/zynqmp_fsbl.elf
}

# Builds PMUFW for ZynqMP as a Vitis project
proc build_pmufw {xsa} {
    setws workspace_pmufw
    app create -name pmufw -hw $xsa -os standalone -proc psu_pmu_0 -template {ZynqMP PMU Firmware} -lang C
    app build -name pmufw
    file copy -force workspace_pmufw/pmufw/Debug/pmufw.elf boot_files/zynqmp_pmufw.elf
}

# Generates device-tree source files based on hardware design (XSA file)
proc build_dts {xsa} {
    hsi::open_hw_design $xsa
    hsi::set_repo_path ./repo
    set procs [hsi::get_cells -filter {IP_TYPE==PROCESSOR}]
    puts "Targeting [lindex $procs 0]"
    set processor [lindex $procs 0]
    hsi::create_sw_design device-tree -os device_tree -proc $processor
    hsi::generate_target -dir my_dts
    hsi::close_hw_design [hsi::current_hw_design]
}

# Copies board-specific dtsi file, and modifies system-top.dts to include the relevant files
proc copy_dtsi {version} {
    file copy -force  ./repo/my_dtg/device-tree-xlnx/device_tree/data/kernel_dtsi/${version}/BOARD/zcu102-rev1.0.dtsi my_dts
    set fp [open my_dts/system-top.dts r]
    set file_data [read $fp]
    close $fp
    set data [split $file_data "\n"]
    set fileId [open my_dts/system-top.dts "w"]
    foreach line $data {
        if {[regexp {zynqmp-clk-ccf.dtsi} $line] == 1} {
            puts $fileId "#include \"zynqmp-clk-ccf.dtsi\""
            puts $fileId "#include \"zcu102-rev1.0.dtsi\""
        } else {
            puts $fileId $line
        }
    }
    close $fileId
}

# Generates BOOT.BIN containing the bitstream, FSBL, PMUFW, ATF, and u-boot binaries
proc generate_boot {} {
    set fileId [open boot_files/bootgen.bif "w"]
    puts $fileId "the_ROM_image:"
    puts $fileId "{"
    puts $fileId "      \[fsbl_config\] a53_x64"
    puts $fileId "      \[bootloader\] zynqmp_fsbl.elf"
    puts $fileId "      \[pmufw_image\] zynqmp_pmufw.elf"
    puts $fileId "      \[destination_device=pl\] system.bit"
    puts $fileId "      \[destination_cpu=a53-0,exception_level=el-3,trustzone\] bl31.elf"
    puts $fileId "      \[destination_cpu=a53-0,exception_level=el-2\] u-boot.elf"
    puts $fileId "}"
    close $fileId
    cd boot_files
    exec bootgen -arch zynqmp -image bootgen.bif -o i BOOT.BIN -w on
    cd ..
}

# Creates a ITS file listing components of the FIT image
proc generate_its {args} {
	puts "Generating ITS"
	set image_dir 0
	set error 0
	for {set i 0} {$i < [llength $args]} {incr i} {
		if {[lindex $args $i] == "-image_dir"} {
			set image_dir [lindex $args [expr {$i + 1}]]
		}
	}
	if {$image_dir != 0} {
		set image [glob -nocomplain -directory $image_dir -type f Image]
		if {$image != ""} {
			set image [file tail $image]
		} else {
			puts "Error: Image not found. Please run make image"
			set error 1
		}
		set dtb [glob -nocomplain -directory $image_dir -type f *dtb]
		if {$dtb != ""} {
			set dtb [file tail $dtb]
		} else {
			puts "Error: DTB not found. Please run make dtb"
			set error 1
		}
		set rfs [glob -nocomplain -directory $image_dir -type f *.cpio.gz]
		if {$rfs != ""} {
			set rfs [file tail $rfs]
		} else {
			puts "Error: RootFS not found. Please run make rootfs"
			set error 1
		}
	} else {
		set error 1
	}
	
	if {$error != 1} {
		set fileId [open boot_files/fitimage.its "w"]
		puts $fileId "/dts-v1/;"
		puts $fileId "" 
		puts $fileId "/ {"
		puts $fileId "    description = \"U-Boot fitImage for plnx_aarch64 kernel\";"
		puts $fileId "    #address-cells = <1>;"
		puts $fileId ""
		puts $fileId "    images {"
		puts $fileId "        kernel@0 {"
		puts $fileId "            description = \"Linux Kernel\";"
		puts $fileId "            data = /incbin/(\"./${image}\");"
		puts $fileId "            type = \"kernel\";"
		puts $fileId "            arch = \"arm64\";"
		puts $fileId "            os = \"linux\";"
		puts $fileId "            compression = \"none\";"
		puts $fileId "            load = <0x80000>;"
		puts $fileId "            entry = <0x80000>;"
		puts $fileId "            hash@1 {"
		puts $fileId "                algo = \"sha1\";"
		puts $fileId "            };"
		puts $fileId "        };"
		puts $fileId "        fdt@0 {"
		puts $fileId "            description = \"Flattened Device Tree blob\";"
		puts $fileId "            data = /incbin/(\"./${dtb}\");"
		puts $fileId "            type = \"flat_dt\";"
		puts $fileId "            arch = \"arm64\";"
		puts $fileId "            compression = \"none\";"
		puts $fileId "            hash@1 {"
		puts $fileId "                algo = \"sha1\";"
		puts $fileId "            };"
		puts $fileId "        };"
		puts $fileId "        ramdisk@0 {"
		puts $fileId "            description = \"ramdisk\";"
		puts $fileId "            data = /incbin/(\"./${rfs}\");"
		puts $fileId "            type = \"ramdisk\";"
		puts $fileId "            arch = \"arm64\";"
		puts $fileId "            os = \"linux\";"
		puts $fileId "            compression = \"none\";"
		puts $fileId "            hash@1 {"
		puts $fileId "                algo = \"sha1\";"
		puts $fileId "            };"
       	puts $fileId "        };"
       	puts $fileId "    };"
		puts $fileId "    configurations {"
		puts $fileId "        default = \"conf@1\";"
		puts $fileId "        conf@1 {"
		puts $fileId "            description = \"Boot Linux kernel with FDT blob + ramdisk\";"
		puts $fileId "            kernel = \"kernel@0\";"
		puts $fileId "            fdt = \"fdt@0\";"
		puts $fileId "            ramdisk = \"ramdisk@0\";"
		puts $fileId "            hash@1 {"
		puts $fileId "                algo = \"sha1\";"
		puts $fileId "            };"
		puts $fileId "        };"
		puts $fileId "    };"
		puts $fileId "};"
		puts "boot_files/fitimage.its has been generated"
	} 
}
