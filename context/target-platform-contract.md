# Target Platform Contract — imx95-bsp-skills

> **Shared context document.** Defines the authoritative schema for target profile YAMLs.
> All skills read this document to understand the target profile format.

---

## Overview

Every board variant used with imx95-bsp-skills is described by a **target profile YAML** file.
The active target profile is always stored at `<workspace>/targets/active_target.yaml`.

**Rules:**
- There is exactly **one active target** at a time.
- All skills read `targets/active_target.yaml` to determine board, MACHINE, paths, and flash config.
- `active_target.yaml` is either a symlink to a named profile or a direct copy.
- Target profiles are created by `imx95-init-target` and switched by `imx95-set-target`.
- Never edit `active_target.yaml` directly — always edit the named profile and re-link.

---

## Schema Version

Current schema version: **1.0**

All target profile YAMLs must include `schema_version: "1.0"` at the top level.

---

## Full Field Reference

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# Target profile for imx95-bsp-skills
# Schema version: 1.0
# Created by: imx95-init-target
# ─────────────────────────────────────────────────────────────────────────────

schema_version: "1.0"
# REQUIRED. Must be "1.0". Skills check this field and refuse to operate on
# unknown schema versions.

# ── Identity ──────────────────────────────────────────────────────────────────

profile_name: "frdm-imx95-base"
# REQUIRED. Short slug used in file paths and git commit messages.
# Rules: lowercase, hyphens only (no spaces, no underscores), max 40 chars.
# Example: "frdm-imx95-base", "acme-carrier-v1", "imx95-evk-sd"

description: "FRDM-IMX95 EVK, eMMC boot, imx-image-full"
# REQUIRED. Human-readable one-line description of this target.
# Used in imx95-print-bsp-info output and git commit messages.

# ── Board ─────────────────────────────────────────────────────────────────────

board:
  name: "FRDM-IMX95"
  # REQUIRED. Human-readable board name. Used in flash confirmation prompt.
  # Examples: "FRDM-IMX95", "i.MX95-19x19-LPDDR5-EVK", "ACME-Carrier-v1"

  variant: "19x19-lpddr5-evk"
  # REQUIRED. Board variant string. Used in artifact path construction.
  # For FRDM: "19x19-lpddr5-evk"
  # For 15x15 EVK: "15x15-evk"
  # For custom: use a descriptive slug

  soc: "imx95"
  # REQUIRED. SoC family. Must be "imx95" for all boards in this bundle.
  # Future: may support "imx93", "imx91" in extended bundles.

  boot_device: "emmc"
  # REQUIRED. Primary boot device.
  # Valid values: "emmc" | "sd" | "flexspi"
  # Determines which uuu script is used by default.

  custom_carrier: false
  # REQUIRED. Boolean.
  # false = using a stock NXP EVK or FRDM board with no carrier customization
  # true  = using a custom carrier board (imx95-derive-carrier has been run)
  # When true, custom_carrier section below must be populated.

# ── Yocto Build ───────────────────────────────────────────────────────────────

yocto:
  machine: "imx95-19x19-lpddr5-evk"
  # REQUIRED. Exact MACHINE= value for bitbake.
  # This string must exactly match a .conf file in the BSP's machine/ directory.
  # Valid values for i.MX 95:
  #   "imx95-19x19-lpddr5-evk"   ← i.MX 95 19×19 EVK (also used for FRDM-IMX95)
  #   "imx95frdm"                 ← FRDM-IMX95 Freedom board (alternate machine name)
  #   "imx95-15x15-evk"           ← i.MX 95 15×15 EVK
  # See references/bsp-platforms-catalogue.md for the full list.

  image_recipe: "imx-image-full"
  # REQUIRED. bitbake target image recipe.
  # Common values:
  #   "core-image-base"        — minimal console image, no GUI (~500 MB)
  #   "imx-image-multimedia"   — multimedia stack with GStreamer/VPU (~1.5 GB)
  #   "imx-image-full"         — full NXP demo image with Weston/Wayland (~2.5 GB)
  # Custom image recipes in meta-imx95-custom are also valid.

  distro: "fsl-imx-xwayland"
  # REQUIRED. Yocto DISTRO value.
  # Valid values:
  #   "fsl-imx-xwayland"   ← X11 + Wayland (default for FRDM EVK)
  #   "fsl-imx-wayland"    ← Wayland only
  #   "fsl-imx-fb"         ← Framebuffer (no display server)
  # Note: distro must be compatible with image_recipe.
  # imx-image-full requires fsl-imx-xwayland or fsl-imx-wayland.

  bsp_manifest_url: "https://github.com/nxp-imx/imx-manifest"
  # REQUIRED. URL of the imx-manifest repo tool manifest repository.
  # Do not change unless using a fork or mirror.

  bsp_manifest_branch: "imx-linux-scarthgap"
  # REQUIRED. Branch in the manifest repo to use.
  # "imx-linux-scarthgap" = Yocto Scarthgap (5.0 LTS) release branch.
  # Other branches: "imx-linux-kirkstone" (older LTS), "imx-linux-nanbield"

  bsp_manifest_file: "imx-6.6.52-2.2.0.xml"
  # REQUIRED. Specific manifest XML file within the branch.
  # This pins the exact BSP release. Use the latest stable release.
  # Format: imx-<kernel_version>-<bsp_version>.xml
  # Check https://github.com/nxp-imx/imx-manifest/tree/imx-linux-scarthgap
  # for available manifest files.

