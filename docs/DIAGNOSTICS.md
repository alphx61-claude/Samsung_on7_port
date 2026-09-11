# Getting diagnostics off the phone

There is no live connection between the phone and whoever is helping you — the
loop is: run something on the device, paste the output back. This page keeps
that loop to one round trip.

Run this **on your current LineageOS install, before flashing anything.** The
downstream kernel knows which panel your unit has; the mainline one can only
guess. Ten seconds here saves a reflash later.

## The 30-second version

Open Termux and run:

```sh
cat /proc/cmdline | tr ' ' '\n' | grep -i mdss
getprop ro.bootloader
cat /sys/class/graphics/fb0/msm_fb_panel_info 2>/dev/null | head -20
```

The first command is the one that matters. Expect something like:

```
mdss_mdp.panel=1:dsi:0:ss_dsi_panel_S6D7AA0X62_BV050HDM_HD:1:none:cfg:single_dsi
```

That name in the middle is your panel:

| If you see | Your panel is | Mainline compatible |
|---|---|---|
| `ss_dsi_panel_S6D7AA0X62_BV050HDM_HD` | Samsung S6D7AA0X62 | `samsung,s6d7aa0x62-bv050hdm` |
| `ss_dsi_panel_ILI9881C_SKI550002_HD` | Ilitek ILI9881C | `samsung,ili9881c-ski550002` |

Paste those three outputs back and that settles which driver your device needs.
If you see a third name, stop — this port only knows about those two, and I
would need the vendor DTS for whatever yours is.

## The full version

`scripts/on7-collect.sh` gathers the above plus backlight state, framebuffer
modes, I2C buses, touchscreen nodes and the display-related kernel log. It runs
unprivileged; root only adds `dmesg`.

Get it onto the phone, whichever is easiest:

```sh
# In Termux, if you can reach the repo:
pkg install curl
curl -fsSLO https://raw.githubusercontent.com/alphx61-claude/Samsung_on7_port/claude/postmarketos-galaxy-on7-display-yk71g2/scripts/on7-collect.sh

# Or from a computer with the phone connected:
adb push scripts/on7-collect.sh /sdcard/
adb shell sh /sdcard/on7-collect.sh > on7-report.txt
```

Then:

```sh
sh on7-collect.sh > on7-report.txt
```

The script scrubs serial numbers, IMEIs, MAC addresses and WiFi keys before
writing the file. Skim it anyway before pasting — it is your device.

## After flashing postmarketOS

The same script works over SSH on postmarketOS and switches to the mainline
checks: DRM connector status, the panel compatible the kernel actually bound,
loaded modules, backlight class.

```console
$ ssh user@172.16.42.1 'sh -s' < scripts/on7-collect.sh > on7-pmos-report.txt
```

If the screen is dark there, the three lines worth reading first are:

```console
$ dmesg | grep -i panel
$ cat /sys/class/drm/*/status
$ ls /sys/class/backlight/
```

A `connected` DSI connector with no backlight device means the LM3632 did not
probe. A missing connector means the panel driver did not bind — usually the
wrong compatible, which is what the first section of this page prevents.

## Termux notes

Termux on LineageOS 16 is unprivileged. That is fine for everything above
except `dmesg`, which Android restricts. If you have the LineageOS `su` addon
installed, the script picks it up automatically. If not, skip it — the panel
identity does not need root.

`pkg install termux-api` is not required. Nothing here needs network access on
the phone beyond fetching the script, and you can avoid even that with `adb
push`.
