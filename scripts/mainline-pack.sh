#!/bin/bash
# mainline-pack.sh <build-dir> <tag> [extra cmdline]
#   On the laptop: lz4 the kernel Image, wrap it with mt8189-quigon.dtb in a FIT whose configuration matches quigon
#   (google,obiwan-rev3-sku196620 / -sku196620 / google,obiwan; depthcharge picks the FIT config by these), copy it
#   to the Chromebook and arm it in the boot-once slot (quigon-test-kernel). The next reboot runs it once.
#   DTB=<name> picks another DTB from the build (default mt8189-quigon). The kernel's built-in initramfs does the test; afterwards `mainline-log` (scripts/mainline-log.sh) on the
#   Chromebook shows its console from pstore. FULL=1 boots the Omarchy install (ROOT-C) on the mainline kernel instead.
#   BRINGUP=<flags> sets the bring-up flags that keep unused clocks/power domains/regulators on. Default: none for
#   FULL=1 (the full DTS describes every user; mt8189-quigon.dts keeps the unclaimed PMIC rails on), all three for the
#   test initramfs, whose partial DTBs leave hardware without a driver.
set -euo pipefail
if [[ -n ${FULL:-} ]]; then bringup=${BRINGUP-}; else bringup=${BRINGUP-clk_ignore_unused pd_ignore_unused regulator_ignore_unused}; fi
B=${1:?build dir}; tag=${2:?tag}; extra=${3:-}
host=${QUIGON_HOST:-root@192.168.0.22}
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
lz4 -q -9 -f "$B/arch/arm64/boot/Image" "$w/Image.lz4"
cp "$B/arch/arm64/boot/dts/mediatek/${DTB:-mt8189-quigon}.dtb" "$w/quigon.dtb"
cat > "$w/image.its" <<ITS
/dts-v1/;
/ {
	description = "quigon mainline test $tag";
	#address-cells = <1>;
	images {
		kernel {
			description = "Linux $tag";
			data = /incbin/("Image.lz4");
			type = "kernel_noload";
			arch = "arm64";
			os = "linux";
			compression = "lz4";
			load = <0>;
			entry = <0>;
		};
		fdt-1 {
			description = "mt8189-quigon.dtb";
			data = /incbin/("quigon.dtb");
			type = "flat_dt";
			arch = "arm64";
			compression = "none";
		};
	};
	configurations {
		default = "conf-1";
		conf-1 {
			compatible = "google,obiwan-rev3-sku196620", "google,obiwan-sku196620", "google,obiwan";
			description = "quigon mainline test";
			kernel = "kernel";
			fdt = "fdt-1";
		};
	};
};
ITS
(cd "$w" && dtc -q -I dts -O dtb -o image.fit image.its)
if [[ -n ${FULL:-} ]]; then
  # FULL=1: boot the real Omarchy install on ROOT-C (sda7) instead of the test initramfs (rdinit points nowhere, so
  # the kernel skips the embedded initramfs and mounts root= itself). No boot-time watchdog arming: nothing in
  # Omarchy feeds it. The console still lands in pstore for mainline-log.
  echo "console=tty0 loglevel=6 panic=10 $bringup irqchip.gicv3_pseudo_nmi=1 rdinit=/quigon-no-initramfs init=/sbin/init root=/dev/sda7 rootwait rw systemd.gpt_auto=0 net.ifnames=0 lsm=capability,landlock,yama,bpf quigon.test=$tag $extra" > "$w/cmdline"
else
  echo "loglevel=8 ignore_loglevel panic=5 softlockup_panic=1 hung_task_panic=1 $bringup mtk_wdt.start_timeout=31 watchdog.open_timeout=20 irqchip.gicv3_pseudo_nmi=1 rdinit=/init printk.devkmsg=on quigon.test=$tag $extra" > "$w/cmdline"
fi
ls -la "$w/image.fit" | awk '{print "FIT", $5, "bytes"}'
scp -q "$w/image.fit" "$w/cmdline" "$host:/root/kern-backup/"
ssh "$host" "mv /root/kern-backup/image.fit /root/kern-backup/$tag.fit && mv /root/kern-backup/cmdline /root/kern-backup/$tag.cmdline && quigon-test-kernel --vmlinuz /root/kern-backup/$tag.fit /root/kern-backup/$tag.cmdline"
