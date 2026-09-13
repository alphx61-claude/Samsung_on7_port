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

> **Do not run `pmbootstrap flasher flash_kernel` on this device.** It will
> fail, and it is not needed. See below.

Boot the phone into lk2nd's fastboot — hold **Volume Down** while powering on —
and check the computer sees it:

```
fastboot devices
```

Then flash only the root filesystem:

```
pmbootstrap flasher flash_rootfs
```

That takes 10-20 minutes over USB 2.0 and looks frozen while it runs.

### Why there is no flash_kernel step

The On7's boot partition is far too small for a modern postmarketOS boot image:

```
fastboot getvar partition-size:boot
partition-size:boot:     0xc80000          # 12.5 MB
```

against a `boot.img` of about 23.6 MB (9.3 MB kernel + 14.3 MB initramfs), of
which lk2nd already occupies the first 512 KiB. It cannot fit, and trimming
will not close a gap that size.

That is exactly why `deviceinfo` sets `deviceinfo_generate_extlinux_config` and
`deviceinfo_partition_type="msdos"`. lk2nd scans leaf partitions of at least
16 MiB, mounts them as ext2 and boots `/extlinux/extlinux.conf` if it finds one
(`lk2nd/boot/boot.c`). It parses the nested partition table inside the flashed
image too (`lk2nd_wrapper_publish_subdevices()`), so the boot partition *inside*
the rootfs image is visible to it — and that one has room to spare.

So the kernel, device tree and initramfs all come from the rootfs image via
extlinux. The 12.5 MB `boot` partition only ever holds lk2nd itself.

A consequence worth remembering: **anything that changes the kernel command
line, the kernel, or the initramfs needs `flash_rootfs`**, not `flash_kernel`,
because `extlinux.conf` and the files it points at live in the rootfs image.

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

## If it boots but you cannot ssh in

The phone answers `ping 172.16.42.1` from very early in the initramfs, long
before it has finished booting, so **ping succeeding proves almost nothing**.
`init_2nd.sh` sets that address up in its first few lines:

```
setup_usb_network ; start_unudhcpd     <- 172.16.42.1 is live from here
setup_framebuffer ; splash_start
if debug_shell = y -> debug_shell      <- off unless you ask for it
mount_subpartitions
wait_root_partition                    <- 30s, then falls into a debug shell
mount_root_partition ... switch_root
```

Two traps follow from that:

- **Check the host interface actually exists.** With the phone unplugged,
  `172.16.42.1` routes out of your default gateway and some unrelated machine
  on your LAN may answer. That looks exactly like success. Confirm with
  `ip route get 172.16.42.1` — it must leave via a `usb0`/`enx…` device, not
  your ethernet.
- **The host side gets no address on its own.** `unudhcpd` on the phone offers
  you `172.16.42.2`, but nothing requests it unless your network manager picks
  the interface up. Set it by hand:

```
IF=$(ls /sys/class/net | grep -E '^(usb|enx)' | head -1)
sudo ip link set "$IF" up
sudo ip addr add 172.16.42.2/24 dev "$IF"
```

With a real link up, probe both ports:

```
nc -vz 172.16.42.1 22    # sshd, so the real system booted
nc -vz 172.16.42.1 23    # telnetd, so it fell into the initramfs debug shell
```

If neither answers about a minute after power-on, nothing is listening — the
initramfs handed over but userspace did not get far. Ask for the debug shell
explicitly:

```
./scripts/enable-debug-shell.sh
pmbootstrap install
pmbootstrap flasher flash_rootfs      # extlinux.conf lives in the rootfs
```

That adds `pmos.debug-shell` to the kernel command line, which stops the
initramfs right after the splash — before it looks for any partition — and
gives you three ways in at once: telnet on port 23, a USB ACM gadget
(`/dev/ttyACM0` on the host, so a serial console with **no 3.5mm UART cable**),
and kernel console output left enabled instead of silenced.

At that shell, `cat /README` explains the environment and `pmos_continue_boot`
resumes the boot so you can watch where it fails. Turn it back off afterwards
with `./scripts/enable-debug-shell.sh --disable`.

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
