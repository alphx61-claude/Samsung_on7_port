#!/bin/sh
# Copy the On7 display packages into the pmaports checkout that pmbootstrap
# uses, then regenerate the checksums.
#
# Run `pmbootstrap init` first — that is what creates the checkout.
#
# Usage:
#   scripts/apply-to-pmaports.sh [path-to-pmaports]
#
# With no argument the path comes from `pmbootstrap config aports`.
set -eu

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

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
cp "$REPO_DIR"/kernel/patches/*.patch "$KDIR"/
cp "$REPO_DIR"/pmaports/linux-postmarketos-qcom-msm8916/APKBUILD "$KDIR"/
cp "$REPO_DIR"/pmaports/linux-postmarketos-qcom-msm8916/on7-display.config "$KDIR"/

echo ">> installing device package"
cp "$REPO_DIR"/pmaports/device-samsung-on7/APKBUILD "$DDIR"/
cp "$REPO_DIR"/pmaports/device-samsung-on7/modules-initfs "$DDIR"/
cp "$REPO_DIR"/pmaports/device-samsung-on7/deviceinfo "$DDIR"/

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