# ── Paths ─────────────────────────────────────────────────────────────────────

paths:
  workspace_root: "~/imx95-workspace"
  # REQUIRED. Absolute path (or ~ path) to the BSP workspace root.
  # This is the directory where .repo/, sources/, build/, overlay-tracker/ live.
  # Must be an absolute path or start with ~/

  bsp_sources: "sources"
  # REQUIRED. Path to BSP source layers, relative to workspace_root.
  # Standard value: "sources"
  # After repo sync, this contains meta-imx/, meta-freescale/, poky/, etc.

  build_dir: "build"
  # REQUIRED. Path to Yocto build directory, relative to workspace_root.
  # Standard value: "build"
  # Contains conf/local.conf, conf/bblayers.conf, tmp/, sstate-cache/

  custom_layer: "sources/meta-imx95-custom"
  # REQUIRED. Path to the custom Yocto layer, relative to workspace_root.
  # This layer contains all bbappend recipes and DT overlay files.
  # Created by imx95-init-source if it does not exist.

  dt_overlay_dir: "sources/meta-imx95-custom/recipes-kernel/linux/files/overlays"
  # REQUIRED. Path to the DT overlay directory, relative to workspace_root.
  # All .dts overlay files created by customize skills go here.
  # This directory is also tracked by overlay-tracker.

  overlay_tracker: "overlay-tracker"
  # REQUIRED. Path to the overlay-tracker git repository, relative to workspace_root.
  # Initialized by imx95-init-source as an empty git repo.

  deploy_dir: "build/tmp/deploy/images/imx95-19x19-lpddr5-evk"
  # REQUIRED. Path to Yocto deploy directory, relative to workspace_root.
  # Must match: build/tmp/deploy/images/<machine>/
  # Update this field if machine changes.

  staging_dir: "staging"
  # REQUIRED. Path to staging directory for promoted artifacts, relative to workspace_root.
  # Created by imx95-promote-image. Contains artifacts ready for uuu flashing.

# ── Flash / Deploy ────────────────────────────────────────────────────────────

flash:
  tool: "uuu"
  # REQUIRED. Flash tool. MUST be "uuu" for all i.MX 95 boards.
  # There is no flash.sh for i.MX 95. See CLAUDE.md Section 11 (G1).

  uuu_script: "references/uuu-scripts/frdm-imx95-emmc.uuu"
  # REQUIRED. Path to the uuu script, relative to workspace_root or absolute.
  # For FRDM-IMX95 eMMC: "references/uuu-scripts/frdm-imx95-emmc.uuu"
  # For FRDM-IMX95 SD:   "references/uuu-scripts/frdm-imx95-sd.uuu"
  # For custom boards:   point to your own .uuu script

  uuu_version_min: "1.5.21"
  # REQUIRED. Minimum uuu version required for this target.
  # imx95-flash-image checks this before flashing.
  # Do not lower below 1.5.21 — older versions have eMMC programming bugs on i.MX 95.

  recovery_mode_jumper: "J301"
  # REQUIRED. Label of the recovery mode jumper/connector on the board.
  # Used in the flash confirmation prompt to guide the user.
  # FRDM-IMX95: "J301" (USB-C OTG port used for SDP)
  # i.MX95-19x19-EVK: "J301"

  usb_vid_pid: "1fc9:0146"
  # REQUIRED. USB VID:PID of the board in USB Serial Download (recovery) mode.
  # i.MX 95 ROM: "1fc9:0146"
  # imx95-flash-image checks lsusb for this VID:PID before flashing.

# ── Device Tree ───────────────────────────────────────────────────────────────

device_tree:
  base_dts: "imx95-19x19-lpddr5-evk.dts"
  # REQUIRED. Filename of the base DTS in the kernel source tree.
  # Located at: sources/linux-imx/arch/arm64/boot/dts/freescale/<base_dts>
  # For FRDM-IMX95 (19x19): "imx95-19x19-lpddr5-evk.dts"
  # For FRDM-IMX95 (frdm):  "imx95frdm.dts"
  # For 15x15 EVK:           "imx95-15x15-evk.dts"

  overlay_prefix: "imx95-custom"
  # REQUIRED. Prefix used when generating overlay file names.
  # imx95-derive-carrier uses this to name: imx95-<overlay_prefix>-<carrier>.dts
  # For custom carriers, set to a descriptive prefix: "imx95-acme"

  kernel_dt_path: "sources/linux-imx/arch/arm64/boot/dts/freescale/"
  # REQUIRED. Path to kernel DTS directory, relative to workspace_root.
  # Standard value for NXP BSP: "sources/linux-imx/arch/arm64/boot/dts/freescale/"
  # Do not modify files in this directory — use overlays instead.

