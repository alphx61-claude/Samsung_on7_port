#!/bin/sh
# Copy the On7 display packages into the pmaports checkout that pmbootstrap
# uses, then regenerate the checksums.
#
# Run `pmbootstrap init` first — that is what creates the checkout.
#
# Usage, from a clone of this repo:
#   scripts/apply-to-pmaports.sh [path-to-pmaports]
#
# Or without cloning anything at all:
#   curl -fsSL https://raw.githubusercontent.com/alphx61-claude/Samsung_on7_port/HEAD/scripts/apply-to-pmaports.sh | sh
#
# Run on its own it downloads the patches and packages it needs. With no
# pmaports argument the path comes from `pmbootstrap config aports`.
set -eu

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd || echo "")
RAW_URL=https://raw.githubusercontent.com/alphx61-claude/Samsung_on7_port/HEAD

# Files this script installs, as repository-relative paths.
FILES="kernel/patches/0001-drm-panel-Add-Samsung-S6D7AA0X62-BV050HDM-panel-driv.patch
kernel/patches/0002-drm-panel-Add-Ilitek-ILI9881C-SKI550002-panel-driver.patch
kernel/patches/0003-backlight-Add-TI-LMU-LM3632-backlight-driver.patch
kernel/patches/0004-arm64-dts-qcom-msm8916-samsung-on7-Add-display-and-t.patch
pmaports/linux-postmarketos-qcom-msm8916/APKBUILD
pmaports/linux-postmarketos-qcom-msm8916/on7-display.config
pmaports/device-samsung-on7/APKBUILD
pmaports/device-samsung-on7/modules-initfs
pmaports/device-samsung-on7/deviceinfo"

# Piped straight from curl there is no repo next to the script, so fetch the
# files instead. SRC is what everything below copies from.
if [ -n "$REPO_DIR" ] && [ -d "$REPO_DIR/kernel/patches" ]; then
	SRC=$REPO_DIR
	echo ">> source: $SRC"
else
	command -v curl >/dev/null 2>&1 || {
		echo "error: no local copy of the repo, and curl is not installed" >&2
		exit 1
	}
	SRC=$(mktemp -d)
	trap 'rm -rf "$SRC"' EXIT INT TERM
	echo ">> no local copy found, downloading from GitHub"
	for f in $FILES; do
		mkdir -p "$SRC/${f%/*}"
		curl -fsSL -o "$SRC/$f" "$RAW_URL/$f" || {
			echo "error: failed to download $f" >&2
			exit 1
		}
	done
	echo ">> downloaded $(echo "$FILES" | wc -l | tr -d ' ') files"
fi

if [ $# -ge 1 ]; then
	APORTS=$1
else
	command -v pmbootstrap >/dev/null 2>&1 || {
		echo "error: pmbootstrap not in PATH, and no pmaports path given" >&2
		echo "usage: $0 [path-to-pmaports]" >&2
		exit 1
	}
	APORTS=$(pmbootstrap config aports 2>/dev/null || true)
fi

if [ -z "${APORTS:-}" ] || [ ! -d "$APORTS" ]; then
	echo "error: pmaports checkout not found${APORTS:+ at $APORTS}" >&2
	echo "hint: run 'pmbootstrap init' first, or pass the path explicitly" >&2
	exit 1
fi

KDIR=$APORTS/device/community/linux-postmarketos-qcom-msm8916
DDIR=$APORTS/device/testing/device-samsung-on7

for d in "$KDIR" "$DDIR"; do
	[ -d "$d" ] || {
		echo "error: expected package directory missing: $d" >&2
		echo "hint: is $APORTS really a pmaports checkout?" >&2
		exit 1
	}
done

echo ">> pmaports: $APORTS"

# Keep a copy of anything being overwritten, so this is undoable.
BACKUP=$APORTS/.on7-display-backup
if [ ! -d "$BACKUP" ]; then
	mkdir -p "$BACKUP/linux-postmarketos-qcom-msm8916" "$BACKUP/device-samsung-on7"
	cp "$KDIR"/APKBUILD "$BACKUP/linux-postmarketos-qcom-msm8916/"
	cp "$DDIR"/APKBUILD "$DDIR"/modules-initfs "$BACKUP/device-samsung-on7/"
	echo ">> backed up originals to $BACKUP"
else
	echo ">> backup already exists at $BACKUP, leaving it alone"
fi

echo ">> installing kernel patches and config fragment"
cp "$SRC"/kernel/patches/*.patch "$KDIR"/
cp "$SRC"/pmaports/linux-postmarketos-qcom-msm8916/APKBUILD "$KDIR"/
cp "$SRC"/pmaports/linux-postmarketos-qcom-msm8916/on7-display.config "$KDIR"/

echo ">> installing device package"
cp "$SRC"/pmaports/device-samsung-on7/APKBUILD "$DDIR"/
cp "$SRC"/pmaports/device-samsung-on7/modules-initfs "$DDIR"/
cp "$SRC"/pmaports/device-samsung-on7/deviceinfo "$DDIR"/

if command -v pmbootstrap >/dev/null 2>&1; then
	echo ">> regenerating checksums"
	pmbootstrap checksum linux-postmarketos-qcom-msm8916 device-samsung-on7
else
	echo ">> pmbootstrap not in PATH; run this yourself:"
	echo "   pmbootstrap checksum linux-postmarketos-qcom-msm8916 device-samsung-on7"
fi

cat <<EOF

Done. Next:

  pmbootstrap install
  pmbootstrap flasher flash_kernel
  pmbootstrap flasher flash_rootfs

To undo, restore the originals from:
  $BACKUP
EOF
