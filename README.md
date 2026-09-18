# OPPO R9s (msm8953) mainline bring-up

Goal: run a current mainline-based kernel (baseline here: the
[`msm8953-mainline`](https://github.com/msm8953-mainline/linux) tree, tag
`v7.1.3-r0`) on the OPPO R9s, which ships on a 4.9 CAF kernel.

**This is a bring-up project. Nothing here has been run on hardware yet.**
Every claim below is labelled by how it was established:

| marker | meaning |
|---|---|
| `[vendor]` | read out of the downstream 4.9 tree in [`XuexGao/android_kernel_oppo_msm8937`](https://github.com/XuexGao/android_kernel_oppo_msm8937), `arch/arm64/boot/dts/qcom/oppo-msm8953/**` — authoritative for this board |
| `[upstream]` | verified against `torvalds/linux` source/bindings |
| `FIXME(unverified)` | reasoned guess, must be confirmed on the device or from the schematic |

## What the board actually is (16017 / 16027)

- SoC `msm8953` (Snapdragon 625), PMIC `pm8953` + `pmi8950` `[vendor]`
- Display: Samsung **EA8064** AMOLED, 1080x1920, **CMD mode**, 4 lanes,
  DCS backlight, reset/enable on **GPIO 41** `[vendor]`
- Touch: Synaptics **S3508 / s1302** on BLSP1 QUP3 (`i2c_3`), addr `0x20`,
  attn IRQ **17**, reset **16**, IO rail `pm8953_l6` (1.8 V) `[vendor]`
- eMMC: core `pm8953_l8` = 2.9 V, I/O `pm8953_l5` = 1.8 V `[vendor]`
- microSD: VMMC `pm8953_l11` = 2.95 V, CD on GPIO 131 `[vendor]`
- Notification/charge-pump LED driver `ktd,ktd2026` @0x30 on `i2c_3` `[vendor]`
- Audio amp `nxp,tfa98xx` @0x36 on `i2c_8`, reset GPIO 33 `[vendor]`
- Keys: volume up/down on GPIO 34 / 39 `[vendor]`

## Blockers

1. **Display PMIC gap - resolved upstream at v7.1.3-r0.**
   The panel is AMOLED and its AVDD/VNEG come from the PMI8950 **LAB/IBB**
   boosters. Older mainline `qcom-labibb-regulator.c` matched only
   `qcom,pmi8998-lab-ibb`. Since tag **v7.1.3-r0**, `pmi8950.dtsi` ships its own
   `labibb` node (`compatible = "qcom,pmi8950-lab-ibb", "qcom,pmi8998-lab-ibb"`,
   register bases `0xdc00`/`0xde00` — the same the pmi8998 driver already
   handles) `[upstream]`, so the panel can now be fed from `&lab`/`&ibb`.
   Consequently the R9s panel node and `mdss_dsi0` are enabled; the panel gets
   `vci-supply` + `avdd-supply`. **Still FIXME(unverified)** on hardware: the
   panel driver currently drives avdd+vci only and does not yet export VNEG
   (ibb) as a separate rail, so the first boot is a probe, not a claim of a
   lit panel.
2. **No usable debug UART is known on this board**, so first-boot evidence has
   to come from elsewhere: `ramoops`/pstore (declared, matching the reference
   boards' reservation) and USB gadget/adb.

## Milestones

1. **M1 - does it run.** Build `Image.gz` + `msm8953-oppo-r9s.dtb`, flash through
   the existing TWRP/AnyKernel3 path, then confirm from pstore
   (`/sys/fs/pstore/console-ramoops-0` after a reboot) that the kernel got to
   userspace, eMMC mounted, and touch probed.
2. **M2 - input/usb/storage usable.** Touch (RMI4), USB adb, battery
   (`bq27541` -> mainline `bq27xxx_battery_i2c`, still to be added).
3. **M3 - display.** The pmi8950 LAB/IBB entry already exists upstream since
   v7.1.3-r0 (see Blocker 1 above), so the panel node and `mdss_dsi0` are now
   enabled. What remains is on-hardware confirmation of the panel probe and the
   VNEG (ibb) rail that `panel-oppo-ea8064.c` does not yet drive.
4. **M4 - audio / modem / sensors.**

Android as a target is out of scope: mainline drops the vendor HAL interface
this device's userspace needs (`ion`, the camera stack, qcom audio machines), so
the realistic OS here is postmarketOS/Debian-style mobile Linux, not an A16/A17
GSI.

## Layout

```
overlay/arch/arm64/boot/dts/qcom/msm8953-oppo-r9s.dts
                                             board description (paths mirror the kernel tree)
overlay/drivers/gpu/drm/panel/panel-oppo-ea8064.c
                                             panel driver, init stream transcribed
                                             from the vendor dtsi (byte-identical)
configs/r9s.fragment                         config fragment merged over defconfig
scripts/apply-overlay.sh                     copies the above into a kernel tree
.github/workflows/build.yml                  CI build + packaging (no local compiles)
```

Overlay + append instead of `.patch` files, so re-basing onto a newer upstream
tag cannot conflict with us.

## Building

Everything is built in GitHub Actions (no kernel builds on the phone):

`Actions → Build R9s mainline kernel → Run workflow`, with

- `kernel_repo`: `msm8953-mainline/linux`
- `kernel_ref`: `v7.1.3-r0` (or a branch such as `7.1/main`)
- `publish_release`: off for experiments

Artifacts: `r9s-mainline-<ref>-<date>.zip` (AnyKernel3, `Image.gz` + board dtb
appended) and `build.log`.

## Flashing / recovery

The device currently runs a custom 4.9 kernel via AnyKernel3 from TWRP, which
means the boot chain is already unlocked and reversible:

1. In TWRP, **back up the current boot image** (this is the only rollback path).
2. Flash `r9s-mainline-*.zip`.
3. If nothing appears: reboot to TWRP, restore the boot backup, and read
   `/sys/fs/pstore/console-ramoops-0` from the running LOS system after the next
   successful boot - pstore keeps the previous attempt's log.
4. Do not flash a mainline boot image as your only copy of anything.
