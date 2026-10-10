---
name: imx95-print-bsp-info
version: "1.0"
platform: imx95
phase: setup
invoke_when:
  - "show BSP info"
  - "what's the current state"
  - "print workspace info"
  - "show active target"
  - "what board am I building for"
  - "check workspace"
requires_host_tools:
  - git
  - python3
safe: true
destructive: false
commit_gate: false
---

# imx95-print-bsp-info

## Purpose

Print a concise, structured summary of the current BSP workspace state. No files are
modified. Safe to run at any time, including before builds, after customizations, or
when debugging workspace issues.

## When to Invoke

- User asks "what's the current state?", "show BSP info", "what board am I building for?"
- Before starting a build (to confirm MACHINE and image recipe)
- After switching targets (to confirm the change took effect)
- When debugging a workspace issue

## Pre-conditions

None — this skill is always safe to run. It gracefully handles missing files.

## Procedure

### Step 1 — Run the info script

```bash
bash skills/imx95-print-bsp-info/scripts/print_bsp_info.sh
```

### Step 2 — Present output to user

Display the full output. If any section shows warnings or errors, highlight them and
suggest the appropriate corrective skill.

### Step 3 — Suggest next action

Based on the output:
- If no active target → suggest `imx95-init-target`
- If no BSP sources → suggest `imx95-download-bsp`
- If build dir missing → suggest `imx95-init-source`
- If overlay-tracker has uncommitted changes → suggest committing before building
- If disk space < 50 GB → warn before any build

## Output Sections

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  imx95-bsp-skills — Workspace Info
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Active Target
    Profile     : frdm-imx95-base
    Board       : FRDM-IMX95
    MACHINE     : imx95-19x19-lpddr5-evk   ⚠️ [UNVERIFIED sample — §7/Q3: 1 fleet ref vs 68 for imx95-19x19-frdm-pro]
    DISTRO      : fsl-imx-xwayland
    Image recipe: imx-image-full
    Boot device : emmc
    Custom carrier: false

  BSP Manifest
    URL    : https://github.com/nxp-imx/imx-manifest
    Branch : imx-linux-scarthgap
    File   : imx-6.6.52-2.2.0.xml

  Workspace Paths
    Root         : ~/imx95-workspace
    Sources      : sources/  [present]
    Build dir    : build/    [present]
    Custom layer : sources/meta-imx95-custom/  [present]
    Overlay dir  : sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/
    Staging dir  : staging/  [absent]

  Layer Stack (bitbake-layers show-layers)
    meta              /path/to/poky/meta
    meta-poky         /path/to/poky/meta-poky
    meta-freescale    /path/to/sources/meta-freescale
    meta-imx          /path/to/sources/meta-imx
    meta-imx95-custom /path/to/sources/meta-imx95-custom

  Overlay Tracker (last 5 commits)
    abc1234 customize(pinmux): enable UART4 on GPIO_IO04/05
    def5678 init: overlay tracker for frdm-imx95-base

  Build Artifacts (build/tmp/deploy/images/<machine>/)
    imx-boot-<machine>.bin   [present, 2024-01-15 14:32]
    imx-image-full-<machine>.rootfs.wic.zst  [present]

  Host Tools
    uuu     : 1.5.21  ✓
    dtc     : 1.6.1   ✓
    repo    : 2.41    ✓
    git     : 2.43.0  ✓
    bitbake : 2.8.0   ✓ (if environment sourced)

  Disk Space
    Workspace : 127 GB free of 500 GB
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Files Touched

None — read-only.

## Safety Rules Applied

None — this skill is purely informational.

## References

- `context/target-platform-contract.md` — target profile YAML schema
- `context/bsp-customization-workflow.md` — workflow phases
