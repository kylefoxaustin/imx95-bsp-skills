# BSP Platforms Catalogue — i.MX 95 Board Variants

> # 🔴 ALMOST EVERYTHING IN THIS FILE IS [UNVERIFIED]
>
> This document was written by an agent with **no board and no BSP checkout**. It is retained
> because its *shape* is useful — these are the fields a target profile needs — but **the values
> are not evidence.** A `MACHINE` name that is wrong fails with a cryptic bitbake error, which is
> the *good* outcome; the bad one is a name that exists and builds a **different board**.
>
> **Confirmed against the running board** (`references/imx95-ground-truth.md`):
>
> | field | value | tag |
> |---|---|:--|
> | DT `model` | **NXP FRDM-IMX95-PRO** | [MEASURED] |
> | DT `compatible` | **`fsl,frdm-imx95-pro fsl,imx95`** | [MEASURED] |
> | live DTB basename | **`imx95-19x19-frdm-pro-neutron.dtb`** | [MEASURED] |
> | RAM | 16 GB LPDDR | [SOURCED] |
> | eMMC `mmcblk0` | **29.6 GB** — confirmed on the board; holds a **non-live** rootfs at p2 | [MEASURED] |
> | microSD `mmcblk1` | **58 GB** — 🔴 **this is what the board actually boots and runs from** (`/` = `mmcblk1p2`) | [MEASURED] |
> | Yocto `MACHINE` | 🔴 **[UNKNOWN]** | — |
>
> **On the MACHINE name specifically:** the value below (`imx95-19x19-lpddr5-evk`) has **1**
> supporting reference across the fleet's i.MX95 repos. `imx95-19x19-frdm-pro` has **68**;
> `imx95-15x15-evk` has 45. The *DTB basename* is measured; the *Yocto MACHINE that produces it*
> is a different string nobody has established. **`imx95-init-target` must ASK.**

---

## Supported Boards

### 1. NXP FRDM-IMX95-PRO (Primary Target)

**DT model (measured):** `NXP FRDM-IMX95-PRO`
**Memory:** 16 GB LPDDR [SOURCED] — *an earlier version of this file said "LPDDR5, 8 GB"*
**Storage [MEASURED 2026-10-08]:** 🔴 **this board boots and runs from the microSD card, not the
eMMC** — a BSP-relevant fact that changes every flashing and imaging instruction.

    mmcblk0   29.6 G  eMMC      p1 256 M vfat -> /run/media/boot-mmcblk0p1
                                p2 10.6 G ext4 -> /run/media/root-mmcblk0p2   (NON-LIVE rootfs)
    mmcblk0boot0/1  31.5 M each (eMMC boot partitions)
    mmcblk1     58 G  microSD   p1 256 M vfat -> /run/media/boot-mmcblk1p1
                                p2 57.7 G ext4 -> /                           (THE LIVE ROOTFS)

So there are **two ext4 roots and two vfat boot partitions mounted at once**. `df` labels `/` as
`/dev/root`, a kernel-supplied name that is *not* a symlink — `readlink -f` returns itself, so use
`findmnt -no SOURCE /`. The microSD slot is therefore **[MEASURED] present and in use**, not
[UNVERIFIED]. Sequential throughput **298 MB/s read / 152 MB/s write** [MEASURED].
⚠️ **Two boot partitions is the likely explanation for `.ORIG` DTB backups being reported "in two
places"** — confirm which the bootloader reads before trusting either. See ground-truth §5.
**Display / Camera / USB / PCIe / Ethernet / Debug:** all **[UNVERIFIED]** below — connector
designators, lane counts and baud rates were written from inference, not from the board.

