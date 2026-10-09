# BSP Customization Workflow — i.MX 95 Yocto BSP

> **Shared context document.** All skills read this before executing any phase.
> This document defines the authoritative 4-phase workflow for the imx95-bsp-skills bundle.

---

## Overview

The imx95-bsp-skills workflow is divided into four sequential phases. Each phase has a defined
entry condition, a set of active skills, a set of files it touches, and a success criterion
that must be met before the next phase begins.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  PHASE 1: SETUP          PHASE 2: CUSTOMIZE     PHASE 3: BUILD               │
│                                                                              │
│  imx95-init-target  ──►  imx95-derive-carrier ──► imx95-build-source        │
│  imx95-download-bsp      imx95-customize-*         (bitbake)                 │
│  imx95-init-source        overlay-tracker git  ──► PHASE 4: DEPLOY           │
│  imx95-print-bsp-info     commit-gate              imx95-promote-image       │
│                                                    imx95-flash-image         │
│                                                    imx95-validate-image      │
└──────────────────────────────────────────────────────────────────────────────┘
```

Phases 2 and 3 form a loop: customize → build → validate → customize again as needed.

---

## Phase 1: Setup

### What It Does

Phase 1 establishes the BSP workspace from scratch. It downloads the NXP Yocto BSP source
tree, creates the target profile YAML, configures the Yocto build environment, and initializes
the overlay-tracker git repository.

### Active Skills

| Skill | Role |
|---|---|
| `imx95-quick-start` | Guided entry point — orchestrates the other setup skills |
| `imx95-init-target` | Creates `targets/<profile>.yaml` and sets `active_target.yaml` |
| `imx95-download-bsp` | Runs `repo init` + `repo sync` to download all BSP layers |
| `imx95-init-source` | Sources `oe-init-build-env`, creates `meta-imx95-custom`, inits overlay-tracker |
| `imx95-print-bsp-info` | Prints workspace state — safe to run at any time |

### Files Touched

```
<workspace>/
├── targets/
│   ├── <profile_name>.yaml          ← created by imx95-init-target
│   └── active_target.yaml           ← symlink/copy set by imx95-init-target
├── .repo/                           ← created by repo init
├── sources/                         ← populated by repo sync
│   ├── meta-imx/                    ← NXP i.MX layer (READ-ONLY after this)
│   ├── meta-freescale/              ← Freescale community layer (READ-ONLY)
│   ├── poky/                        ← Yocto Poky (READ-ONLY)
│   ├── linux-imx/                   ← NXP kernel (READ-ONLY — use overlays)
│   ├── u-boot-imx/                  ← NXP U-Boot (READ-ONLY — use bbappend)
│   └── meta-imx95-custom/           ← YOUR layer (created by imx95-init-source)
├── build/
│   ├── conf/local.conf              ← MACHINE, DISTRO, IMAGE_INSTALL
│   └── conf/bblayers.conf           ← layer stack
└── overlay-tracker/                 ← empty git repo (created by imx95-init-source)
    └── .git/
```

### Success Criteria

- [ ] `targets/active_target.yaml` exists and is valid YAML matching the schema in
      `context/target-platform-contract.md`
- [ ] `sources/meta-imx/` exists and contains `conf/layer.conf`
- [ ] `sources/poky/oe-init-build-env` exists
- [ ] `build/conf/local.conf` contains `MACHINE = "<machine>"` matching the active target
- [ ] `build/conf/bblayers.conf` includes `meta-imx95-custom`
- [ ] `overlay-tracker/.git/` exists with at least one commit
- [ ] `bitbake-layers show-layers` runs without error
- [ ] `imx95-print-bsp-info` runs and shows all green

### Estimated Time

| Step | Time |
|---|---|
| `repo init` | < 1 minute |
| `repo sync -j8` (first time, ~10–20 GB) | 30–60 minutes (network-dependent) |
| `oe-init-build-env` + layer setup | < 5 minutes |
| Total Phase 1 | ~35–65 minutes |

---

## Phase 2: Customize

### What It Does

Phase 2 modifies the BSP for the target hardware. All customizations are made through:
1. **Device tree overlays** in `sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/`
2. **bbappend recipes** in `sources/meta-imx95-custom/`

Upstream BSP layers (`meta-imx`, `meta-freescale`, `poky`, `linux-imx`) are **never modified
directly**. Every DT change is committed to the `overlay-tracker` git repository before
building.

### Active Skills

| Skill | Role |
|---|---|
| `imx95-derive-carrier` | Fork FRDM-IMX95 base DTS into a custom carrier overlay |
| `imx95-customize-pinmux` | Modify IOMUX pad function, drive strength, pull settings |
| `imx95-customize-usb` | Configure USB3 OTG and USB2 host DT nodes |
| `imx95-customize-camera` | Add MIPI-CSI2 camera sensor pipeline to DT |
| `imx95-customize-clocks` | Modify clock assignments and frequencies in DT |
| `imx95-optimize-memory` | Tune CMA size, DMA-BUF pool, reserved-memory regions |

### Files Touched

```
sources/meta-imx95-custom/
├── conf/layer.conf
├── recipes-kernel/
│   └── linux/
│       ├── linux-imx_%.bbappend          ← registers overlays with kernel recipe
│       └── files/
│           └── overlays/
│               ├── imx95-<carrier>.dts           ← main carrier overlay
│               ├── imx95-<carrier>-pinmux.dts    ← pinmux sub-overlay
│               ├── imx95-<carrier>-camera.dts    ← camera overlay (if applicable)
│               └── imx95-<carrier>-memory.dts    ← memory overlay (if applicable)
└── recipes-bsp/
    └── u-boot/
        └── u-boot-imx_%.bbappend         ← U-Boot env for overlay loading (if needed)

