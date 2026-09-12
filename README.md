# postmarketOS display support for the Samsung Galaxy On7 (2015)

Fixes the blank screen on the `samsung-on7` postmarketOS port — the one where
the device boots far enough for SSH to work, but the panel never lights up.

Target device: **SM-G600FY** (Galaxy On7 Pro, India/SWA).
Also applies to SM-G600F and SM-G6000, which use the same board and panels.

| | |
|---|---|
| SoC | Qualcomm MSM8916 (Snapdragon 410), 4x Cortex-A53, Adreno 306 |
| Vendor codename | `o7lte` (`o7lte-swa` for SM-G600FY, `o7lte-chn` for SM-G6000) |
| pmOS device package | `device-samsung-on7` |
| Kernel | `linux-postmarketos-qcom-msm8916` — msm8916-mainline, tag `v6.12.1-msm8916` |
| Panel | 5.5" 720x1280 DSI video mode, **dual-sourced** (see below) |
| Backlight / panel bias | TI LM3632 on a bit-banged I2C bus |

## Why the display never came up

Not a broken driver — a **missing one**, plus a device tree with no display in
it at all.

1. **`msm8916-samsung-on7.dts` had zero display nodes.** No `&mdss`, no
   `&mdss_dsi0`, no panel, no backlight. MDP and DSI were never enabled, so
   nothing ever drove the LCD. Everything else (eMMC, USB, WiFi) was wired up,
   which is exactly why SSH worked and the screen stayed dark.

2. **The panel driver it expected did not exist.** `device-samsung-on7`'s
   `modules-initfs` lists `panel-samsung-s6d7aa0x62-bv050hdm`, but no such
   driver was in the kernel — upstream or in the msm8916-mainline fork. The
   package was written in anticipation of a driver that was never finished.

3. **The backlight chip was unsupported.** The panel's +5.5V/-5.5V bias rails
   *and* the backlight both come from a TI LM3632. `CONFIG_MFD_TI_LMU` was off
   in the pmOS kernel config, and even with it on, `drivers/mfd/ti-lmu.c`
   registers a `ti-lmu-backlight` cell for which **no driver was ever merged**.
   So even a perfect panel driver would have produced a black screen.

4. **The On7 ships one of two different panels**, so a single hardcoded
   compatible cannot work for every unit:

   | Vendor name | Controller | Mainline compatible |
   |---|---|---|
   | `ss_dsi_panel_S6D7AA0X62_BV050HDM_HD` | Samsung S6D7AA0X62 | `samsung,s6d7aa0x62-bv050hdm` |
   | `ss_dsi_panel_ILI9881C_SKI550002_HD` | Ilitek ILI9881C | `samsung,ili9881c-ski550002` |

   Board revision does not affect this. All three SWA revisions (r01/r02/r03)
   use the same reset/enable GPIOs, the same supplies and the same LM3632
   wiring, so only the panel itself varies.

## What is in here

Patches, not a fork. Five commits total.

### `kernel/patches/` — against `v6.12.1-msm8916`

| Patch | What it does |
|---|---|
| `1001` | New DRM panel driver for the Samsung S6D7AA0X62 BV050HDM |
| `1002` | New DRM panel driver for the Ilitek ILI9881C SKI550002 |
| `1003` | New `ti-lmu-backlight` driver for the LM3632 |
| `1004` | Display, backlight and touchscreen nodes in `msm8916-samsung-on7.dts` |

Both panel drivers were generated with
[linux-mdss-dsi-panel-driver-generator][lmdpdg] from the vendor device tree in
the [Galaxy-MSM8916 downstream kernel][downstream], then adapted: they take the
LM3632 bias rails as regulators and pick the backlight up from the device tree.

The device tree additions come straight from the vendor DTS
(`msm8916-sec-o7lte-swa-r03.dtsi`):

- DSI reset on GPIO 25, LCD power gate on GPIO 16
- Panel supplies: `pm8916_l5` (1.8V logic), `pm8916_s4` (2.1V, gated by GPIO 16)
- LM3632 at 0x11 on a bit-banged I2C bus (SCL GPIO 102, SDA GPIO 101),
  HWEN on GPIO 98, ENP on GPIO 97, ENN on GPIO 120
