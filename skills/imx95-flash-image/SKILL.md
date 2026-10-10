---
name: imx95-flash-image
version: "1.0"
platform: imx95
phase: deploy
invoke_when:
  - "flash the board"
  - "program eMMC"
  - "uuu"
  - "write the image"
  - "flash eMMC"
  - "flash SD"
  - "program the board"
requires_host_tools:
  - uuu
safe: false
destructive: true
commit_gate: false
---

# imx95-flash-image

## Purpose

Flash staged artifacts to the FRDM-IMX95 EVK (or custom board) using `uuu` (Universal
Update Utility). Includes pre-flight hardware checks, recovery mode verification, and a
**mandatory "flash confirmed" gate** before any write operation.

## When to Invoke

- After `imx95-promote-image`
- User says "flash the board", "program eMMC", "uuu", "write the image"

## CRITICAL SAFETY RULES

1. **NEVER run `uuu` without the exact string "flash confirmed" from the user.**
2. **ALWAYS verify `uuu --version` ≥ 1.5.21 before flashing.**
3. **ALWAYS verify the board is detected at VID:PID 1fc9:0146 before flashing.**
4. Flash tool is `uuu` — there is NO `flash.sh` for i.MX 95.

## Flash Tool: uuu (Universal Update Utility)

`uuu` communicates with the i.MX 95 ROM via USB Serial Download Protocol (SDP) when the
board is in recovery mode. It does NOT require JTAG.

- Minimum version: **1.5.21**
- Recovery mode USB VID:PID: **1fc9:0146**
- Download: https://github.com/nxp-imx/mfgtools/releases

## Recovery Mode Instructions (FRDM-IMX95 EVK)

```
1. Power OFF the board.
2. Set SW1 DIP switches to USB boot (recovery):
     SW1[1]=OFF  SW1[2]=OFF  SW1[3]=OFF  SW1[4]=OFF
3. Connect USB-C cable from host to J301 (USB OTG port).
4. Power ON the board.
5. Verify: uuu -lsusb  →  should show "SDP: 1fc9:0146"
6. After flashing, set SW1 back to eMMC boot:
     SW1[1]=ON  SW1[2]=OFF  SW1[3]=OFF  SW1[4]=OFF
```

## Pre-conditions

1. `targets/active_target.yaml` exists.
2. `staging/latest/` exists with artifacts and `manifest.txt`.
3. `uuu` ≥ 1.5.21 is installed and on PATH.
4. Board is in USB Serial Download (recovery) mode.
5. `lsusb` shows device at VID:PID `1fc9:0146`.

## Procedure

### Step 1 — Run pre-flight checks

```bash
bash skills/imx95-flash-image/scripts/preflight_flash.sh
```

All checks must pass before proceeding.

### Step 2 — Display flash confirmation prompt

**MANDATORY.** Display exactly this prompt to the user:

```
⚠️  FLASH CONFIRMATION REQUIRED
════════════════════════════════════════════════════════════════
Target board : <board_name>
Boot device  : <emmc|sd>
uuu script   : <path or built-in>
Artifacts    :
  Boot image : <filename>  (<sha256 first 16 chars>...)
  WIC image  : <filename>  (<sha256 first 16 chars>...)

This will ERASE and REPROGRAM the board's <emmc|sd>.
There is NO undo. Ensure the correct board is connected.

Type "flash confirmed" to proceed, or anything else to cancel.
════════════════════════════════════════════════════════════════
```

**WAIT** for the user to type exactly **"flash confirmed"**.
Any other response → cancel and do NOT run uuu.

### Step 3 — Run flash

```bash
bash skills/imx95-flash-image/scripts/flash.sh
```

### Step 4 — Post-flash instructions

After successful flash, instruct the user to:
1. Power off the board.
2. Set SW1 back to eMMC boot: SW1[1]=ON, rest OFF.
3. Disconnect and reconnect power.
4. Run `imx95-validate-image` to verify the board boots correctly.

## Flash Commands Reference

### eMMC flash (FRDM-IMX95 default)

```bash
uuu -b emmc_all \
    staging/latest/imx-boot-<machine>.bin \
    staging/latest/<image_recipe>-<machine>.rootfs.wic.zst
```

### SD card flash

```bash
uuu -b sd_all \
    staging/latest/imx-boot-<machine>.bin \
    staging/latest/<image_recipe>-<machine>.rootfs.wic.zst
```

### Using a custom uuu script

```bash
uuu <path-to-custom.uuu>
```

## Files Touched

- None on host (read-only: staging artifacts)
- Board eMMC/SD is erased and reprogrammed

## Safety Rules Applied

- **R1** — Mandatory "flash confirmed" gate before any uuu execution
- **R10** — uuu version ≥ 1.5.21 verified before flashing

## References

- `references/bsp-platforms-catalogue.md` — board recovery jumper settings
- `context/bsp-customization-workflow.md` — workflow context
