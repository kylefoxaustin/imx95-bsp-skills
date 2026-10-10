---
name: imx95-quick-start
version: "0.1.0"
platform: imx95-bsp
phase: setup
invoke_when:
  - "help me set up the BSP"
  - "first time setup"
  - "start from scratch"
  - "I'm new to this"
  - "help me set up the i.MX 95 BSP workspace"
  - "quick start"
requires_host_tools:
  - git
  - python3
  - repo
safe: true
destructive: false
commit_gate: false
---

# imx95-quick-start

## Purpose

Guided first-time setup agent for the NXP i.MX 95 Yocto BSP. Walks the user from zero to a
fully configured workspace ready for customization and building. Asks the core questions,
validates prerequisites, and dispatches the correct skill chain.

**This is the recommended entry point for all new users.**

## When to Invoke

- User says "help me set up the BSP", "first time", "start from scratch", "I'm new to this"
- User says "help me set up the i.MX 95 BSP workspace"
- User has just run `setup.sh` and started Claude Code for the first time

## Pre-conditions

- `setup.sh` has been run and the workspace exists
- Claude Code is running from `<workspace>/` (so `CLAUDE.md` was loaded)
- Host has `git`, `python3` installed (minimum for setup phase)

## Decision Tree

```
User asks for setup
       │
       ▼
1. Check prerequisites (tools, disk space)
       │
       ├─ Missing required tools? → Guide user to install them, then stop
       │
       ▼
2. Ask: Which board? (FRDM-IMX95 or custom)
       │
       ├─ FRDM-IMX95 → use defaults, skip carrier questions
       └─ Custom board → ask carrier name, base board
       │
       ▼
3. Ask: BSP release (default: imx-linux-scarthgap / imx-6.6.52-2.2.0.xml)
       │
       ▼
4. Ask: Image recipe (default: imx-image-full)
       │
       ▼
5. Ask: Boot device (default: eMMC)
       │
       ▼
6. Ask: Workspace path (default: ~/imx95-workspace)
       │
       ▼
7. STOP — Show summary, wait for approval
       │
       ▼
8. Dispatch skill chain:
   imx95-init-target → imx95-download-bsp → imx95-init-source
   → (if custom carrier) imx95-derive-carrier
       │
       ▼
9. Print final summary via imx95-print-bsp-info
```

## Procedure

### Step 1 — Welcome and Prerequisites Check

Greet the user and explain what will happen:

```
Welcome to imx95-bsp-skills! I'll guide you through setting up the NXP i.MX 95
Yocto BSP workspace. This will take about 35–65 minutes (most of that is BSP download).

Let me first check your host tools...
```

Check the following tools and report status:

| Tool | Required? | Check command | Min version |
|---|---|---|---|
| `git` | YES | `git --version` | any |
| `python3` | YES | `python3 --version` | 3.8+ |
| `repo` | YES (for BSP download) | `repo --version` | any |
| `dtc` | YES (for DT work) | `dtc --version` | any |
| `uuu` | YES (for flashing) | `uuu --version` | 1.5.21+ |
| `bitbake` | NO (not yet) | — | — |

If any **required** tool is missing, show the install command and stop:
```
⚠️  Missing required tool: repo

Install it with:
  mkdir -p ~/bin
  curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
  chmod a+x ~/bin/repo
  echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
  source ~/.bashrc

Then restart Claude Code and try again.
```

Check disk space. Warn if < 80 GB free:
```
⚠️  Only 45 GB free at ~/. A full Yocto build needs 80–120 GB.
   You can proceed, but the build may fail due to disk space.
   Recommended: free up space or use a larger disk.
```

### Step 2 — Ask Core Questions

Ask these questions one at a time (not all at once):

**Q1: Board variant**
```
Which board are you using?
  1. FRDM-IMX95 EVK (NXP Freedom board, 19×19 mm, LPDDR5) [DEFAULT]
  2. i.MX95-19x19-LPDDR5-EVK (standalone EVK)
  3. i.MX95-15x15-EVK
  4. Custom carrier board (based on FRDM-IMX95 SOM)

Enter 1–4 [1]:
```

**Q2: BSP release** (only ask if user wants non-default)
```
BSP release to use:
  Default: imx-linux-scarthgap / imx-6.6.52-2.2.0.xml (kernel 6.6.52, recommended)

Press Enter to use the default, or type a different manifest file name:
```