overlay-tracker/                          ← git repo tracking all DT changes
├── imx95-<carrier>.dts                   ← symlink or copy of overlay files
└── imx95-<carrier>-pinmux.dts
```

### Overlay-Tracker Git Pattern

Every customize skill MUST follow this pattern for every DT file change:

1. **Make the change** to the overlay `.dts` file in `dt_overlay_dir`.
2. **Stage the change** in overlay-tracker:
   ```bash
   cd <workspace>/overlay-tracker
   git add <changed-file>.dts [<bbappend>.bbappend]
   ```
3. **Show the diff** — display `git diff --staged` in full to the user.
4. **STOP** — wait for explicit user approval ("approve", "looks good", "commit it").
5. **Commit** with the structured message format:
   ```
   customize(<subsystem>): <one-line summary>

   Board: <profile_name>
   Skill: imx95-customize-<subsystem>
   Files: <list of changed files>

   <Description of what was changed and why>

   Tested: pending
   ```

**This pattern is mandatory. No exceptions. See CLAUDE.md Section 8 (Commit-Gate Rule).**

### Success Criteria

- [ ] All desired DT changes are in overlay files under `dt_overlay_dir`
- [ ] `dtc -I dts -O dtb <overlay>.dts` compiles without errors or warnings
- [ ] `overlay-tracker` working tree is **clean** (`git status` shows nothing to commit)
- [ ] `overlay-tracker` git log shows one commit per logical change
- [ ] No files modified in `sources/meta-imx/`, `sources/meta-freescale/`, or `sources/poky/`

### Estimated Time

| Change | Time |
|---|---|
| Simple pinmux change (1–2 pads) | 5–15 minutes |
| USB or PCIe DT configuration | 15–30 minutes |
| Camera pipeline (new sensor) | 30–60 minutes |
| Full custom carrier derivation | 1–2 hours |

---

## Phase 3: Build

### What It Does

Phase 3 runs the Yocto `bitbake` build to produce the firmware image. The build system
compiles the kernel (including DT overlays), U-Boot, and the root filesystem, then packages
them into flashable artifacts.

### Active Skills

| Skill | Role |
|---|---|
| `imx95-build-source` | Pre-flight checks + `bitbake <image_recipe>` + artifact report |

### Pre-Flight Checks (ALL must pass before bitbake runs)

1. `targets/active_target.yaml` exists and is valid
2. `build/conf/local.conf` has correct `MACHINE` matching the active target
3. `overlay-tracker/` working tree is **clean** (no uncommitted changes)
4. ≥ 50 GB free disk space in workspace (80 GB recommended)
5. `bitbake` is on PATH (Yocto environment sourced)
6. Not running as root

### Files Touched

```
build/
├── conf/local.conf                  ← read (not modified during build)
├── conf/bblayers.conf               ← read (not modified during build)
├── tmp/
│   ├── deploy/
│   │   └── images/<machine>/
│   │       ├── imx-boot-<machine>.bin        ← combined boot image
│   │       ├── Image                         ← kernel image
│   │       ├── <machine>.dtb                 ← compiled DTB
│   │       ├── <image>-<machine>.rootfs.ext4 ← root filesystem
│   │       └── <image>-<machine>.rootfs.wic.zst ← full WIC image
│   └── work/                        ← intermediate build artifacts
└── sstate-cache/                    ← shared state cache (speeds up rebuilds)
```

### Build Modes

| Mode | Command | When to use | Approx. time |
|---|---|---|---|
| Full image (first build) | `bitbake <image_recipe>` | First build, rootfs changes | 2–4 hours |
| Full image (incremental) | `bitbake <image_recipe>` | After any change | 10–30 min |
| Kernel only | `bitbake linux-imx` | DT or driver changes | 5–15 min |
| DTB only | `bitbake linux-imx -c compile -f` | DT overlay changes only | 2–5 min |
| devtool | `devtool modify linux-imx` | Interactive kernel development | varies |

### Success Criteria

- [ ] `bitbake` exits with code 0
- [ ] `build/tmp/deploy/images/<machine>/imx-boot-<machine>.bin` exists
- [ ] `build/tmp/deploy/images/<machine>/Image` exists
- [ ] `build/tmp/deploy/images/<machine>/<machine>.dtb` exists
- [ ] `build/tmp/deploy/images/<machine>/<image>-<machine>.rootfs.wic.zst` exists
- [ ] No `ERROR:` lines in `build/tmp/log/cooker/<machine>/` build log

### Estimated Time

| Build type | Time |
|---|---|
| First full build (cold sstate) | 2–4 hours |
| Incremental full image | 10–30 minutes |
| Kernel + DTB only | 5–15 minutes |
| DTB only (force recompile) | 2–5 minutes |

---

## Phase 4: Deploy

### What It Does

Phase 4 stages the build artifacts, flashes them to the board via `uuu`, and validates that
the board boots correctly with the expected configuration.

### Active Skills

| Skill | Role |
|---|---|
| `imx95-promote-image` | Copy artifacts to `staging/`, generate SHA256 manifest |
| `imx95-flash-image` | Pre-flight checks + `uuu` flash with mandatory confirmation gate |
| `imx95-validate-image` | Post-flash validation checklist (host-side + board-side) |

### Files Touched

```
staging/
├── imx-boot-<machine>.bin           ← copied from tmp/deploy/images/
├── Image                            ← copied
├── <machine>.dtb                    ← copied
├── <image>-<machine>.rootfs.wic.zst ← copied
└── artifact-manifest.json           ← SHA256 checksums of all staged files
```

### Flash Safety Gates

The following gates are **mandatory** and cannot be bypassed:

1. **Pre-flight gate:** `uuu --version` ≥ 1.5.21, board detected at VID:PID `1fc9:0146`
2. **Artifact gate:** SHA256 of staged files matches `artifact-manifest.json`
3. **Confirmation gate:** User must type exactly `"flash confirmed"` before `uuu` runs

### Success Criteria

- [ ] `staging/artifact-manifest.json` exists with SHA256 checksums
- [ ] `uuu` exits with code 0
- [ ] Board boots to U-Boot prompt (visible on serial console)
- [ ] Kernel boots to login prompt
- [ ] `uname -r` shows expected kernel version (6.6.x)
- [ ] `cat /proc/device-tree/model` shows expected board model string
- [ ] Customized peripherals appear in `dmesg` without errors

### Estimated Time

| Step | Time |
|---|---|
| `imx95-promote-image` | < 2 minutes |
| `imx95-flash-image` (target device via uuu — **name it**: `mmcblk0` eMMC vs `mmcblk1` SD; on the fleet board `/` is `mmcblk1p2`, so the eMMC script no-ops and the SD script destroys the running rootfs) | 3–8 minutes |
| `imx95-validate-image` (boot + checks) | 5–10 minutes |
| Total Phase 4 | ~10–20 minutes |

---

## Workflow Loop: Customize → Build → Validate

After the first successful deploy, the typical development loop is:

```
1. Make a DT change (imx95-customize-*)
   └─► overlay-tracker commit (commit-gate)
2. Build (imx95-build-source)
   └─► bitbake linux-imx  (kernel + DTB only, ~5–15 min)
3. Promote + Flash (imx95-promote-image → imx95-flash-image)
   └─► uuu flash (~5 min)
4. Validate (imx95-validate-image)
   └─► check dmesg, peripheral probing
5. If OK: continue to next change
   If not OK: go back to step 1
```

For rootfs changes (adding packages, changing image recipe), run a full `bitbake <image_recipe>`
instead of `bitbake linux-imx`.

---

## Key Invariants (Always True)

These invariants must hold at all times. Any skill that would violate them must stop and
alert the user.

| # | Invariant |
|---|---|
| I1 | `targets/active_target.yaml` always points to a valid, complete target profile |
| I2 | `overlay-tracker` working tree is clean before any `bitbake` run |
| I3 | No files in `sources/meta-imx/`, `sources/meta-freescale/`, or `sources/poky/` are modified |
| I4 | Every `git commit` in this workspace was preceded by a shown diff and explicit user approval |
| I5 | `uuu` is never run without the full confirmation prompt and `"flash confirmed"` response |
| I6 | `bitbake` is never run as root |
| I7 | Disk space ≥ 50 GB before any full image build |
