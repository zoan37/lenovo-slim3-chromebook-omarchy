#!/bin/bash
# vdec-dump.sh <out>: snapshot of the MT8189 video decoder's registers, clocks and power domains, for diffing the
# ChromeOS kernel (decoder works) against mainline (decoder never raises its interrupt). Run as root WHILE a decode
# is running (VDE0 powered): reading the vdec blocks with VDE0 off faults. Needs memdump (bringup/memdump.c).
out=${1:?out file}
{
echo "# $(uname -r)"
for r in "0x16000000 0x1000 vdec_soc" "0x16025000 0x1000 vdec_core_misc" "0x1602e000 0x400 larb4" \
         "0x1602f000 0x100 vdec_core_cg" "0x10000000 0x400 topckgen" "0x1c001e00 0x160 spm_pwr" \
         "0x10001c00 0x40 infra_bus_prot" "0x1e800000 0x200 mminfra_cg" "0x1e801000 0x400 smi_common"; do
  set -- $r; echo "## $3 $1 $2"; memdump "$1" "$2"
done
echo "## irq"; grep -E " 520 Level|vcodec|vdec" /proc/interrupts
echo "## clk"; grep -i -E "vdec|univpll_d4 |mminfra|gce|smi|larb" /sys/kernel/debug/clk/clk_summary
echo "## genpd"; cat /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null
} > "$out" 2>&1
echo "wrote $out ($(wc -l < "$out") lines)"
