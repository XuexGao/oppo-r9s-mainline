#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Copy this project's overlay into a msm8953-mainline kernel tree and hook the
# new files into the build. Done as an overlay + append rather than .patch files
# on purpose: a rebase of the upstream branch then cannot conflict with us.
#
# usage: apply-overlay.sh <kernel-tree> <overlay-dir>
set -eu

KERNEL=$1
OVER=$2

if [ ! -f "$KERNEL/Makefile" ]; then
	echo "not a kernel tree: $KERNEL" >&2
	exit 1
fi

# --- board device tree ------------------------------------------------------
DTS_REL=arch/arm64/boot/dts/qcom/msm8953-oppo-r9s.dts
cp "$OVER/$DTS_REL" "$KERNEL/$(dirname $DTS_REL)/"
MK="$KERNEL/arch/arm64/boot/dts/qcom/Makefile"
if ! grep -q 'msm8953-oppo-r9s.dtb' "$MK"; then
	printf 'dtb-$(CONFIG_ARCH_QCOM) += msm8953-oppo-r9s.dtb\n' >> "$MK"
	echo "  added $DTS_REL to qcom dtbs"
fi

# --- generated-style DRM panel driver ---------------------------------------
PANEL_REL=drivers/gpu/drm/panel/panel-oppo-ea8064.c
cp "$OVER/$PANEL_REL" "$KERNEL/$(dirname $PANEL_REL)/"

KCFG="$KERNEL/drivers/gpu/drm/panel/Kconfig"
PMake="$KERNEL/drivers/gpu/drm/panel/Makefile"

if ! grep -q DRM_PANEL_OPPO_EA8064 "$KCFG"; then
	# must land *inside* the menu, i.e. before the trailing endmenu
	awk '
	BEGIN { done = 0 }
	{
		if (!done && $0 ~ /^endmenu/) {
			print "config DRM_PANEL_OPPO_EA8064"
			print "\ttristate \"Samsung EA8064 AMOLED panel (OPPO R9s)\""
			print "\tdepends on OF && DRM_MIPI_DSI"
			print "\thelp"
			print "\t  Say Y here if you want to use the Samsung EA8064"
			print "\t  command-mode AMOLED panel as found on the OPPO R9s."
			print ""
			done = 1
		}
		print
	}' "$KCFG" > "$KCFG.new" && mv "$KCFG.new" "$KCFG"
	echo "  added DRM_PANEL_OPPO_EA8064 to panel Kconfig"
fi

if ! grep -q panel-oppo-ea8064 "$PMake"; then
	printf 'obj-$(CONFIG_DRM_PANEL_OPPO_EA8064) += panel-oppo-ea8064.o\n' >> "$PMake"
	echo "  added panel-oppo-ea8064.o to panel Makefile"
fi

echo "overlay applied"
