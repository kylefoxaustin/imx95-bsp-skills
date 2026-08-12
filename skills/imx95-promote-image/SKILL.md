---
name: imx95-promote-image
version: "1.0"
platform: imx95
phase: deploy
invoke_when:
  - "stage artifacts"
  - "prepare for flash"
  - "promote image"
  - "copy artifacts"
  - "staging"
requires_host_tools:
  - sha256sum
  - git
safe: true
destructive: false
commit_gate: false
---

# imx95-promote-image

## Purpose

Copy build artifacts from `build/tmp/deploy/images/<machine>/` into a timestamped
`staging/` directory, generate a `manifest.txt` with SHA256 checksums, and verify
artifact integrity. Prepares artifacts for `imx95-flash-image`.

## When to Invoke

- After a successful `imx95-build-source`
- User says "stage artifacts", "prepare for flash", "promote image"

## Pre-conditions

1. `targets/active_target.yaml` exists.
2. `build/tmp/deploy/images/<machine>/` contains fresh build artifacts.
3. ≥ 5 GB free in workspace for staging copies.

## Artifacts Staged

| Artifact | Description |
|---|---|
| `imx-boot-<machine>.bin` | Combined boot image (SPL + ATF + U-Boot) |
| `Image` | Kernel image (uncompressed ARM64) |
| `<machine>.dtb` | Compiled device tree blob |
| `<image_recipe>-<machine>.rootfs.wic.zst` | Full WIC image (compressed) |
| `<image_recipe>-<machine>.rootfs.ext4` | Root filesystem ext4 (optional) |

## Procedure

### Step 1 — Run promote script

```bash
bash skills/imx95-promote-image/scripts/promote.sh
```

### Step 2 — Show artifact manifest to user

Display the complete `manifest.txt` with filenames, sizes, and SHA256 checksums.

### STOP — Confirm with user

State: "Here are the staged artifacts and their checksums. Please verify the artifact
list looks correct before flashing. Reply 'ok' to proceed to flash, or 'cancel' to stop."

### Step 3 — Recommend next step

After user confirms: suggest `imx95-flash-image`.

## Files Touched

- `staging/<timestamp>/` — timestamped staging directory (created)
- `staging/latest/` — symlink to most recent staging directory (updated)
- `staging/<timestamp>/manifest.txt` — SHA256 checksums of all staged artifacts

## Safety Rules Applied

- **R1** — This skill does NOT flash; it only stages. Flashing requires imx95-flash-image.

## References

- `context/bsp-customization-workflow.md` — workflow context
- `context/target-platform-contract.md` — target profile schema
