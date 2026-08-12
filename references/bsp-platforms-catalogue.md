# BSP Platforms Catalogue — Supported i.MX 95 Board Variants

> **Reference document.** Lists all supported i.MX 95 board variants with their MACHINE names,
> uuu script names, default image recipes, known DT files, and recovery mode settings.

---

## Supported Boards

### 1. NXP FRDM-IMX95 EVK (Primary Target)

**Full name:** NXP Freedom Development Board for i.MX 95  
**Form factor:** 19×19 mm SOM on FRDM carrier board  
**Memory:** LPDDR5, 8 GB  
**Storage:** eMMC 32 GB (primary), microSD slot  
**Display:** MIPI-DSI connector  
**Camera:** MIPI-CSI connector (2-lane)  
**USB:** USB3.0 OTG (USB-C, J301), USB2.0 Host (USB-A)  
**PCIe:** M.2 Key-E slot (PCIe Gen3 x1)  
**Ethernet:** 1 GbE (ENET1)  
**Debug:** USB-UART via J1003 (micro-USB), 115200 8N1  

| Field | Value |
|---|---|
| **MACHINE** | `imx95-19x19-lpddr5-evk` |
| **Alternate MACHINE** | `imx95frdm` |
| **Default image recipe** | `imx-image-full` |
| **Default DISTRO** | `fsl-imx-xwayland` |
| **Base DTS** | `imx95-19x19-lpddr5-evk.dts` |
| **Alternate DTS** | `imx95frdm.dts` |
| **uuu script (eMMC)** | `frdm-imx95-emmc.uuu` |
| **uuu script (SD)** | `frdm-imx95-sd.uuu` |
| **USB VID:PID (recovery)** | `1fc9:0146` |
| **Recovery connector** | J301 (USB-C OTG) |
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