- Zinitix ZT7548 touchscreen at 0x20 on `blsp_i2c5`, IRQ GPIO 13

### `lk2nd/patches/` — panel autodetection

The Samsung bootloader passes the detected panel on the kernel command line as
`mdss_mdp.panel=`. lk2nd already parses this and can rewrite the panel's
`compatible` in the kernel device tree before boot; it just had no mapping for
the On7. The patch adds one for both the SM-G600FY and SM-G6000 entries.

The kernel device tree defaults to the S6D7AA0X62 and carries
`samsung,on7-panel` as a fallback compatible, which is the string lk2nd matches
on. So an up-to-date lk2nd picks the right panel automatically, and an older one
still gets the S6D7AA0X62 default rather than nothing.

Numbered from 1001 so they sort after the `0001-kbuild-*` patch the kernel
package already carries.

### `pmaports/` — drop-in package updates

`linux-postmarketos-qcom-msm8916` with the four patches wired into `source=`
and the new Kconfig symbols merged in `prepare()`, plus `device-samsung-on7`
with the display modules added to `modules-initfs`.

**Upstream pmaports has archived `device-samsung-on7` as unmaintained**, which
is why `pmbootstrap init` does not offer the device at all.
`scripts/apply-to-pmaports.sh` moves it from `device/archived/` into
`device/testing/` before patching. The kernel package also moved from
`device/community/` to `device/testing/`; the script accepts either.

Two packaging details that are easy to get wrong and fail confusingly:

- The kernel `pkgrel` is bumped. Without that, pmbootstrap treats the mirror's
  unpatched binary kernel as current and never rebuilds, so the device tree and
  panel drivers silently never reach the phone.
- `device-samsung-on7-nonfree-firmware` no longer depends on
  `firmware-samsung-on7`, whose WiFi calibration blob came from a pastebin URL.
  A failed fetch there leaves `firmware-samsung-on7-wcnss-nv` unbuilt and the
  whole install dies at `apk ... unable to select packages`. It now uses
  `msm-firmware-loader-wcnss`, which reads that data off the phone's own stock
  firmware partition.

Note that pmbootstrap clones pmaports from `gitlab.postmarketos.org`, not the
older `gitlab.com` mirror.

## Build status

A full arm64 `Image.gz + modules + dtbs` build of `v6.12.1-msm8916` with these
patches and the stock postmarketOS msm8916 config succeeds, built with `LLVM=1`
the way the pmaports package builds it. The three new drivers compile
warning-free, `msm8916-samsung-on7.dtb` builds clean, and all four patches
apply to a pristine tree with `patch -p1` alongside the `0001-kbuild-*` patch
the package already carries. The module aliases match the compatibles in the device tree:

```
panel-samsung-s6d7aa0x62-bv050hdm.ko   of:N*T*Csamsung,s6d7aa0x62-bv050hdm
panel-samsung-ili9881c-ski550002.ko    of:N*T*Csamsung,ili9881c-ski550002
ti-lmu-backlight.ko                    of:N*T*Cti,lm3632-backlight
```

The patched lk2nd device tree compiles too.

One data point from real hardware: on an SM-G600FY running LineageOS 16.0
(bootloader `G600FYXXU1BRD2`), the downstream kernel reports
`panel_name=ss_dsi_panel_S6D7AA0X62_BV050HDM_HD` — the Samsung panel, which is
what the device tree here defaults to.

**The display itself has not been tested on real hardware** — there is no On7
attached to the machine this was built on. The register sequences, GPIOs, supplies and
timings are transcribed from the vendor kernel, but the LM3632 configuration in
particular involved one deliberate deviation, documented in
[`docs/INSTALL.md`](docs/INSTALL.md#if-the-panel-stays-dark), along with what to
check first if the screen is still dark.

## Install

See [`docs/INSTALL.md`](docs/INSTALL.md).

Before flashing, run the panel check in
[`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md) from your current Android install.
The stock/LineageOS kernel reports which of the two panels your unit actually
has; the mainline kernel cannot work it out on its own.

[lmdpdg]: https://github.com/msm8916-mainline/linux-mdss-dsi-panel-driver-generator
[downstream]: https://github.com/Galaxy-MSM8916/android_kernel_samsung_msm8916