**Q3: Image recipe**
```
Which image recipe do you want to build?
  1. imx-image-full — Full NXP demo image with Weston/Wayland (~2.5 GB) [DEFAULT]
  2. imx-image-multimedia — Multimedia stack with GStreamer/VPU (~1.5 GB)
  3. core-image-base — Minimal console image, no GUI (~500 MB)
  4. Custom (enter recipe name)

Enter 1–4 [1]:
```

**Q4: Boot device**
```
Primary boot device:
  1. eMMC [DEFAULT]
  2. SD card

Enter 1–2 [1]:
```

**Q5: Workspace path**
```
BSP workspace directory:
  Default: ~/imx95-workspace

Press Enter to use the default, or enter a different path:
```

**Q6: Custom carrier (only if Q1 = 4)**
```
Custom carrier board name (short slug, e.g., "acme-carrier-v1"):
```

### Step 3 — STOP: Show Summary and Wait for Approval

Display a complete summary of what will be done:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SETUP PLAN — imx95-bsp-skills
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Board         : FRDM-IMX95 EVK
  MACHINE       : imx95-19x19-lpddr5-evk   ⚠️ [UNVERIFIED sample — §7/Q3: 1 fleet ref vs 68 for imx95-19x19-frdm-pro]
  Image recipe  : imx-image-full
  DISTRO        : fsl-imx-xwayland
  Boot device   : eMMC
  BSP manifest  : imx-linux-scarthgap / imx-6.6.52-2.2.0.xml
  Workspace     : ~/imx95-workspace
  Custom carrier: No

  Steps to be performed:
  1. imx95-init-target  — create target profile YAML (~1 min)
  2. imx95-download-bsp — repo init + sync BSP (~30–60 min, ~15 GB download)
  3. imx95-init-source  — source Yocto env, create meta-imx95-custom (~5 min)
  4. imx95-print-bsp-info — verify workspace state

  Total estimated time: 35–65 minutes (mostly BSP download)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Reply "proceed" to start, or tell me what to change.
```

**WAIT** for user to reply "proceed" (or equivalent approval) before continuing.

### Step 4 — Dispatch imx95-init-target

Read `skills/imx95-init-target/SKILL.md` completely and follow its procedure to create the
target profile YAML. Pass the answers from Step 2 as inputs (do not ask again).

### Step 5 — Dispatch imx95-download-bsp

Read `skills/imx95-download-bsp/SKILL.md` completely and follow its procedure to run
`repo init` and `repo sync`.

Warn the user before starting the download:
```
Starting BSP download. This will download ~10–20 GB and may take 30–60 minutes.
You can monitor progress in the terminal. Do not interrupt the download.
```

### Step 6 — Dispatch imx95-init-source

Read `skills/imx95-init-source/SKILL.md` completely and follow its procedure to:
- Source `oe-init-build-env`
- Create `meta-imx95-custom` layer
- Initialize `overlay-tracker` git repo

### Step 7 — (Optional) Dispatch imx95-derive-carrier

If the user selected a custom carrier board (Q1 = 4), read
`skills/imx95-derive-carrier/SKILL.md` and follow its procedure.

### Step 8 — Final Summary

Run `skills/imx95-print-bsp-info/SKILL.md` procedure to print the workspace state.

Then display:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SETUP COMPLETE ✓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Your i.MX 95 BSP workspace is ready.

Next steps:
  • To build the image:
    "build the image"  →  imx95-build-source

  • To customize hardware (pinmux, USB, camera, etc.):
    "I need to enable UART4 on GPIO_IO04/05"  →  imx95-customize-pinmux
    "Add a MIPI CSI camera"                   →  imx95-customize-camera
    "Configure USB3 OTG"                      →  imx95-customize-usb

  • To flash the board after building:
    "flash the board"  →  imx95-promote-image → imx95-flash-image

  • To check workspace state at any time:
    "show BSP info"  →  imx95-print-bsp-info
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Estimated Time per Phase

| Phase | Step | Time |
|---|---|---|
| Setup | imx95-init-target | < 1 min |
| Setup | imx95-download-bsp (repo sync) | 30–60 min |
| Setup | imx95-init-source | < 5 min |
| Setup | imx95-derive-carrier (if custom) | 5–10 min |
| Build | imx95-build-source (first full build) | 2–4 hours |
| Deploy | imx95-promote-image + imx95-flash-image | ~10 min |

## Safety Rules Applied

- R6: Never run bitbake as root (check before sourcing environment)
- R7: Disk space check before proceeding (warn if < 80 GB)

## References

- `context/bsp-customization-workflow.md` — full 4-phase workflow
- `context/target-platform-contract.md` — target profile schema
- `references/bsp-platforms-catalogue.md` — board variants and MACHINE names
