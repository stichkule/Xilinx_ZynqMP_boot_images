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

# Connect to hw_server. IMPORTANT -- replace <YOUR_URL> with the hostname/IP address of machine running hw_server
connect -url TCP:<YOUR_URL>:3121
 
# Disable Security gates to view PMU MB target
targets -set -filter {name =~ "PSU"}
mwr 0xffca0038 0x1ff
after 500
   
# Load and run PMUFW
targets -set -filter {name =~ "MicroBlaze PMU"}
dow ./boot_files/zynqmp_pmufw.elf
con
after 500
   
# Reset A53, load and run FSBL
targets -set -filter {name =~ "Cortex-A53 #0"}
rst -processor
dow ./boot_files/zynqmp_fsbl.elf
con
   
# Give FSBL time to run
after 500
stop
   
# Download u-boot and ATF binaries
dow ./boot_files/u-boot.elf
after 500
dow ./boot_files/bl31.elf
after 500
con
 
# Loading bitstream to PL
targets -set -nocase -filter {name =~ "*PL*"}
after 500
fpga -no-revision-check ./boot_files/system.bit
after 500
 
# Download FIT image
targets -set -filter {name =~ "Cortex-A53 #0"}
stop
dow -data ./boot_files/image.ub 0x10000000
con
disconnect