| Field | Value | tag |
|---|---|:--|
| **MACHINE** | `imx95-19x19-lpddr5-evk` | 🔴 **[UNKNOWN] — ASK, do not default** |
| **Alternate MACHINE** | `imx95frdm` | [UNVERIFIED] |
| **Default image recipe** | `imx-image-full` | [UNVERIFIED] |
| **Default DISTRO** | `fsl-imx-xwayland` | [UNVERIFIED] |
| **Base DTS** | `imx95-19x19-lpddr5-evk.dts` | [UNVERIFIED] — live DTB is `imx95-19x19-frdm-pro[-neutron]` |
| **uuu script (eMMC / SD)** | `frdm-imx95-emmc.uuu` / `-sd.uuu` | [UNVERIFIED] — **and these files do not exist in this repo** |
| **USB VID:PID (recovery)** | `1fc9:0146` | [UNVERIFIED] — read it from `uuu -lsusb` on your board |
| **Recovery connector** | J301 (USB-C OTG) | [UNVERIFIED] |
| **Debug UART** | J1003 (micro-USB), `/dev/ttyUSB0`, 115200 8N1 |

**Recovery Mode Jumper Settings (SW1 DIP switch):**

| Mode | SW1[1] | SW1[2] | SW1[3] | SW1[4] | Description |
|---|---|---|---|---|---|
| eMMC boot (normal) | ON | OFF | OFF | OFF | Normal operation after flashing |
| USB Serial Download | OFF | OFF | OFF | OFF | Recovery/flash mode |
| SD card boot | OFF | ON | OFF | OFF | Boot from microSD |

**Recovery procedure:**
1. Power off board
2. Set SW1: [1]=OFF [2]=OFF [3]=OFF [4]=OFF
3. Connect USB-C cable from host to J301
4. Power on board
5. Verify: `uuu -lsusb` shows `SDP: 1fc9:0146`
6. After flashing: set SW1 [1]=ON [2]=OFF [3]=OFF [4]=OFF, power cycle

**Known DT files in kernel source:**
```
arch/arm64/boot/dts/freescale/
├── imx95-19x19-lpddr5-evk.dts        ← Main EVK DTS
├── imx95-19x19-lpddr5-evk.dtsi       ← EVK DTSI (included by main)
├── imx95frdm.dts                      ← FRDM-specific DTS
├── imx95.dtsi                         ← SoC-level DTSI
└── imx95-clock-init.dtsi              ← Clock initialization DTSI
```

---

### 2. i.MX 95 19×19 LPDDR5 EVK

**Full name:** NXP i.MX 95 19×19 mm LPDDR5 Evaluation Kit  
**Form factor:** Standalone EVK (no SOM)  
**Memory:** LPDDR5, 8 GB  
**Storage:** eMMC 32 GB, microSD  
**Note:** This is the same MACHINE as FRDM-IMX95 (`imx95-19x19-lpddr5-evk`). The FRDM board
uses the same SOM and the same BSP machine configuration.

| Field | Value |
|---|---|
| **MACHINE** | `imx95-19x19-lpddr5-evk` |
| **Default image recipe** | `imx-image-full` |
| **Default DISTRO** | `fsl-imx-xwayland` |
| **Base DTS** | `imx95-19x19-lpddr5-evk.dts` |
| **uuu script (eMMC)** | `frdm-imx95-emmc.uuu` |
| **USB VID:PID (recovery)** | `1fc9:0146` |
| **Recovery connector** | J301 (USB-C OTG) |

---

### 3. i.MX 95 15×15 EVK

**Full name:** NXP i.MX 95 15×15 mm Evaluation Kit  
**Form factor:** Standalone EVK, smaller package variant  
**Memory:** LPDDR5, 4 GB  
**Storage:** eMMC 16 GB, microSD  
**Note:** Uses a different SoC package (15×15 mm vs 19×19 mm). Different machine config
and DTS from the 19×19 EVK.

| Field | Value |
|---|---|
| **MACHINE** | `imx95-15x15-evk` |
| **Default image recipe** | `imx-image-full` |
| **Default DISTRO** | `fsl-imx-xwayland` |
| **Base DTS** | `imx95-15x15-evk.dts` |
| **uuu script (eMMC)** | `imx95-15x15-evk-emmc.uuu` |
| **USB VID:PID (recovery)** | `1fc9:0146` |
| **Recovery connector** | J301 (USB-C OTG) |