# ── Custom Carrier (populated by imx95-derive-carrier) ────────────────────────

custom_carrier:
  carrier_name: null
  # OPTIONAL (required if board.custom_carrier = true).
  # Short slug for the custom carrier board.
  # Example: "acme-carrier-v1", "myboard-rev2"
  # Used as the overlay file prefix: imx95-<carrier_name>.dts

  base_overlay: null
  # OPTIONAL (required if board.custom_carrier = true).
  # Filename of the main carrier overlay DTS file.
  # Example: "imx95-acme-carrier-v1.dts"
  # Located in dt_overlay_dir.

  schematic_pdf: null
  # OPTIONAL. Path to the carrier board schematic PDF.
  # Absolute path or relative to workspace_root.
  # Used by customize skills to reference hardware details.
  # Example: "~/Documents/acme-carrier-v1-schematic.pdf"

# ── Notes ─────────────────────────────────────────────────────────────────────

notes: |
  Created by imx95-init-target.
  Modify flash.uuu_script for custom boot media.
  Set custom_carrier: true and run imx95-derive-carrier for custom boards.
  Update paths.deploy_dir if MACHINE changes.
```

---

## Complete Example: FRDM-IMX95 EVK

```yaml
schema_version: "1.0"

profile_name: "frdm-imx95-base"
description: "FRDM-IMX95 EVK, eMMC boot, imx-image-full, Scarthgap 6.6.52"

board:
  name: "FRDM-IMX95"
  variant: "19x19-lpddr5-evk"
  soc: "imx95"
  boot_device: "emmc"
  custom_carrier: false

yocto:
  machine: "imx95-19x19-lpddr5-evk"
  image_recipe: "imx-image-full"
  distro: "fsl-imx-xwayland"
  bsp_manifest_url: "https://github.com/nxp-imx/imx-manifest"
  bsp_manifest_branch: "imx-linux-scarthgap"
  bsp_manifest_file: "imx-6.6.52-2.2.0.xml"

paths:
  workspace_root: "~/imx95-workspace"
  bsp_sources: "sources"
  build_dir: "build"
  custom_layer: "sources/meta-imx95-custom"
  dt_overlay_dir: "sources/meta-imx95-custom/recipes-kernel/linux/files/overlays"
  overlay_tracker: "overlay-tracker"
  deploy_dir: "build/tmp/deploy/images/imx95-19x19-lpddr5-evk"
  staging_dir: "staging"

flash:
  tool: "uuu"
  uuu_script: "references/uuu-scripts/frdm-imx95-emmc.uuu"
  uuu_version_min: "1.5.21"
  recovery_mode_jumper: "J301"
  usb_vid_pid: "1fc9:0146"

device_tree:
  base_dts: "imx95-19x19-lpddr5-evk.dts"
  overlay_prefix: "imx95-custom"
  kernel_dt_path: "sources/linux-imx/arch/arm64/boot/dts/freescale/"

custom_carrier:
  carrier_name: null
  base_overlay: null
  schematic_pdf: null

notes: |
  Standard FRDM-IMX95 EVK configuration.
  Boot mode: eMMC (SW1[1]=ON, SW1[2:4]=OFF after flashing).
  Recovery mode: SW1[1:4]=OFF, USB-C to J301.
```

---

## Validation Rules

Skills that read `active_target.yaml` MUST validate the following before proceeding:

1. `schema_version` == `"1.0"` — refuse to operate on unknown schema versions
2. `profile_name` matches `[a-z0-9-]+` — no spaces or special characters
3. `board.soc` == `"imx95"` — this bundle only supports i.MX 95
4. `board.boot_device` is one of `"emmc"`, `"sd"`, `"flexspi"`
5. `flash.tool` == `"uuu"` — refuse if any other flash tool is specified
6. `flash.usb_vid_pid` == `"1fc9:0146"` — warn if different (custom ROM)
7. `paths.workspace_root` is an absolute path or starts with `~/`
8. `paths.deploy_dir` contains the `yocto.machine` value as a path component
9. If `board.custom_carrier` == `true`, then `custom_carrier.carrier_name` must not be null

---

## Active Target Pointer

```bash
# The active target is always read from:
<workspace>/targets/active_target.yaml

# To switch targets (use imx95-set-target skill, or manually):
ln -sf <profile_name>.yaml <workspace>/targets/active_target.yaml

# To verify the active target:
cat <workspace>/targets/active_target.yaml | grep profile_name
```

---

## Path Resolution

All relative paths in the `paths:` section are resolved relative to `paths.workspace_root`.
Skills expand `~/` to `$HOME` before using any path.

```python
# Pseudocode for path resolution used by all skills:
import os, yaml
with open("targets/active_target.yaml") as f:
    target = yaml.safe_load(f)
workspace = os.path.expanduser(target["paths"]["workspace_root"])
deploy_dir = os.path.join(workspace, target["paths"]["deploy_dir"])
```
