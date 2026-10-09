#!/bin/bash
# mainline-config.sh <kernel-src> <build-dir> <initramfs-dir> [make args...]
#   arm64 defconfig trimmed to MediaTek (the image must stay near ChromeOS's ~33 MB uncompressed: depthcharge
#   decompresses into a fixed buffer), plus everything stage 1 needs built in: MT8189 clocks/pinctrl/power domains,
#   watchdog, pstore/ramoops console, embedded (xz) initramfs, lockup/hang panics with a 5 s panic timeout, PCIe +
#   Panfrost + the MT8189 GPU clock (stage 3); display: mediatek DRM, eDP, panel-edp, PWM backlight, fbcon (stage 4); EC keyboard/battery, touchpad, touchscreen (stage 5); USB + USB-Ethernet; Wi-Fi off while PCIe is parked. The PCIe controller driver is a module, loaded by /init under a timeout (its probe froze the SoC
#   when built in), and copied into the initramfs by mainline-cycle.sh.
set -euo pipefail
src=$(realpath "$1"); out=$(realpath -m "$2"); ird=$(realpath "$3"); shift 3
mkdir -p "$out"
make -C "$src" -s ARCH=arm64 O="$out" "$@" defconfig
S() { "$src/scripts/config" --file "$out/.config" "$@"; }
# every SoC platform except MediaTek
for a in $(grep -o '^CONFIG_ARCH_[A-Z0-9_]*=y' "$out/.config" | sed 's/CONFIG_//; s/=y//'); do
  case $a in ARCH_MEDIATEK|ARCH_HAS_*|ARCH_SUPPORTS_*|ARCH_USE_*|ARCH_WANT*|ARCH_MMAP_*|ARCH_INLINE_*|ARCH_PROC_*|\
    ARCH_SPARSEMEM_*|ARCH_HIBERNATION_*|ARCH_SUSPEND_*|ARCH_SELECT_*|ARCH_ENABLE_*|ARCH_BINFMT_*|ARCH_KEEP_*|\
    ARCH_CORRECT_*|ARCH_STACK*|ARCH_HAVE_*|ARCH_DMA_*|ARCH_SPLIT_*|ARCH_FORCE_*|ARCH_NR_*|ARCH_SEC_*|ARCH_MHP_*|\
    ARCH_DEFAULT_*|ARCH_CLOCK*|ARCH_RANDOM*|ARCH_FLAT*|ARCH_PFN*|ARCH_MIGHT*|ARCH_HIBER*|ARCH_HUGETLB*|ARCH_DIS*) ;;
    *) S -d "$a" ;;
  esac
