# imx95-bsp-skills

> **AgentSkills.io-convention skill bundle for the NXP i.MX 95 Yocto BSP.**
> Runs on the **developer host machine** — not on the board.

---

## Overview

`imx95-bsp-skills` gives [Claude Code](https://claude.ai/code) a structured, safety-gated
workflow for setting up, customizing, building, and deploying the NXP Yocto Linux BSP for the
**FRDM-IMX95 EVK** and custom i.MX 95 carrier boards.

Every skill is a self-contained directory with a `SKILL.md` instruction document, helper
scripts, reference material, and eval test cases. Claude Code reads `CLAUDE.md` first, then
reads the relevant `SKILL.md` before taking any action.

---

## 4-Phase Workflow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         imx95-bsp-skills WORKFLOW                               │
├──────────────┬──────────────────┬──────────────────┬───────────────────────────┤
│  PHASE 1     │  PHASE 2         │  PHASE 3         │  PHASE 4                  │
│  SETUP       │  CUSTOMIZE       │  BUILD           │  DEPLOY                   │
├──────────────┼──────────────────┼──────────────────┼───────────────────────────┤
│              │                  │                  │                           │
│ init-target  │ derive-carrier   │ build-source     │ promote-image             │
│     │        │      │           │      │           │      │                    │
│ download-bsp │ customize-pinmux │  (bitbake)       │ flash-image               │
│     │        │      │           │      │           │      │                    │
│ init-source  │ customize-usb    │  artifacts in    │ validate-image            │
│     │        │      │           │  tmp/deploy/     │                           │
│ print-bsp-   │ customize-camera │                  │  board boots ✓            │
│   info       │      │           │                  │                           │
│              │ customize-clocks │                  │                           │
│              │      │           │                  │                           │
│              │ optimize-memory  │                  │                           │
│              │                  │                  │                           │
│  ~30-60 min  │  minutes–hours   │  2–4 hrs (first) │  ~10 min                  │
│  (BSP sync)  │  per change      │  ~20 min (incr.) │                           │
└──────────────┴──────────────────┴──────────────────┴───────────────────────────┘
                        ↑ overlay-tracker git commit-gate ↑
                  (every DT change committed + user-approved before build)
```

---

## Skill List

### Setup Skills

| Skill | Purpose | Invoke when... |
|---|---|---|
| `imx95-quick-start` | Guided first-time setup | "help me set up the BSP", "first time" |
| `imx95-init-target` | Create target profile YAML | "create a new target", "add board profile" |
| `imx95-set-target` | Switch active target | "switch to target X", "change active board" |
| `imx95-download-bsp` | `repo init` + `repo sync` NXP BSP | "download the BSP", "repo sync" |
| `imx95-init-source` | Source `oe-init-build-env`, init overlay-tracker | "source the environment", "init build env" |
| `imx95-print-bsp-info` | Print workspace state summary | "what's the current state?", "show BSP info" |

### Customize Skills

| Skill | Purpose | Invoke when... |
|---|---|---|
| `imx95-derive-carrier` | Fork FRDM DT into custom carrier overlay | "create custom carrier", "fork device tree" |
| `imx95-customize-pinmux` | IOMUX/pinmux DT overlay edits | "change pinmux", "configure IOMUX", "set pin function" |
| `imx95-customize-usb` | USB3 OTG / USB2 host DT config | "configure USB", "enable USB3", "USB OTG" |
| `imx95-customize-camera` | MIPI-CSI camera pipeline DT config | "add camera", "MIPI CSI", "configure sensor" |
| `imx95-customize-clocks` | Clock tree DT modifications | "change clock", "set clock frequency" |
| `imx95-optimize-memory` | CMA / DMA-BUF pool tuning | "tune CMA", "resize DMA buffer", "memory pool" |

### Build / Deploy Skills

| Skill | Purpose | Invoke when... |
|---|---|---|
| `imx95-build-source` | `bitbake` build with pre-flight checks | "build the image", "run bitbake" |
| `imx95-promote-image` | Stage artifacts for `uuu` flashing | "stage artifacts", "prepare for flash" |
| `imx95-flash-image` | Flash via `uuu` with safety gates | "flash the board", "program eMMC" |
| `imx95-validate-image` | Post-flash validation checklist | "validate the image", "check the board" |

---

## Prerequisites

Install on the host machine before running `setup.sh`:

```bash
# Ubuntu 22.04 / 24.04 (recommended)
sudo apt-get update
sudo apt-get install -y \
    git curl wget python3 python3-pip \
    gawk diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    libegl1-mesa libsdl1.2-dev xterm python3-subunit mesa-common-dev \
    zstd liblz4-tool file locales libacl1 \
    device-tree-compiler

# uuu — Universal Update Utility (minimum v1.5.21)
# Download from: https://github.com/nxp-imx/mfgtools/releases
sudo install -m 755 uuu /usr/local/bin/uuu

# repo tool
mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

**Required host tools:** `repo`, `bitbake`, `uuu`, `dtc`, `fdtdump`, `git`, `python3`

---

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/<org>/imx95-bsp-skills.git
cd imx95-bsp-skills

# 2. Install into your BSP workspace
./setup.sh --workspace ~/imx95-workspace

# 3. Start Claude Code from the workspace
cd ~/imx95-workspace
claude

# 4. First prompt
# "help me set up the i.MX 95 BSP workspace for the FRDM-IMX95 EVK"
```

Claude Code will invoke `imx95-quick-start` and guide you through the entire setup.

---

## Platform Facts

| Item | Value |
|---|---|
| Primary board | NXP FRDM-IMX95 EVK |
| SoC | i.MX 95 (Cortex-A55 + Cortex-M7 + NPU) |
| BSP | NXP Yocto Linux BSP (meta-imx, Scarthgap) |
| Kernel | 6.6.x LTS |
| Manifest | `imx-manifest` → `imx-linux-scarthgap` → `imx-6.6.52-2.2.0.xml` |
| Build system | Yocto / bitbake |
| Flash tool | `uuu` (Universal Update Utility) — **NOT** `flash.sh` |
| MACHINE | `imx95-19x19-lpddr5-evk` or `imx95frdm` |
| Default image | `imx-image-full` |

---

## Safety Highlights

- **Flash gate:** Claude Code will never run `uuu` without displaying a full confirmation
  prompt and receiving the exact string `"flash confirmed"` from the user.
- **Commit gate:** Every `git commit` in the overlay-tracker requires showing the complete
  diff and receiving explicit user approval.
- **No upstream edits:** `sources/meta-imx/`, `sources/meta-freescale/`, and `sources/poky/`
  are never modified directly. All customizations go in `meta-imx95-custom/`.
- **Overlay-tracker:** All DT changes are tracked in a dedicated git repo before building.

See `CLAUDE.md` Section 10 for the full safety rules.

---

## Repository Layout

```
imx95-bsp-skills/
├── CLAUDE.md                        ← Primary Claude Code ingestion document
├── README.md                        ← This file
├── LICENSE                          ← Apache 2.0
├── setup.sh                         ← Bootstrap installer
├── .gitignore
├── context/                         ← Shared context docs
│   ├── bsp-customization-workflow.md
│   ├── target-platform-contract.md
│   └── bsp-customization-software-layers.md
├── references/                      ← Shared reference material
│   ├── platform_template.yaml
│   ├── active_target_template.yaml
│   ├── bsp-platforms-catalogue.md
│   ├── bsp-customization-iomux-dt.md
│   ├── bsp-customization-kernel-dtb.md
│   └── bsp-customization-io-devices.md
└── skills/
    ├── imx95-quick-start/
    ├── imx95-init-target/
    ├── imx95-set-target/
    ├── imx95-download-bsp/
    ├── imx95-init-source/
    ├── imx95-print-bsp-info/
    ├── imx95-derive-carrier/
    ├── imx95-customize-pinmux/
    ├── imx95-customize-usb/
    ├── imx95-customize-camera/
    ├── imx95-customize-clocks/
    ├── imx95-optimize-memory/
    ├── imx95-build-source/
    ├── imx95-promote-image/
    ├── imx95-flash-image/
    └── imx95-validate-image/
```

---

## License

Code (scripts, tools): Apache 2.0 — see `LICENSE`
Documentation (`.md` files): CC-BY-4.0

---

## Official NXP Resources

- [i.MX 95 Linux BSP](https://www.nxp.com/design/software/embedded-software/i-mx-software/embedded-linux-for-i-mx-applications-processors:IMXLINUX)
- [i.MX 95 Reference Manual](https://www.nxp.com/products/processors-and-microcontrollers/arm-processors/i-mx-applications-processors/i-mx-9-processors/i-mx-95-applications-processor-family:iMX95)
- [meta-imx](https://github.com/nxp-imx/meta-imx)
- [imx-manifest](https://github.com/nxp-imx/imx-manifest)
- [uuu / mfgtools](https://github.com/nxp-imx/mfgtools)
