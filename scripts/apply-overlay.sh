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

# --- generated-style DRM panel drivers --------------------------------------
# Both OPPO R9s panels are kept here: the 16017 Samsung EA8064 AMOLED, and the
# 16027 JDI R63452 cmd-mode LCD (the real device is 16027). Each file is copied
# and hooked into Kconfig/Makefile the same way (insert kconfig before endmenu,
# append obj to the panel Makefile).
KCFG="$KERNEL/drivers/gpu/drm/panel/Kconfig"
PMake="$KERNEL/drivers/gpu/drm/panel/Makefile"

add_panel() {
	# $1 = source .c basename (without path) under overlay dir, $2 = title,
	# $3 = config symbol, $4 = kconfig "depends on" clause.
	local base c_file sym kplt title
	base="$1"; title="$2"; sym="$3"; kplt="$4"
	c_file="drivers/gpu/drm/panel/$base"
	cp "$OVER/$c_file" "$KERNEL/$c_file"
	if ! grep -q "$sym" "$KCFG"; then
		# must land *inside* the menu, i.e. before the trailing endmenu
		awk -v S="$sym" -v T="$title" -v D="$kplt" '
		BEGIN { done = 0 }
		{
			if (!done && $0 ~ /^endmenu/) {
				print "config " S
				print "\ttristate \"" T "\""
				print "\tdepends on " D
				print "\thelp"
				print "\t  Say Y here to enable the OPPO R9s " T " driver."
				print ""
				done = 1
			}
			print
		}' "$KCFG" > "$KCFG.new" && mv "$KCFG.new" "$KCFG"
		echo "  added $sym to panel Kconfig"
	fi
	if ! grep -q "${base%.c}" "$PMake"; then
		printf 'obj-$(CONFIG_%s) += %s.o\n' "$sym" "${base%.c}" >> "$PMake"
		echo "  added ${base%.c}.o to panel Makefile"
	fi
}

add_panel "panel-oppo-ea8064.c" \
	"Samsung EA8064 AMOLED panel (OPPO R9s 16017)" \
	"DRM_PANEL_OPPO_EA8064" "OF && DRM_MIPI_DSI"
add_panel "panel-oppo-jdi-r63452.c" \
	"JDI R63452 cmd-mode panel (OPPO R9s 16027)" \
	"DRM_PANEL_JDI_R63452" "OF && DRM_MIPI_DSI"

echo "overlay applied"
