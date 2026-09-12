#!/bin/sh
# Install the On7 display packages into the pmaports checkout that pmbootstrap
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
#
# Upstream pmaports has archived device-samsung-on7 and firmware-samsung-on7
# as unmaintained, so this restores them into device/testing/ before patching.
set -eu

REPO_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd || echo "")
RAW_URL=https://raw.githubusercontent.com/alphx61-claude/Samsung_on7_port/HEAD

# Files this script installs, as repository-relative paths.
FILES="kernel/patches/1001-drm-panel-Add-Samsung-S6D7AA0X62-BV050HDM-panel-driv.patch
kernel/patches/1002-drm-panel-Add-Ilitek-ILI9881C-SKI550002-panel-driver.patch
kernel/patches/1003-backlight-Add-TI-LMU-LM3632-backlight-driver.patch
kernel/patches/1004-arm64-dts-qcom-msm8916-samsung-on7-Add-display-and-t.patch
pmaports/linux-postmarketos-qcom-msm8916/APKBUILD
pmaports/linux-postmarketos-qcom-msm8916/on7-display.config
pmaports/device-samsung-on7/APKBUILD
pmaports/device-samsung-on7/deviceinfo
pmaports/device-samsung-on7/modules-initfs
pmaports/device-samsung-on7/kernel-cmdline.conf
pmaports/firmware-samsung-on7/APKBUILD"

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

echo ">> pmaports: $APORTS"

# The kernel package moved from device/community to device/testing; accept both.
KDIR=""
for d in testing community; do
	if [ -d "$APORTS/device/$d/linux-postmarketos-qcom-msm8916" ]; then
		KDIR=$APORTS/device/$d/linux-postmarketos-qcom-msm8916
		break
	fi
done

if [ -z "$KDIR" ]; then
	echo "error: linux-postmarketos-qcom-msm8916 not found under $APORTS/device/" >&2
	echo >&2
	echo "What is actually at $APORTS:" >&2
	if [ -z "$(ls -A "$APORTS" 2>/dev/null)" ]; then
		echo "  (empty)" >&2
		echo >&2
		echo "Nothing has been cloned into it yet." >&2
		echo "Run 'pmbootstrap init' and let it finish, then try again." >&2
	else
		ls -A "$APORTS" 2>/dev/null | head -15 | sed 's/^/  /' >&2
		if [ -e "$APORTS/.git" ]; then
			echo >&2
			echo "git branch: $(git -C "$APORTS" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')" >&2
			echo "Try 'pmbootstrap pull' to refresh the checkout." >&2
		else
			echo >&2
			echo "This is not a git checkout, so probably not pmaports." >&2
			echo "Check 'pmbootstrap config aports', or pass the path:" >&2
			echo "  $0 /path/to/pmaports" >&2
		fi
	fi
	exit 1
fi
echo ">> kernel package: $KDIR"

# device-samsung-on7 and firmware-samsung-on7 are archived upstream as
# unmaintained, so pmbootstrap will not offer the device until they are back
# in device/testing.
restore_from_archive() {
	_pkg=$1
	_dst=$APORTS/device/testing/$_pkg
	_src=$APORTS/device/archived/$_pkg
	if [ -d "$_dst" ]; then
		echo ">> $_pkg already in device/testing"
	elif [ -d "$_src" ]; then
		echo ">> restoring $_pkg from device/archived"
		mkdir -p "$_dst"
		cp "$_src"/* "$_dst"/
	else
		echo "error: $_pkg is in neither device/testing nor device/archived" >&2
		exit 1
	fi
}

restore_from_archive device-samsung-on7
restore_from_archive firmware-samsung-on7
DDIR=$APORTS/device/testing/device-samsung-on7
FDIR=$APORTS/device/testing/firmware-samsung-on7

# Keep a copy of anything being overwritten, so this is undoable.
BACKUP=$APORTS/.on7-display-backup
if [ ! -d "$BACKUP" ]; then
	mkdir -p "$BACKUP/kernel"
	cp "$KDIR"/APKBUILD "$BACKUP/kernel/"
	echo ">> backed up the original kernel APKBUILD to $BACKUP"
else
	echo ">> backup already exists at $BACKUP, leaving it alone"
fi

echo ">> installing kernel patches and config fragment"
cp "$SRC"/kernel/patches/*.patch "$KDIR"/
cp "$SRC"/pmaports/linux-postmarketos-qcom-msm8916/APKBUILD "$KDIR"/
cp "$SRC"/pmaports/linux-postmarketos-qcom-msm8916/on7-display.config "$KDIR"/

echo ">> installing device and firmware packages"
cp "$SRC"/pmaports/device-samsung-on7/APKBUILD "$DDIR"/
cp "$SRC"/pmaports/device-samsung-on7/deviceinfo "$DDIR"/
cp "$SRC"/pmaports/device-samsung-on7/modules-initfs "$DDIR"/
cp "$SRC"/pmaports/device-samsung-on7/kernel-cmdline.conf "$DDIR"/
cp "$SRC"/pmaports/firmware-samsung-on7/APKBUILD "$FDIR"/

if command -v pmbootstrap >/dev/null 2>&1; then
	echo ">> regenerating checksums"
	pmbootstrap checksum linux-postmarketos-qcom-msm8916 \
		device-samsung-on7 firmware-samsung-on7
else
	echo ">> pmbootstrap not in PATH; run this yourself:"
	echo "   pmbootstrap checksum linux-postmarketos-qcom-msm8916 device-samsung-on7 firmware-samsung-on7"
fi

cat <<MSG

Done. Next:

  pmbootstrap init            # re-run: samsung / on7 is selectable now
  pmbootstrap install
  pmbootstrap flasher flash_kernel
  pmbootstrap flasher flash_rootfs

The original kernel APKBUILD is backed up at:
  $BACKUP
MSG
