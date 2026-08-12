---
name: imx95-init-source
version: "1.0"
platform: imx95
phase: setup
invoke_when:
  - "source the environment"
  - "init build env"
  - "source oe-init-build-env"
  - "set up the build directory"
  - "initialize the Yocto environment"
requires_host_tools:
  - bash
  - git
  - bitbake
safe: true
destructive: false
commit_gate: false
---

# imx95-init-source

## Purpose

Source the Yocto build environment (`oe-init-build-env`), configure `build/conf/local.conf`
and `build/conf/bblayers.conf` for the active target, create the `meta-imx95-custom` layer
if it does not exist, and initialize the `overlay-tracker` git repository.

## When to Invoke

- After `imx95-download-bsp` on first setup
- At the start of any new shell session before running `bitbake`
- After changing the active target (MACHINE or DISTRO change)

## Pre-conditions

1. `targets/active_target.yaml` exists and is valid.
2. `sources/poky/oe-init-build-env` exists (BSP has been synced).
3. Shell is NOT running as root (bitbake refuses to run as root).

## Procedure

### Step 1 — Read active target

Read `targets/active_target.yaml` and extract:
- `yocto.machine`       → MACHINE value
- `yocto.distro`        → DISTRO value
- `yocto.image_recipe`  → image recipe (informational)
- `paths.workspace_root` → workspace root
- `paths.build_dir`     → build directory (relative to workspace)
- `paths.custom_layer`  → path to meta-imx95-custom

### Step 2 — Check not running as root

```bash
if [[ "$(id -u)" == "0" ]]; then
    echo "ERROR: Do not run bitbake as root. Switch to a non-root user."
    exit 1
fi
```

### Step 3 — Source oe-init-build-env

```bash
cd <workspace_root>/sources/poky
MACHINE=<machine> DISTRO=<distro> source oe-init-build-env ../../<build_dir>
# This changes CWD to <workspace_root>/<build_dir>
```

This creates `build/conf/local.conf` and `build/conf/bblayers.conf` if they do not exist.

### Step 4 — Configure local.conf

Ensure these settings are present in `build/conf/local.conf`:

```bash
# Set by init_source.sh:
MACHINE = "<machine>"
DISTRO  = "<distro>"

# Parallel build settings (auto-detected from nproc):
BB_NUMBER_THREADS = "<nproc>"
PARALLEL_MAKE     = "-j <nproc>"

# Shared download and sstate cache (speeds up rebuilds):
DL_DIR    = "<workspace_root>/downloads"
SSTATE_DIR = "<workspace_root>/sstate-cache"

# Accept NXP EULA (required for proprietary firmware blobs):
ACCEPT_FSL_EULA = "1"
```

### Step 5 — Configure bblayers.conf

Ensure `meta-imx95-custom` is in the layer stack. The script checks
`build/conf/bblayers.conf` and adds the layer if missing:

```
BBLAYERS += "<workspace_root>/sources/meta-imx95-custom"
```

### Step 6 — Create meta-imx95-custom layer if absent

If `sources/meta-imx95-custom/` does not exist, create it:

```bash
bash skills/imx95-init-source/scripts/init_source.sh --create-custom-layer
```

The layer structure created:
```
sources/meta-imx95-custom/
├── conf/
│   └── layer.conf
├── recipes-kernel/
│   └── linux/
│       └── files/
│           └── overlays/          ← DT overlay files go here
└── README
```

### Step 7 — Initialize overlay-tracker

```bash
cd <workspace_root>/overlay-tracker
git init 2>/dev/null || true
# Only create initial commit if repo is empty
if ! git log --oneline -1 &>/dev/null; then
    git commit --allow-empty -m "init: overlay tracker for <profile_name>"
fi
```

### Step 8 — Verify layer stack

```bash
cd <workspace_root>/<build_dir>
bitbake-layers show-layers
```

Expected output includes: `meta`, `meta-poky`, `meta-freescale`, `meta-imx`,
`meta-imx95-custom`.

### Step 9 — Report to user

Print:
- MACHINE and DISTRO configured
- Layer stack summary
- overlay-tracker status
- Recommended next step

## Files Touched

- `<workspace>/build/conf/local.conf` — MACHINE, DISTRO, DL_DIR, SSTATE_DIR, ACCEPT_FSL_EULA
- `<workspace>/build/conf/bblayers.conf` — meta-imx95-custom added
- `<workspace>/sources/meta-imx95-custom/` — created if absent
- `<workspace>/overlay-tracker/` — git init + initial empty commit

## Safety Rules Applied

- **R2** — Never modify upstream layers; only meta-imx95-custom is created/modified
- **R6** — Check not running as root before sourcing environment

## References

- `context/bsp-customization-workflow.md` — full workflow context
- `context/bsp-customization-software-layers.md` — Yocto layer model
- `context/target-platform-contract.md` — target profile YAML schema