done
S -e COMMON_CLK_MT8189 -e COMMON_CLK_MT8189_BUS -e COMMON_CLK_MT8189_DBGAO -e COMMON_CLK_MT8189_DVFSRC \
  -e COMMON_CLK_MT8189_IIC -e COMMON_CLK_MT8189_SCP -e COMMON_CLK_MT8189_UFS -e PINCTRL_MT8189 \
  -e MTK_SCPSYS_PM_DOMAINS -e MEDIATEK_WATCHDOG -e SERIAL_8250_MT6577 \
  -e PSTORE -e PSTORE_RAM -e PSTORE_CONSOLE -e PSTORE_PMSG -d PSTORE_COMPRESS -e DEBUG_FS \
  -e BLK_DEV_INITRD --set-str INITRAMFS_SOURCE "$ird" --set-val INITRAMFS_ROOT_UID "$(id -u)" --set-val INITRAMFS_ROOT_GID "$(id -g)" \
  -e SOFTLOCKUP_DETECTOR -e DETECT_HUNG_TASK -e HARDLOCKUP_DETECTOR -e BOOTPARAM_HARDLOCKUP_PANIC \
  --set-val PANIC_TIMEOUT 5 -e WATCHDOG_HANDLE_BOOT_ENABLED \
  -d DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT -d DEBUG_INFO_DWARF4 -d DEBUG_INFO_DWARF5 -e DEBUG_INFO_NONE \
  -e DRM -e DRM_PANFROST -e COMMON_CLK_MT8189_MFG -e PM_DEVFREQ -e DEVFREQ_GOV_SIMPLE_ONDEMAND -e REGULATOR_COUPLER -e ARM_MEDIATEK_CPUFREQ_HW -e CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
  -d DRM_NOUVEAU -d DRM_RADEON -d DRM_AMDGPU -d DRM_MSM -d DRM_TEGRA -d DRM_ETNAVIV -d DRM_LIMA -d DRM_PANTHOR -d DRM_V3D \
  -d DRM_VC4 -d DRM_ROCKCHIP -d DRM_EXYNOS -d DRM_SUN4I -d DRM_MESON -d DRM_IMX -d DRM_RCAR_DU -d DRM_HISI_HIBMC -d DRM_HISI_KIRIN \
  -d DRM_I2C_ADV7511 -d DRM_DISPLAY_CONNECTOR -d DRM_LONTIUM_LT9611 -d DRM_SIMPLE_BRIDGE -d DRM_PANEL_SIMPLE \
  -d SOUND -d MEDIA_SUPPORT -d BT -d NFC -d CAN -d INFINIBAND -d MD -d SCSI_LOWLEVEL \
  -d VIRTUALIZATION -d KVM -d XEN -d STAGING -d SURFACE_PLATFORMS \
  -d ETHERNET -d WIRELESS_WAN -d IEEE802154 -d WAN -d ATM -d HAMRADIO -d MDIO_DEVICE \
  -d BTRFS_FS -d XFS_FS -d NFS_FS -d NFSD -d CEPH_FS -d CIFS -d 9P_FS -d F2FS_FS -d SQUASHFS -d OVERLAY_FS \
  -d IIO -d HWMON -d INPUT_TOUCHSCREEN -d INPUT_JOYSTICK -d INPUT_TABLET -d RC_CORE -d USB_GADGET -d TYPEC \
  -d SPI_FSL_DSPI -d NET_DSA -d BRIDGE -d NETFILTER -d CRYPTO_DEV_CCREE -d REMOTEPROC -d RPMSG -d PCI_ENDPOINT \
  -d ACPI -d ATA -d MTD -d EFI -d NFS_COMMON -d ROOT_NFS -d FTRACE -d KPROBES -d PROFILING -d DEBUG_FS_ALLOW_ALL \
  -d MT7921E -m CFG80211 -m MAC80211 -e WLAN -e WLAN_VENDOR_REALTEK -m RTW88 -m RTW88_8821AU \
  -e COMMON_CLK_MT8189_MMSYS -e MTK_CMDQ -e MTK_MMSYS -e DRM_MEDIATEK -e DRM_MEDIATEK_DP -e PHY_MTK_EDP -d DRM_MEDIATEK_HDMI \
  -e DRM_PANEL_EDP -e DRM_DISPLAY_DP_AUX_BUS -e PWM -e PWM_MTK_DISP -e BACKLIGHT_CLASS_DEVICE -e BACKLIGHT_PWM \
  -e FB -e DRM_FBDEV_EMULATION -e FRAMEBUFFER_CONSOLE -e COREBOOT_FIRMWARE -e COREBOOT_TABLE -e COREBOOT_FRAMEBUFFER -e COREBOOT_MEMCONSOLE -e DRM_SIMPLEDRM \
  -e CHROME_PLATFORMS -e CROS_EC -e CROS_EC_SPI -e KEYBOARD_CROS_EC -e I2C_CROS_EC_TUNNEL -e BATTERY_SBS \
  -e SPI -e SPI_MT65XX -e I2C_MT65XX -e INPUT_EVDEV -e MOUSE_ELAN_I2C -e MOUSE_ELAN_I2C_I2C -e HID -e I2C_HID_OF_ELAN \
  -e PHY_MTK_XSPHY -e USB_NET_DRIVERS -e USB_USBNET -e USB_RTL8152 -e USB_NET_AX88179_178A -e USB_NET_CDCETHER \
  -e USB_NET_CDC_NCM -e USB_NET_CDC_EEM -e USB_NET_RNDIS_HOST \
  -m PCIE_MEDIATEK_GEN3 -e PHY_MTK_TPHY -e PCI -e PCIEPORTBUS -e MODULES -e DYNAMIC_DEBUG -e MAGIC_SYSRQ \
  -e RD_XZ -e INITRAMFS_COMPRESSION_XZ -d INITRAMFS_COMPRESSION_GZIP \
  --set-str LOCALVERSION "-quigon" -d LOCALVERSION_AUTO
# DISP_MODULES=1: the display drivers as modules, which /init loads one at a time (mainline-cycle.sh MODS=...)
[[ -n ${DISP_MODULES:-} ]] && S -m DRM_MEDIATEK -m DRM_MEDIATEK_DP -m MTK_MMSYS -m PHY_MTK_EDP
make -C "$src" -s ARCH=arm64 O="$out" "$@" olddefconfig
