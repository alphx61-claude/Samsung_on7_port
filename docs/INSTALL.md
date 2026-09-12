# Installing

## What this actually replaces

postmarketOS is **not a kernel you drop onto LineageOS**. The two cannot share a
device:

- LineageOS runs Samsung's downstream 3.10 kernel and needs Android HALs for
  graphics, audio and modem.
- postmarketOS runs a mainline 6.6 kernel with none of those. It is a different
  operating system, with a different init, userspace and driver model.

So installing it takes the **boot partition** (lk2nd plus the pmOS boot image)
and the **userdata partition** (the pmOS root filesystem). Your LineageOS
install goes with it.

This is reversible — reflash LineageOS, or stock firmware via Odin/Heimdall,
whenever you want the phone back. But back up anything on it first, because
`pmbootstrap install` erases userdata.

## What you need

- **A computer running Linux.** pmbootstrap does not run on the phone, and it
  needs Linux (WSL2 works; macOS is rough). This is the one hard prerequisite.
- `heimdall` (or Odin on Windows) to get lk2nd on, and `fastboot` after that.
- A USB cable that does data, not just charging.

## Before you start: get lk2nd back

If you are booting LineageOS right now, **lk2nd is not installed** — LineageOS
wrote its own boot image over it. You need to put it back before anything else
here works.

Check: hold Volume Down while powering on. If `fastboot devices` lists the
phone, lk2nd is there. If the phone just boots LineageOS, it is not.

To install it, use Samsung Download mode (Volume Down + Home + Power, then
Volume Up to confirm) — the stock Samsung bootloader has no fastboot, so this
first step goes through Heimdall:

```console
$ wget https://github.com/msm8916-mainline/lk2nd/releases/latest/download/lk2nd.img
$ heimdall flash --BOOT lk2nd.img
```

From then on lk2nd provides fastboot itself, entered by holding Volume Down
while booting.

One detail worth knowing: lk2nd lives at the *start* of the boot partition and
stores the OS boot image 512 KiB into it, so `fastboot flash boot boot.img`
later does not overwrite lk2nd. That is why installing LineageOS — which writes
at offset 0 — removes it.

## 1. Find out which panel you have

Do this *before* wiping, while Android is still installed.

If you are still on Android/LineageOS, the easiest check is one Termux command
— see [`DIAGNOSTICS.md`](DIAGNOSTICS.md). Otherwise, lk2nd reports the panel the
Samsung bootloader detected:

```console
$ fastboot getvar lk2nd:panel
lk2nd:panel: ss_dsi_panel_S6D7AA0X62_BV050HDM_HD
```

It is also shown in the lk2nd menu (hold Volume Up while booting), on the
`Panel:` line. Expect one of:

- `ss_dsi_panel_S6D7AA0X62_BV050HDM_HD` — Samsung S6D7AA0X62
- `ss_dsi_panel_ILI9881C_SKI550002_HD` — Ilitek ILI9881C

Write it down. If you get something else entirely, stop and open an issue with
the exact string — this port only knows about those two.

## 2. Build postmarketOS with the patches

Install pmbootstrap if you have not already:

```
pipx install pmbootstrap      # or: pip install --user pmbootstrap
```

Run `init` **first** — it is what clones pmaports, so there is nothing to patch
until it has run. It will not offer the On7 yet; that is expected and the next
step fixes it:

```
pmbootstrap init
```

Now apply everything. The helper resolves the pmaports path itself, restores
the two archived packages, installs the patches and regenerates the checksums:

```
curl -fsSL https://raw.githubusercontent.com/alphx61-claude/Samsung_on7_port/HEAD/scripts/apply-to-pmaports.sh | sh
```

> **Why the On7 is missing from `pmbootstrap init`**
>
> Upstream pmaports archived `device-samsung-on7` as unmaintained, so it lives
> in `device/archived/` where pmbootstrap ignores it. The helper moves it back
> into `device/testing/`. It has to be a move:
> pmbootstrap scans every `device/` subfolder and refuses to build a package
> that appears in two of them. It also handles the kernel package having moved
> from `device/community/` to `device/testing/`.
>
> To undo everything, run `git checkout . && git clean -fd` in the pmaports
> checkout.

Then run `init` **again** — `samsung` / `on7` is selectable now:

```
pmbootstrap init
```

| Prompt | Answer |
|---|---|
| Channel | `edge` |
| Vendor | `samsung` |
| Device | `on7` |
| Device is in `testing` | confirm |
| `soc-qcom-msm8916-rproc` provider | `rproc-all` for WiFi/BT/modem |
| User interface | `console` first — see below |
| Username, passwords | whatever you like |