**Recovery Mode Jumper Settings:**

| Mode | SW1[1] | SW1[2] | SW1[3] | SW1[4] |
|---|---|---|---|---|
| eMMC boot (normal) | ON | OFF | OFF | OFF |
| USB Serial Download | OFF | OFF | OFF | OFF |
| SD card boot | OFF | ON | OFF | OFF |

**Known DT files:**
```
arch/arm64/boot/dts/freescale/
├── imx95-15x15-evk.dts        ← Main 15x15 EVK DTS
└── imx95-15x15-evk.dtsi       ← 15x15 EVK DTSI
```

---

## MACHINE Name Quick Reference

| MACHINE | Board | Package | RAM | Notes |
|---|---|---|---|---|
| `imx95-19x19-lpddr5-evk` | FRDM-IMX95 / 19×19 EVK | 19×19 mm | 8 GB LPDDR5 | Primary target |
| `imx95frdm` | FRDM-IMX95 | 19×19 mm | 8 GB LPDDR5 | Alternate name for FRDM |
| `imx95-15x15-evk` | 15×15 EVK | 15×15 mm | 4 GB LPDDR5 | Smaller package |

**Important:** The MACHINE value in `build/conf/local.conf` must exactly match one of these
strings. A typo causes bitbake to fail with "no such machine" error.

---

## Image Recipe Quick Reference

| Recipe | Size | GUI | VPU | NPU | Typical use |
|---|---|---|---|---|---|
| `core-image-base` | ~500 MB | No | No | No | Bring-up, CI, minimal |
| `imx-image-multimedia` | ~1.5 GB | No | Yes | No | Media applications |
| `imx-image-full` | ~2.5 GB | Weston/Wayland | Yes | Yes | Default FRDM demo |

---

## Adding a Custom Board

To add a custom carrier board based on the FRDM-IMX95 SOM:

1. Use `imx95-init-target` to create a new target profile with `custom_carrier: true`
2. Use `imx95-derive-carrier` to fork the FRDM-IMX95 DTS into a custom overlay
3. The MACHINE value remains `imx95-19x19-lpddr5-evk` (same SOM)
4. The custom carrier is differentiated by the DT overlay, not the MACHINE name

For a fully custom board (different SOM or SoC package):
- Create a new machine config in `meta-imx95-custom/conf/machine/`
- Base it on the closest NXP machine config
- Set `MACHINE` in the target profile to your new machine name

---

## uuu Script Reference

| Script | Board | Boot device | Description |
|---|---|---|---|
| `frdm-imx95-emmc.uuu` | FRDM-IMX95 / 19×19 EVK | eMMC | Flash full image to eMMC |
| `frdm-imx95-sd.uuu` | FRDM-IMX95 / 19×19 EVK | SD | Flash full image to SD card |

uuu scripts are located in `references/uuu-scripts/` within the skill bundle, and are
copied to `<workspace>/.imx95-skills/references/uuu-scripts/` by `setup.sh`.

---

## Serial Console Reference

| Board | Connector | Device | Baud | Format |
|---|---|---|---|---|
| FRDM-IMX95 | J1003 (micro-USB) | `/dev/ttyUSB0` | 115200 | 8N1 |
| i.MX95-19x19-EVK | J1003 (micro-USB) | `/dev/ttyUSB0` | 115200 | 8N1 |
| i.MX95-15x15-EVK | J1003 (micro-USB) | `/dev/ttyUSB0` | 115200 | 8N1 |

```bash
# Connect to serial console:
screen /dev/ttyUSB0 115200
# or
minicom -D /dev/ttyUSB0 -b 115200
# or
picocom -b 115200 /dev/ttyUSB0
```

If `/dev/ttyUSB0` is not present, check:
```bash
ls /dev/ttyUSB*
dmesg | grep ttyUSB
# Add user to dialout group if permission denied:
sudo usermod -aG dialout $USER
```
