#!/bin/sh
# Turn the postmarketOS initramfs debug shell on (or off) for this device.
#
# Why: the initramfs takes 172.16.42.1 very early, so the phone answers ping
# long before it has finished booting. Without the debug shell there is nothing
# to log into unless the boot actually fails, and even then only after a 30
# second timeout. With `pmos.debug-shell` the initramfs stops and gives you a
# shell straight after the splash, before it looks for any partition.
#
# It gives you three ways in at once:
#   - telnet on 172.16.42.1 port 23
#   - a USB ACM gadget, so /dev/ttyACM0 on the host — a serial console with no
#     3.5mm UART cable needed
#   - kernel console output stays enabled instead of being silenced
#
# Usage:
#   scripts/enable-debug-shell.sh [--disable] [path-to-pmaports]
#
# With no path, it comes from `pmbootstrap config aports`.
#
# Then rebuild and reflash just the boot image:
#   pmbootstrap install
#   pmbootstrap flasher flash_kernel
#
# The root filesystem is untouched, so there is no need to flash it again.
set -eu

DISABLE=false
APORTS=""
for arg in "$@"; do
	case "$arg" in
		--disable) DISABLE=true ;;
		*) APORTS=$arg ;;
	esac
done

if [ -z "$APORTS" ]; then
	command -v pmbootstrap >/dev/null 2>&1 || {
		echo "error: pmbootstrap not in PATH, and no pmaports path given" >&2
		echo "usage: $0 [--disable] [path-to-pmaports]" >&2
		exit 1
	}
	APORTS=$(pmbootstrap config aports 2>/dev/null || true)
fi

[ -n "$APORTS" ] && [ -d "$APORTS" ] || {
	echo "error: pmaports checkout not found${APORTS:+ at $APORTS}" >&2
	exit 1
}
DDIR=$APORTS/device/testing/device-samsung-on7
CMDLINE=$DDIR/kernel-cmdline.conf
APKBUILD=$DDIR/APKBUILD

[ -f "$CMDLINE" ] || {
	echo "error: $CMDLINE not found" >&2
	echo "hint: run scripts/apply-to-pmaports.sh first" >&2
	exit 1
}

if grep -q "pmos.debug-shell" "$CMDLINE"; then
	if [ "$DISABLE" = true ]; then
		grep -v "pmos.debug-shell" "$CMDLINE" > "$CMDLINE.new"
		mv "$CMDLINE.new" "$CMDLINE"
		echo ">> debug shell disabled"
	else
		echo ">> debug shell already enabled, nothing to do"
		exit 0
	fi
elif [ "$DISABLE" = true ]; then
	echo ">> debug shell already disabled, nothing to do"
	exit 0
else
	echo "pmos.debug-shell" >> "$CMDLINE"
	echo ">> debug shell enabled"
fi

echo ">> kernel cmdline is now:"
sed 's/^/     /' "$CMDLINE"

# The boot image is rebuilt from this package, so pmbootstrap has to be told
# the package changed or it reuses the previously built binary.
_rel=$(sed -n 's/^pkgrel=\([0-9]\+\)$/\1/p' "$APKBUILD" | head -1)
[ -n "$_rel" ] || {
	echo "error: could not read pkgrel from $APKBUILD" >&2
	exit 1
}
sed -i "s/^pkgrel=$_rel\$/pkgrel=$((_rel + 1))/" "$APKBUILD"
echo ">> device-samsung-on7 pkgrel $_rel -> $((_rel + 1))"

if command -v pmbootstrap >/dev/null 2>&1; then
	echo ">> regenerating checksums"
	if ! pmbootstrap checksum device-samsung-on7; then
		echo "error: 'pmbootstrap checksum' failed" >&2
		exit 1
	fi
else
	echo ">> pmbootstrap not in PATH; run this yourself:"
	echo "   pmbootstrap checksum device-samsung-on7"
fi

cat <<MSG

Now rebuild and reflash only the boot image:

  pmbootstrap install
  pmbootstrap flasher flash_kernel

Reboot with USB connected, give the host interface an address:

  IF=\$(ls /sys/class/net | grep -E '^(usb|enx)' | head -1)
  sudo ip link set "\$IF" up
  sudo ip addr add 172.16.42.2/24 dev "\$IF" 2>/dev/null || true

Then get in, whichever works:

  telnet 172.16.42.1
  sudo screen /dev/ttyACM0 115200      # or: sudo picocom -b 115200 /dev/ttyACM0

At the shell, 'cat /README' explains it, and 'pmos_continue_boot' resumes the
boot so you can watch where it goes wrong.
MSG