Pick **`console`** for the first install. If the display works you will see a
login prompt, which is an unambiguous answer. A full desktop adds a second thing
that can fail and muddies the diagnosis; you can switch later with
`pmbootstrap init` and reinstall.

Then build. The kernel cross-compiles under emulation, so expect 20-60 minutes
on the first run; later builds are cached:

```
pmbootstrap install
```

## 2b. Flash

Boot the phone into lk2nd's fastboot — hold **Volume Down** while powering on —
and check the computer sees it:

```console
$ fastboot devices
```

Then:

```console
$ pmbootstrap flasher flash_kernel
$ pmbootstrap flasher flash_rootfs
```

Reboot. With `console` selected you should get a login prompt on the screen. If
the screen stays black, SSH in over USB (`ssh user@172.16.42.1`) and jump to
[If the panel stays dark](#if-the-panel-stays-dark).

## 3. Update lk2nd

**Skip this if step 1 reported the Samsung S6D7AA0X62** — that is already the
default, and lk2nd would only confirm it.

Do it if step 1 reported the ILI9881C, or if you want the boot to pick the panel
up automatically rather than relying on the default.

```console
$ git clone https://github.com/msm8916-mainline/lk2nd.git
$ cd lk2nd
$ git am /path/to/this/repo/lk2nd/patches/*.patch
$ make TOOLCHAIN_PREFIX=arm-none-eabi- lk2nd-msm8916
$ fastboot flash boot build-lk2nd-msm8916/lk2nd.img
```

If you would rather not rebuild lk2nd and step 1 reported the **ILI9881C**, edit
the panel compatible in
`kernel/patches/1004-arm64-dts-qcom-msm8916-samsung-on7-Add-display-and-t.patch`
instead, changing:

```dts
compatible = "samsung,s6d7aa0x62-bv050hdm", "samsung,on7-panel";
```

to:

```dts
compatible = "samsung,ili9881c-ski550002", "samsung,on7-panel";
```

and rebuild from step 2.

## Checking it worked

Over SSH or serial:

```console
$ dmesg | grep -iE 'panel|msm_dsi|mdss|lm3632|backlight'
$ ls /sys/class/backlight/          # expect lm3632-backlight
$ cat /sys/class/drm/*/status       # expect "connected" on the DSI connector
```

Brightness:

```console
$ echo 1200 > /sys/class/backlight/lm3632-backlight/brightness
```

## If the panel stays dark

Work through these in order.

**Is the right panel driver bound?**

```console
$ dmesg | grep -i panel
$ cat /proc/device-tree/soc*/mdss*/mdsi*/panel*/compatible | tr '\0' '\n'
```

If the bound compatible does not match what `fastboot getvar lk2nd:panel`
reported, lk2nd did not patch the device tree — redo step 3.

**Is the backlight on but the panel black (or vice versa)?** That splits the
problem cleanly:

- Backlight on, no image → DSI/panel init problem. Check `dmesg` for
  `mipi_dsi` write failures.
- Image faintly visible under bright light, no backlight → LM3632 problem, see
  below.

**The one deliberate deviation from the vendor driver.** The vendor kernel
writes `0x41` to the LM3632 IO_CTRL register (0x09), which puts the chip in
**PWM** brightness mode. `ti-lmu-backlight` clears that bit and uses I2C
brightness instead, because the PWM input is not wired on every board and
leaving it in PWM mode there would keep the backlight dark.

If your unit turns out to need PWM mode, in
`drivers/video/backlight/ti-lmu-backlight.c` change:

```c
	ret = regmap_update_bits(lmu_bl->regmap, LM3632_REG_IO_CTRL,
				 LM3632_PWM_MASK, LM3632_I2C_MODE);
```

to `LM3632_PWM_MODE`, and rebuild. You can test it live first without
rebuilding anything:

```console
$ i2cset -y -f <bus> 0x11 0x09 0x41   # vendor value, PWM mode
```

Find the bus with `i2cdetect -l` — it is the `i2c-gpio` one.

**Still nothing?** Grab the full boot log over the serial console (the headphone
jack UART, 115200 baud — `deviceinfo_getty` is already set to `ttyMSM0`) and
include it in an issue along with the `lk2nd:panel` string and the board
revision from `fastboot getvar all`.

## Building the kernel on its own

To check that the patches build without going through pmbootstrap:

```console
$ ./scripts/build-kernel.sh
```

Needs `gcc-aarch64-linux-gnu`, `make`, `device-tree-compiler`, `git` and the
usual kernel build dependencies (`libssl-dev bc flex bison libelf-dev`). This
produces a kernel image and DTB but does not package or flash anything.
