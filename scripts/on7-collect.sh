#!/bin/sh
# Collect display diagnostics from a Samsung Galaxy On7 (2015).
#
# Works in two places:
#   - Termux / adb shell on the stock or LineageOS ROM (downstream kernel).
#     This is where the panel identity comes from, so run it here FIRST.
#   - An SSH or serial shell on postmarketOS (mainline kernel), to see what
#     the mainline drivers did with it.
#
# Usage:
#   sh on7-collect.sh > on7-report.txt
#
# Root is optional. Without it a few sections come back empty, which is fine;
# the important ones do not need root.
#
# Serial numbers, IMEIs, MAC addresses and WiFi keys are scrubbed from the
# output. Read the file before sharing it.

# Deliberately no `set -e`: a missing sysfs file must not abort the run.

say() {
	echo
	echo "===== $* ====="
}

# Print a file if it exists, else say so. Never fail.
show() {
	if [ -r "$1" ]; then
		cat "$1" 2>/dev/null
	else
		echo "(not readable: $1)"
	fi
}

# Run a command if it exists. Never fail.
try() {
	if command -v "$1" >/dev/null 2>&1; then
		"$@" 2>&1
	else
		echo "(no $1)"
	fi
}

# Best-effort privileged dmesg. LineageOS ships su as an optional addon, so
# this is allowed to come back empty.
kmsg() {
	if dmesg >/dev/null 2>&1; then
		dmesg 2>/dev/null
	elif command -v su >/dev/null 2>&1; then
		su -c dmesg 2>/dev/null
	else
		echo "(dmesg needs root here)"
	fi
}

main() {
	if [ -r /system/build.prop ] || command -v getprop >/dev/null 2>&1; then
		PLATFORM=android
	else
		PLATFORM=linux
	fi

	echo "on7-collect: platform=$PLATFORM date=$(date 2>/dev/null)"
	echo "uname: $(uname -a 2>/dev/null)"

	say "PANEL IDENTITY (the important one)"
	# The Samsung bootloader passes the detected panel here. This single line
	# decides which mainline panel driver the device needs.
	echo "--- mdss_mdp.panel from /proc/cmdline ---"
	tr ' ' '\n' < /proc/cmdline 2>/dev/null | grep -i 'mdss_mdp3\?\.panel=' || \
		echo "(no mdss_mdp.panel= in cmdline)"

	echo
	echo "--- msm_fb_panel_info ---"
	for f in /sys/class/graphics/fb0/msm_fb_panel_info; do
		show "$f"
	done

	echo
	echo "--- Samsung lcd class ---"
	for f in /sys/class/lcd/*/lcd_type /sys/class/lcd/*/window_type; do
		[ -e "$f" ] || continue
		printf '%s: ' "$f"
		cat "$f" 2>/dev/null || echo "(unreadable)"
	done

	say "DEVICE / BOARD REVISION"
	if [ "$PLATFORM" = android ]; then
		for p in ro.product.model ro.product.device ro.product.name \
			 ro.bootloader ro.boot.bootloader ro.boot.hardware \
			 ro.boot.hw_rev ro.build.version.release ro.build.display.id; do
			printf '%s = %s\n' "$p" "$(getprop $p 2>/dev/null)"
		done
	fi
	echo "--- full cmdline ---"
	show /proc/cmdline

	say "BACKLIGHT"
	try ls -l /sys/class/backlight/
	for d in /sys/class/backlight/*/; do
		[ -d "$d" ] || continue
		echo "--- $d"
		for a in brightness max_brightness actual_brightness bl_power type; do
			[ -e "$d$a" ] || continue
			printf '  %s = %s\n' "$a" "$(cat "$d$a" 2>/dev/null)"
		done
	done

	say "DISPLAY STATE"
	if [ "$PLATFORM" = android ]; then
		echo "--- fb0 ---"
		for a in modes virtual_size bits_per_pixel name blank; do
			[ -e "/sys/class/graphics/fb0/$a" ] || continue
			printf '  %s = %s\n' "$a" "$(cat "/sys/class/graphics/fb0/$a" 2>/dev/null)"
		done
	else
		echo "--- DRM connectors ---"
		for d in /sys/class/drm/*/; do
			[ -e "$d/status" ] || continue
			printf '%s: status=%s enabled=%s\n' "$(basename "$d")" \
				"$(cat "$d/status" 2>/dev/null)" \
				"$(cat "$d/enabled" 2>/dev/null)"
			[ -s "$d/modes" ] && sed 's/^/    mode: /' "$d/modes" 2>/dev/null
		done
		echo "--- panel compatible from live device tree ---"
		find /proc/device-tree -name compatible -path '*panel*' 2>/dev/null | \
			while read -r f; do
				printf '%s: ' "$f"
				tr '\0' ' ' < "$f" 2>/dev/null
				echo
			done
		echo "--- loaded display modules ---"
		try lsmod | grep -iE 'panel|msm|lmu|lm363x|backlight|zinitix' || \
			echo "(none matched)"
	fi

	say "I2C BUSES"
	try i2cdetect -l

	say "TOUCHSCREEN"
	if [ "$PLATFORM" = android ]; then
		for f in /sys/class/sec/tsp/status /sys/class/sec/tsp/cmd_result; do
			[ -e "$f" ] || continue
			printf '%s: %s\n' "$f" "$(cat "$f" 2>/dev/null)"
		done
	fi
	try ls /sys/class/input/

	say "KERNEL LOG (display related)"
	kmsg | grep -iE 'panel|mdss|dsi|lm3632|lmu|backlight|lcd|zinitix|drm|msm_drm' | tail -120

	say "KERNEL LOG (errors)"
	kmsg | grep -iE 'error|fail|timeout|-110|-517|EPROBE' | tail -60

	echo
	echo "===== END ====="
}

# Everything above runs inside main() so the whole report can be filtered.
# Drop identifiers that have no diagnostic value but do identify the handset.
# Kept to plain BRE so busybox and toybox sed handle it the same as GNU sed;
# the strings below are lowercase everywhere they actually occur.
main | sed \
	-e 's/serialno=[^ ]*/serialno=<redacted>/g' \
	-e 's/ro.serialno = .*/ro.serialno = <redacted>/' \
	-e 's/imei[^ ]*=[^ ]*/imei=<redacted>/g' \
	-e 's/meid[^ ]*=[^ ]*/meid=<redacted>/g' \
	-e 's/[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]/<mac-redacted>/g' \
	-e 's/psk=[^ ]*/psk=<redacted>/g'
