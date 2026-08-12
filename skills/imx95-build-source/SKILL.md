---
name: imx95-build-source
version: "1.0"
platform: imx95
phase: build
invoke_when:
  - "build the image"
  - "run bitbake"
  - "compile"
  - "build kernel"
  - "build DTB"
  - "bitbake"
requires_host_tools:
  - bitbake
  - git
safe: true
destructive: false
commit_gate: false
---

# imx95-build-source

## Purpose

Run a `bitbake` build for the active target's image recipe. Performs pre-flight checks
(active target, git clean, disk space, MACHINE match), runs bitbake, and reports build
results with artifact locations.

## When to Invoke

- After any DT customization or layer change
- User says "build the image", "run bitbake", "compile", "build kernel"

## Pre-conditions

1. `targets/active_target.yaml` exists and is valid.
2. Yocto environment has been sourced (`oe-init-build-env`).
3. `build/conf/local.conf` has correct `MACHINE`.
4. `overlay-tracker/` working tree is **clean** (no uncommitted changes).
5. ≥ 50 GB free disk space.
6. Not running as root.

## Build Modes

| Mode | Command | When to use |
|---|---|---|
| Full image | `bitbake <image_recipe>` | First build, rootfs changes |
| Kernel only | `bitbake linux-imx` | DT or driver changes |
| DTB only | `bitbake linux-imx -c compile -f && bitbake linux-imx -c deploy -f` | DT overlay changes only |
| devtool | `devtool modify linux-imx` | Interactive kernel development |
| Clean recipe | `bitbake <recipe> -c cleansstate` | Force full rebuild of recipe |

## Procedure

### Step 1 — Run pre-flight checks

```bash
bash skills/imx95-build-source/scripts/build.sh --preflight-only
```

Pre-flight checks (ALL must pass):
1. `targets/active_target.yaml` exists
2. `build/conf/local.conf` MACHINE matches active target
3. `overlay-tracker/` working tree is clean
4. ≥ 50 GB free disk space
5. Not running as root
6. `bitbake` is on PATH

If any check fails, report the failure and the corrective action. Do NOT proceed.

### Step 2 — Determine build mode

Ask user (or infer from context):
- Full image build? → `bitbake <image_recipe>`
- Kernel/DT only? → `bitbake linux-imx`
- DTB only (fastest)? → force compile + deploy

### Step 3 — Run build

```bash
bash skills/imx95-build-source/scripts/build.sh [--kernel-only | --dtb-only]
```

Estimated build times (first build, 16-core host):
- Full image (`imx-image-full`): 2–4 hours
- Kernel only (`linux-imx`): 15–30 minutes
- DTB only: 2–5 minutes
- Subsequent builds (sstate cache): 5–30 minutes

### Step 4 — Report build results

After build completes:
- Print artifact list with sizes and timestamps
- Print deploy directory path
- Recommend next step: `imx95-promote-image`

If build fails:
- Show last 50 lines of the failed task log
- Identify the failing recipe and task
- Suggest corrective action

## Files Touched

- `build/tmp/deploy/images/<machine>/` — build artifacts (written by bitbake)
- `build/tmp/work/` — recipe work directories (managed by bitbake)

## Safety Rules Applied

- **R3** — Blocks build if overlay-tracker has uncommitted changes
- **R6** — Blocks build if running as root
- **R7** — Blocks build if < 50 GB free disk space

## References

- `context/bsp-customization-workflow.md` — full workflow
- `context/target-platform-contract.md` — target profile schema
