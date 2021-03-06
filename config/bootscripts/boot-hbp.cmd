# DO NOT EDIT THIS FILE
#
# Please edit /boot/armbianEnv.txt to set supported parameters
#

setenv rootdev "/dev/mmcblk${devnum}p1"
setenv verbosity "7"
setenv console "both"
setenv rootfstype "ext4"
#setenv disp_mode "1920x1080m60"

echo "Boot script loaded from ${devtype} ${devnum}"

#setenv load_addr "0x39000000"
#if test -e ${devtype} ${devnum} ${prefix}armbianEnv.txt; then
#	echo "Loading armbianEnv.txt"
#	load ${devtype} ${devnum} ${load_addr} ${prefix}armbianEnv.txt
#	env import -t ${load_addr} ${filesize}
#fi

if test "${logo}" = "disabled"; then setenv logo "logo.nologo"; fi

if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "console=tty1"; fi
if test "${console}" = "serial" || test "${console}" = "both"; then setenv consoleargs "${consoleargs} console=ttymxc0,115200"; fi

# get PARTUUID of first partition on SD/eMMC the boot script was loaded from
if test "${devtype}" = "mmc"; then part uuid mmc ${devnum}:1 partuuid; fi

echo "Set FDT for ${board_name} [$board,$board_rev,$soc]"
if test "${board}" = "imx8mq_hb" && test -e ${devtype} ${devnum} ${prefix}dtb/freescale/fsl-imx8mq-hummingboard-pulse.dtb; then setenv fdtfile "freescale/fsl-imx8mq-hummingboard-pulse.dtb"; fi
if test "${board}" = "imx8mq_hb" && test -e ${devtype} ${devnum} ${prefix}dtb/freescale/imx8mq-hummingboard-pulse.dtb; then setenv fdtfile "freescale/imx8mq-hummingboard-pulse.dtb"; fi

#setenv bootargs "root=${rootdev} rootfstype=${rootfstype} rootwait ${consoleargs} consoleblank=0 video=mxcfb0:dev=hdmi,${disp_mode},if=RGB24,bpp=32 coherent_pool=2M cma=256M@2G rd.dm=0 rd.luks=0 rd.lvm=0 raid=noautodetect pci=nomsi vt.global_cursor_default=0 loglevel=${verbosity} usb-storage.quirks=${usbstoragequirks} ${extraargs}"
setenv bootargs "root=${rootdev} rootfstype=${rootfstype} rootwait ${consoleargs} earlycon=ec_imx6q,0x30860000,115200 net.ifnames=0 consoleblank=0 loglevel=${verbosity} ubootpart=${partuuid} usb-storage.quirks=${usbstoragequirks} ${extraargs} ${extraboardargs}"

if test "${docker_optimizations}" = "on"; then setenv bootargs "${bootargs} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1"; fi

load ${devtype} ${devnum} ${ramdisk_addr_r} ${prefix}uInitrd
load ${devtype} ${devnum} ${kernel_addr_r} ${prefix}Image
load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}dtb/${fdtfile}
fdt addr ${fdt_addr_r}

echo "Booting Kernel: ${bootargs}"
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
