# CLAUDE.md — imx95-bsp-skills

> **Primary ingestion document for Claude Code.**
> Read this file completely before taking any action in this workspace.
> Every skill, safety rule, and workflow decision in this repo flows from this document.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [How Skills Work](#3-how-skills-work)
4. [Repository Layout](#4-repository-layout)
5. [Bootstrap — setup.sh](#5-bootstrap--setupsh)
6. [Target Profile YAML Schema](#6-target-profile-yaml-schema)
7. [Overlay-Tracker Git Pattern](#7-overlay-tracker-git-pattern)
8. [Commit-Gate Rule](#8-commit-gate-rule)
9. [Skills Reference](#9-skills-reference)
   - [Setup Skills](#91-setup-skills)
   - [Customize Skills](#92-customize-skills)
   - [Build / Deploy Skills](#93-build--deploy-skills)
10. [Safety Rules](#10-safety-rules)
11. [Platform-Specific Gotchas](#11-platform-specific-gotchas)
12. [Running Evals](#12-running-evals)
13. [Adding a New Skill](#13-adding-a-new-skill)
14. [Quick Start](#14-quick-start)

---

## 1. Project Overview

`imx95-bsp-skills` is an **AgentSkills.io-convention skill bundle** that runs entirely on the
**developer's host machine** (laptop or workstation). It does not run on the FRDM-IMX95 EVK or
any other i.MX 95 board. The skills guide Claude Code through the four-phase NXP Yocto BSP
workflow — Setup, Customize, Build, and Deploy — for the NXP i.MX 95 SoC family.

The primary target is the **NXP FRDM-IMX95 EVK** (Freedom development board for i.MX 95,
19×19 mm package, LPDDR5). The skill set is designed to be extensible to custom i.MX 95 carrier
boards by using the `imx95-derive-carrier` skill to fork the FRDM reference device tree into a
custom overlay tree. All BSP customization is done through **Yocto bbappend recipes and kernel
device tree overlays** — the upstream NXP BSP layers (`meta-imx`, `meta-freescale`, Poky) are
never modified directly.

The BSP itself is the **NXP Yocto Linux BSP** sourced via the `imx-manifest` repo tool manifest
(https://github.com/nxp-imx/imx-manifest). It uses `bitbake` as the build system, kernel 6.6.x
LTS, and `uuu` (Universal Update Utility) as the flash tool. There is no `flash.sh`, no L4T, no
Tegra BCT, and no NVIDIA-specific tooling in this repo. If you see references to those tools,
stop and re-read this document — you are in the wrong skill bundle.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DEVELOPER HOST MACHINE                           │
│                                                                         │
│  ┌──────────────┐     reads      ┌─────────────────────────────────┐   │
│  │  Claude Code │ ─────────────► │  imx95-bsp-skills/              │   │
│  │  (AI agent)  │                │  CLAUDE.md  ← you are here      │   │
│  └──────┬───────┘                │  skills/imx95-*/SKILL.md        │   │
│         │ invokes                │  references/  context/          │   │
│         ▼                        └─────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    BSP WORKSPACE  (~/<workspace>/)               │  │
│  │                                                                  │  │
│  │  .repo/                  ← repo tool manifest checkout           │  │
│  │  sources/                                                        │  │
│  │    meta-imx/             ← NXP i.MX Yocto layer (READ-ONLY)     │  │
│  │    meta-freescale/       ← Freescale community layer (READ-ONLY) │  │
│  │    poky/                 ← Yocto Project Poky (READ-ONLY)        │  │
│  │    meta-imx95-custom/    ← YOUR custom layer (bbappend/overlays) │  │
│  │  build/                                                          │  │
│  │    conf/local.conf       ← MACHINE, IMAGE_INSTALL, etc.         │  │
│  │    conf/bblayers.conf    ← layer stack                          │  │
│  │    tmp/deploy/images/    ← build artifacts                      │  │
│  │  overlay-tracker/        ← git repo tracking DT overlay changes  │  │
│  │  targets/                ← target profile YAMLs                 │  │
│  │    active_target.yaml    ← symlink to current target            │  │
│  └──────────────────────────────┬───────────────────────────────────┘  │
│                                 │                                       │
│  ┌──────────────────────────────▼───────────────────────────────────┐  │
│  │                    HOST TOOLS                                    │  │
│  │  repo   bitbake   devtool   dtc   fdtdump   git   python3   uuu  │  │
│  └──────────────────────────────┬───────────────────────────────────┘  │
│                                 │  USB (uuu flash protocol)            │
└─────────────────────────────────┼───────────────────────────────────────┘
                                  │
                    ┌─────────────▼──────────────┐
                    │   FRDM-IMX95 EVK / Custom  │
                    │   i.MX 95 Board            │
                    │                            │
                    │   eMMC / SD card           │
                    │   U-Boot + kernel + rootfs │
                    │   imx95-19x19-lpddr5-evk   │
                    │   (or imx95frdm)           │
                    └────────────────────────────┘
```

**Key principle:** Claude Code operates exclusively on the host. It never SSH-es into the board
during build or flash phases. Post-flash validation (`imx95-validate-image`) may use a serial
console or SSH connection to the board, but only after the user confirms the board has booted.

---

## 3. How Skills Work

### AgentSkills Convention

Each skill is a self-contained directory under `skills/` with a fixed internal layout:

```
skills/<skill-name>/
├── SKILL.md          ← Primary instruction document (Claude reads this first)
├── BENCHMARK.md      ← Eval benchmark definition and pass/fail criteria
├── evals/
│   └── evals.json    ← Structured eval test cases
├── references/       ← Supporting reference documents, templates, gotchas
│   ├── procedure.md  ← Step-by-step procedure (detailed)
│   ├── gotchas.md    ← Known failure modes and workarounds
│   └── *.md / *.dts.tmpl / *.yaml  ← Other reference material
├── scripts/          ← Helper Python/shell scripts (optional)
│   └── *.py / *.sh
└── skill-card.md     ← One-page human-readable summary card
```

### How Claude Code Invokes a Skill

1. The user asks for a BSP operation (e.g., "set up the BSP workspace", "add a MIPI camera").
2. Claude Code reads `CLAUDE.md` (this file) to identify the correct skill name.
3. Claude Code reads `skills/<skill-name>/SKILL.md` **completely** before taking any action.
4. Claude Code follows the SKILL.md procedure step by step, reading referenced files in
   `references/` as directed.
5. At every **STOP checkpoint**, Claude Code presents its plan or diff to the user and waits
   for explicit approval before proceeding.
6. Scripts in `scripts/` are executed by Claude Code on the host using the shell; they are
   never run on the board.

### Skill Invocation Triggers

Skills are triggered by natural-language requests. The table in
[Section 9](#9-skills-reference) maps common user phrases to skill names. When in doubt,
run `imx95-print-bsp-info` first to understand the current workspace state.

### Progressive Disclosure

SKILL.md files use **progressive disclosure**: the top of each SKILL.md contains a quick
decision tree and the most common path. Detailed procedures, edge cases, and gotchas are in
`references/procedure.md` and `references/gotchas.md`. Claude Code reads the full SKILL.md
before starting, then reads referenced files only when the procedure directs it to.

---

## 4. Repository Layout

```
imx95-bsp-skills/
│
├── CLAUDE.md                          ← THIS FILE — read first, always
├── README.md                          ← Human-facing project overview
├── LICENSE                            ← Apache-2.0 (code) / CC-BY-4.0 (docs)
├── setup.sh                           ← Bootstrap installer
│
├── context/                           ← Shared context documents (all skills may reference)
│   ├── bsp-workflow.md                ← End-to-end BSP workflow narrative
│   ├── yocto-layer-model.md           ← How meta-imx / meta-freescale / custom layer relate
│   ├── imx95-dt-architecture.md       ← i.MX 95 device tree structure and IOMUX model
│   └── target-profile-contract.md     ← Formal spec of the target profile YAML
│
├── references/                        ← Top-level shared references
│   ├── active_target_template.yaml    ← Template for active_target.yaml
│   ├── platform_template.yaml         ← Full target profile template with all fields
│   ├── imx95-machines.md              ← Supported MACHINE values and their meanings
│   ├── uuu-scripts/                   ← Reference uuu script templates
│   │   ├── frdm-imx95-emmc.uuu        ← Flash eMMC on FRDM-IMX95
│   │   ├── frdm-imx95-sd.uuu          ← Flash SD card on FRDM-IMX95
│   │   └── custom-board.uuu.tmpl      ← Template for custom board uuu scripts
│   └── bsp-platforms-catalogue.md     ← Known i.MX 95 board variants and MACHINE names
│
├── skills/
│   │
│   ├── imx95-quick-start/             ← Guided first-time setup entry point
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   └── skill-card.md
│   │
│   ├── imx95-init-target/             ← Create new target profile YAML
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── gotchas.md
│   │   │   └── ui-samples.md
│   │   └── skill-card.md
│   │
│   ├── imx95-set-target/              ← Switch active target
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   └── skill-card.md
│   │
│   ├── imx95-download-bsp/            ← repo init + sync NXP BSP manifest
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── manifest-tags.md
│   │   │   └── proxy-gotchas.md
│   │   └── skill-card.md
│   │
│   ├── imx95-init-image/              ← Configure image recipe
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   └── image-recipes.md
│   │   └── skill-card.md
│   │
│   ├── imx95-init-source/             ← Source oe-init-build-env, init overlay-tracker
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   └── bblayers-setup.md
│   │   └── skill-card.md
│   │
│   ├── imx95-print-bsp-info/          ← Print workspace state summary
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   └── skill-card.md
│   │
│   ├── imx95-derive-carrier/          ← Fork FRDM DT into custom carrier overlay
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── procedure.md
│   │   │   └── overlay-structure.md
│   │   └── skill-card.md
│   │
│   ├── imx95-customize-pinmux/        ← IOMUX/pinmux DT overlay edits
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── procedure.md
│   │   │   ├── iomux-bindings.md
│   │   │   └── gotchas.md
│   │   ├── scripts/
│   │   │   └── validate_iomux.py
│   │   └── skill-card.md
│   │
│   ├── imx95-customize-usb/           ← USB3 OTG / USB2 host DT config
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── procedure.md
│   │   │   ├── usb-architecture.md
│   │   │   └── gotchas.md
│   │   └── skill-card.md
│   │
│   ├── imx95-customize-pcie/          ← PCIe lane DT config
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── procedure.md
│   │   │   └── gotchas.md
│   │   └── skill-card.md
│   │
│   ├── imx95-customize-camera/        ← MIPI-CSI camera pipeline DT config
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── procedure.md
│   │   │   ├── csi-dt-bindings.md
│   │   │   └── camera-overlay-templates/
│   │   │       ├── mipi-csi2-single.dts.tmpl
│   │   │       └── mipi-csi2-dual.dts.tmpl
│   │   └── skill-card.md
│   │
│   ├── imx95-customize-clocks/        ← Clock tree DT modifications
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── procedure.md
│   │   │   └── clock-control-model.md
│   │   └── skill-card.md
│   │
│   ├── imx95-customize-power/         ← Power domains and regulators DT config
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── procedure.md
│   │   │   └── power-domain-model.md
│   │   └── skill-card.md
│   │
│   ├── imx95-optimize-memory/         ← CMA / DMA-BUF pool tuning
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   └── reserved-memory.md
│   │   └── skill-card.md
│   │
│   ├── imx95-build-source/            ← bitbake build with change tracking
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── build-modes.md
│   │   │   └── long-tail-gotchas.md
│   │   └── skill-card.md
│   │
│   ├── imx95-promote-image/           ← Stage artifacts for flashing
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   └── artifact-manifest.md
│   │   └── skill-card.md
│   │
│   ├── imx95-flash-image/             ← Flash via uuu with pre-flight checks
│   │   ├── SKILL.md
│   │   ├── BENCHMARK.md
│   │   ├── evals/evals.json
│   │   ├── references/
│   │   │   ├── recovery-mode.md
│   │   │   ├── uuu-command-reference.md
│   │   │   └── gotchas.md
│   │   └── skill-card.md
│   │
│   └── imx95-validate-image/          ← Post-flash validation checklist
│       ├── SKILL.md
│       ├── BENCHMARK.md
│       ├── evals/evals.json
│       ├── references/
│       │   └── validation-checklist.md
│       └── skill-card.md
│
└── .gitignore
```

---

## 5. Bootstrap — setup.sh

`setup.sh` installs the skill bundle into a BSP workspace directory. It does **not** download
the BSP itself — that is done by `imx95-download-bsp`.

### Usage

```bash
git clone https://github.com/<org>/imx95-bsp-skills.git
cd imx95-bsp-skills
./setup.sh --workspace ~/imx95-workspace
```

### What setup.sh Does

1. Creates `<workspace>/` if it does not exist.
2. Copies `CLAUDE.md` into `<workspace>/CLAUDE.md` (so Claude Code finds it at startup).
3. Copies `skills/`, `context/`, and `references/` into `<workspace>/.imx95-skills/`.
4. Creates `<workspace>/targets/` directory.
5. Creates `<workspace>/overlay-tracker/` as an empty git repository.
6. Writes `<workspace>/.imx95-skills/VERSION` with the skill bundle version and git SHA.
7. Prints a "Next steps" message directing the user to start Claude Code from `<workspace>/`.

### Starting Claude Code After Bootstrap

```bash
cd ~/imx95-workspace
claude
```

Then say: **"help me set up the i.MX 95 BSP workspace"**

This triggers `imx95-quick-start`, the recommended entry point for all new users.

---

## 6. Target Profile YAML Schema

Every board variant is described by a **target profile YAML** stored in `targets/`. The active
target is always `targets/active_target.yaml` (a symlink or copy). Skills read this file to
know which board, MACHINE, image recipe, and uuu script to use.

### Full Schema

```yaml
# Target profile for imx95-bsp-skills
# Generated by imx95-init-target — edit with care.
# Schema version: 1.0

schema_version: "1.0"

# ── Identity ──────────────────────────────────────────────────────────────────
profile_name: "frdm-imx95-base"          # Short slug, no spaces (used in paths)
description:  "FRDM-IMX95 EVK, eMMC boot, imx-image-full"

# ── Board ─────────────────────────────────────────────────────────────────────
board:
  name:        "FRDM-IMX95"              # Human-readable board name
  variant:     "19x19-lpddr5-evk"        # Board variant string
  soc:         "imx95"                   # SoC family
  boot_device: "emmc"                    # emmc | sd | flexspi
  custom_carrier: false                  # true if using imx95-derive-carrier

# ── Yocto Build ───────────────────────────────────────────────────────────────
yocto:
  machine:       "imx95-19x19-lpddr5-evk"  # MACHINE= value for bitbake
  # Alternate FRDM machine name:
  # machine:     "imx95frdm"
  image_recipe:  "imx-image-full"           # bitbake target image recipe
  # Common alternatives:
  #   core-image-base        — minimal console image
  #   imx-image-multimedia   — multimedia stack
  #   imx-image-full         — full NXP demo image (default for FRDM)
  distro:        "fsl-imx-xwayland"         # Yocto DISTRO
  # Alternatives: fsl-imx-wayland | fsl-imx-fb | fsl-imx-xwayland
  bsp_manifest_url:   "https://github.com/nxp-imx/imx-manifest"
  bsp_manifest_branch: "imx-linux-scarthgap"   # Yocto release branch
  bsp_manifest_file:   "imx-6.6.52-2.2.0.xml"  # Pinned manifest XML

# ── Paths ─────────────────────────────────────────────────────────────────────
paths:
  workspace_root:   "~/imx95-workspace"    # Absolute or ~ path
  bsp_sources:      "sources"              # Relative to workspace_root
  build_dir:        "build"                # Relative to workspace_root
  custom_layer:     "sources/meta-imx95-custom"  # Your bbappend/overlay layer
  dt_overlay_dir:   "sources/meta-imx95-custom/recipes-kernel/linux/files/overlays"
  overlay_tracker:  "overlay-tracker"      # git repo tracking DT changes
  deploy_dir:       "build/tmp/deploy/images/imx95-19x19-lpddr5-evk"
  staging_dir:      "staging"              # Promoted artifacts ready for uuu

# ── Flash / Deploy ────────────────────────────────────────────────────────────
flash:
  tool:        "uuu"                       # ALWAYS uuu for i.MX 95 — never flash.sh
  uuu_script:  "references/uuu-scripts/frdm-imx95-emmc.uuu"
  # Path relative to workspace_root, or absolute.
  # For custom boards, point to your own .uuu script.
  uuu_version_min: "1.5.21"               # Minimum uuu version required
  recovery_mode_jumper: "J301"            # Board-specific recovery jumper label
  usb_vid_pid:  "1fc9:0146"              # i.MX 95 ROM USB VID:PID in recovery

# ── Device Tree ───────────────────────────────────────────────────────────────
device_tree:
  base_dts:    "imx95-19x19-lpddr5-evk.dts"   # Base DTS in kernel source
  # For FRDM: "imx95-15x15-evk.dts" or "imx95frdm.dts"
  overlay_prefix: "imx95-custom"               # Prefix for generated overlay files
  kernel_dt_path: "sources/linux-imx/arch/arm64/boot/dts/freescale/"

# ── Custom Carrier (populated by imx95-derive-carrier if custom_carrier=true) ─
custom_carrier:
  carrier_name:   null                    # e.g. "acme-carrier-v1"
  base_overlay:   null                    # e.g. "imx95-acme-carrier.dts"
  schematic_pdf:  null                    # Path to carrier schematic PDF

# ── Notes ─────────────────────────────────────────────────────────────────────
notes: |
  Created by imx95-init-target.
  Modify flash.uuu_script for custom boot media.
  Set custom_carrier: true and run imx95-derive-carrier for custom boards.
```

### Active Target Pointer

```bash
# The active target is always read from:
targets/active_target.yaml

# Switch targets with imx95-set-target, which updates this symlink:
ln -sf targets/frdm-imx95-base.yaml targets/active_target.yaml
```

---

## 7. Overlay-Tracker Git Pattern

All device tree overlay changes are tracked in a dedicated git repository at
`<workspace>/overlay-tracker/`. This is separate from the BSP source tree and provides a clean
audit trail of every DT modification made by the skills.

### Why a Separate Repo?

The BSP source tree (`sources/`) is managed by `repo` and should not have ad-hoc commits.
The `overlay-tracker/` repo tracks only the files in `dt_overlay_dir` (and any bbappend
recipes that reference them), giving a focused, reviewable history of customizations.

### Initialization (done by imx95-init-source)

```bash
cd <workspace>/overlay-tracker
git init
git commit --allow-empty -m "init: overlay tracker for <profile_name>"
```

### Commit Pattern (enforced by all customize skills)

Every time a customize skill modifies a DT overlay file, it MUST:

1. Stage the changed files:
   ```bash
   cd <workspace>/overlay-tracker
   git add <overlay-file>.dts [<bbappend-file>.bbappend]
   ```

2. Show the diff to the user (**STOP — wait for approval**):
   ```bash
   git diff --staged
   ```

3. After user approval, commit with a structured message:
   ```
   customize(<subsystem>): <one-line summary>

   Board: <profile_name>
   Skill: imx95-customize-<subsystem>
   Files: <list of changed files>

   <Description of what was changed and why>

   Tested: <pending | passed | not-applicable>
   ```

4. Example:
   ```
   customize(pinmux): enable UART4 on PAD_GPIO_IO04/05

   Board: frdm-imx95-base
   Skill: imx95-customize-pinmux
   Files: imx95-custom-pinmux.dts

   Configured PAD_GPIO_IO04 as UART4_TX and PAD_GPIO_IO05 as UART4_RX
   with pull-up enabled. Required for RS-485 expansion header.

   Tested: pending
   ```

### Pre-Build Gate

`imx95-build-source` checks that the overlay-tracker working tree is **clean** (no uncommitted
changes) before starting a bitbake build. If there are uncommitted changes, the build is
blocked until the user either commits them (via the commit-gate rule) or explicitly discards
them.

---

## 8. Commit-Gate Rule

> **MANDATORY — Claude Code MUST follow this rule without exception.**

**Before any `git commit` in the overlay-tracker (or in any other repo in this workspace),
Claude Code MUST:**

1. Run `git diff --staged` (or `git diff HEAD` for already-staged changes).
2. Display the **complete diff output** in the conversation — do not summarize or truncate it.
3. State clearly: *"Here is the complete diff. Please review and reply 'approve' to commit,
   or tell me what to change."*
4. **WAIT** for the user to reply with explicit approval (e.g., "approve", "looks good",
   "commit it", "yes").
5. Only after receiving explicit approval: run `git commit`.

**Claude Code MUST NOT:**
- Auto-commit without showing the diff.
- Commit after a vague acknowledgment ("ok", "sure", "continue") that does not clearly
  approve the specific diff shown.
- Batch multiple overlay changes into a single commit without showing each change.
- Amend a previous commit without showing the amended diff and getting fresh approval.

This rule applies to ALL git commits in this workspace, including:
- `overlay-tracker/` commits
- `meta-imx95-custom/` layer commits
- Any other repo touched during the workflow

---

## 9. Skills Reference

### Skill Invocation Quick-Reference

| User says... | Skill to invoke |
|---|---|
| "help me set up the BSP" / "first time setup" | `imx95-quick-start` |
| "create a new target" / "add board profile" | `imx95-init-target` |
| "switch to target X" / "change active board" | `imx95-set-target` |
| "download the BSP" / "repo sync" / "get NXP sources" | `imx95-download-bsp` |
| "configure the image" / "change image recipe" | `imx95-init-image` |
| "source the environment" / "init build env" | `imx95-init-source` |
| "what's the current state?" / "show BSP info" | `imx95-print-bsp-info` |
| "create custom carrier" / "fork the device tree" | `imx95-derive-carrier` |
| "change pinmux" / "configure IOMUX" / "set pin function" | `imx95-customize-pinmux` |
| "configure USB" / "enable USB3" / "USB OTG" | `imx95-customize-usb` |
| "configure PCIe" / "enable PCIe lane" | `imx95-customize-pcie` |
| "add camera" / "MIPI CSI" / "configure sensor" | `imx95-customize-camera` |
| "change clock" / "set clock frequency" | `imx95-customize-clocks` |
| "configure power domain" / "add regulator" | `imx95-customize-power` |
| "tune CMA" / "resize DMA buffer" / "memory pool" | `imx95-optimize-memory` |
| "build the image" / "run bitbake" | `imx95-build-source` |
| "stage artifacts" / "prepare for flash" | `imx95-promote-image` |
| "flash the board" / "program eMMC" / "uuu" | `imx95-flash-image` |
| "validate the image" / "check the board" | `imx95-validate-image` |

---

### 9.1 Setup Skills

---

#### `imx95-quick-start`

**Purpose:** Guided first-time setup — walks the user from zero to a flashed board in one
conversation. Asks the core questions (board variant, BSP release, custom carrier yes/no,
image recipe) and dispatches the correct setup skill chain.

**When to invoke:** Any time a user says "help me set up", "I'm new to this", "start from
scratch", or "first time". This is the recommended entry point for all new users.

**Procedure summary:**
1. Ask: FRDM-IMX95 EVK or custom board?
2. Ask: BSP release / manifest tag (default: latest `imx-linux-scarthgap`).
3. Ask: image recipe (default: `imx-image-full`).
4. Ask: boot device (eMMC or SD).
5. Ask: custom carrier board? (yes → will run `imx95-derive-carrier` after setup).
6. Dispatch: `imx95-init-target` → `imx95-download-bsp` → `imx95-init-image` →
   `imx95-init-source` → (optionally) `imx95-derive-carrier`.
7. Print final workspace summary via `imx95-print-bsp-info`.

**Key files touched:**
- `targets/<profile_name>.yaml` (created)
- `targets/active_target.yaml` (symlink set)
- `.repo/` (created by repo init)
- `build/conf/local.conf`, `build/conf/bblayers.conf`

---

#### `imx95-init-target`

**Purpose:** Create a new target profile YAML for a board variant and write it to
`targets/<profile_name>.yaml`. Updates `targets/active_target.yaml` to point to the new
profile.

**When to invoke:** When adding a new board variant (e.g., switching from FRDM-IMX95 to a
custom carrier, or adding a second target with a different image recipe).

**Key questions asked:**
- Board name and variant
- MACHINE value (see `references/imx95-machines.md` for valid values)
- Image recipe
- Boot device (eMMC / SD)
- Custom carrier? (if yes, `custom_carrier: true` is set and `imx95-derive-carrier` is
  recommended next)

**Key files touched:**
- `targets/<profile_name>.yaml` (written)
- `targets/active_target.yaml` (updated)

**STOP checkpoint:** Show the complete generated YAML to the user before writing it to disk.

---

#### `imx95-set-target`

**Purpose:** Switch the active target to an existing profile in `targets/`. Lists available
profiles and updates `targets/active_target.yaml`.

**When to invoke:** When the user wants to switch between multiple board profiles in the same
workspace (e.g., from `frdm-imx95-base` to `acme-carrier-v1`).

**Key commands:**
```bash
ls targets/*.yaml                          # List available profiles
ln -sf targets/<profile>.yaml targets/active_target.yaml
```

**Key files touched:** `targets/active_target.yaml`

---

#### `imx95-download-bsp`

**Purpose:** Initialize and sync the NXP Yocto BSP using the Google `repo` tool and the
`imx-manifest` manifest. Downloads all BSP layers into `sources/`.

**When to invoke:** On first setup, or when the user wants to update to a new BSP release.

**Key commands:**
```bash
# Install repo tool if not present
mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo

# Initialize workspace
cd <workspace_root>
repo init \
  -u https://github.com/nxp-imx/imx-manifest \
  -b <bsp_manifest_branch> \
  -m <bsp_manifest_file>

# Sync (this downloads ~10–20 GB; may take 30–60 minutes)
repo sync -j$(nproc)
```

**Key files touched:**
- `.repo/` (created)
- `sources/meta-imx/`
- `sources/meta-freescale/`
- `sources/poky/`
- `sources/linux-imx/`
- `sources/u-boot-imx/`
- (and other layers per manifest)

**Gotchas:**
- Requires `git`, `repo`, `curl`, `python3` on PATH.
- Corporate proxies: set `http_proxy` / `https_proxy` before running.
- See `references/proxy-gotchas.md` for proxy configuration.
- `repo sync` may fail on first run due to network timeouts — retry with `repo sync -j4`.

---

#### `imx95-init-image`

**Purpose:** Configure the Yocto image recipe in `build/conf/local.conf`. Sets `MACHINE`,
`DISTRO`, and `IMAGE_INSTALL` additions. Creates the custom layer `meta-imx95-custom` if it
does not exist.

**When to invoke:** After `imx95-download-bsp`, or when changing the image recipe or DISTRO.

**Key commands:**
```bash
# Source the Yocto environment (creates build/ if needed)
cd <workspace_root>/sources/poky
MACHINE=<machine> source oe-init-build-env ../../build

# The skill then edits build/conf/local.conf and build/conf/bblayers.conf
```

**Image recipe options** (from `references/image-recipes.md`):

| Recipe | Description | Typical use |
|---|---|---|
| `core-image-base` | Minimal console image, no GUI | Bring-up, CI |
| `imx-image-multimedia` | Multimedia stack (GStreamer, VPU) | Media applications |
| `imx-image-full` | Full NXP demo image with Weston/Wayland | Default for FRDM EVK |
| `<custom-image>` | User-defined image recipe in meta-imx95-custom | Production |

**Key files touched:**
- `build/conf/local.conf`
- `build/conf/bblayers.conf`
- `sources/meta-imx95-custom/` (created if absent)

---

#### `imx95-init-source`

**Purpose:** Source the Yocto build environment (`oe-init-build-env`), verify the layer stack,
initialize the `overlay-tracker` git repo, and confirm the workspace is ready for
customization or build.

**When to invoke:** At the start of any new shell session before running `bitbake`, or after
`imx95-init-image` on first setup.

**Key commands:**
```bash
cd <workspace_root>/sources/poky
MACHINE=<machine> source oe-init-build-env ../../build

# Verify layers
bitbake-layers show-layers

# Verify MACHINE
grep '^MACHINE' ../../build/conf/local.conf

# Initialize overlay-tracker if not already done
cd <workspace_root>/overlay-tracker
git init 2>/dev/null || true
git log --oneline -1 2>/dev/null || git commit --allow-empty -m "init: overlay tracker"
```

**Key files touched:**
- `build/conf/` (verified, not modified)
- `overlay-tracker/` (initialized)

---

#### `imx95-print-bsp-info`

**Purpose:** Print a concise host-side summary of the current workspace state. No files are
modified. Safe to run at any time.

**When to invoke:** Any time the user asks "what's the current state?", before starting a
build, or when debugging a workspace issue.

**Output includes:**
- Active target profile name and board
- MACHINE, DISTRO, image recipe
- BSP manifest branch and file
- Layer stack (`bitbake-layers show-layers`)
- overlay-tracker git log (last 5 commits)
- Build artifacts present in `deploy_dir` (if any)
- `uuu` version on PATH
- Disk space available in workspace

---

### 9.2 Customize Skills

> **Golden rules for all customize skills:**
> 1. NEVER modify files in `sources/meta-imx/`, `sources/meta-freescale/`, or `sources/poky/`
>    directly. Always use bbappend recipes in `sources/meta-imx95-custom/`.
> 2. NEVER modify the base kernel DTS files in `sources/linux-imx/arch/arm64/boot/dts/freescale/`
>    directly. Always create or modify overlay files in `dt_overlay_dir`.
> 3. Every DT change MUST be committed to `overlay-tracker/` before building
>    (see [Section 7](#7-overlay-tracker-git-pattern)).
> 4. The commit-gate rule ([Section 8](#8-commit-gate-rule)) applies to every commit.
> 5. Ask the user for hardware details (schematic, pin assignments) — never assume.

---

#### `imx95-derive-carrier`

**Purpose:** Create a custom carrier board device tree overlay by forking the FRDM-IMX95 base
DTS. Scaffolds the overlay directory structure, creates the initial `.dts` file with the
correct `#include` of the base DTS, and registers the overlay in the bbappend recipe.

**When to invoke:** When the user has a custom carrier board (not the stock FRDM-IMX95 EVK)
and needs to start customizing hardware-specific DT nodes.

**Key questions asked:**
- Carrier board name (used as overlay file prefix)
- Which FRDM-IMX95 base DTS to fork from
- Does the carrier reuse the FRDM SOM, or is it a fully custom board?

**Key files created:**
```
sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/
  imx95-<carrier-name>.dts          ← Main carrier overlay
  imx95-<carrier-name>-pinmux.dts   ← Pinmux sub-overlay (included by main)

sources/meta-imx95-custom/recipes-kernel/linux/
  linux-imx_%.bbappend              ← Registers overlays with kernel recipe
```

**Overlay file template:**
```dts
// SPDX-License-Identifier: GPL-2.0+
/*
 * Copyright <YEAR> <Company>
 * Custom carrier board overlay for i.MX 95
 * Base: imx95-19x19-lpddr5-evk.dts
 */

/dts-v1/;
/plugin/;

#include "imx95-19x19-lpddr5-evk.dts"

/ {
    model = "NXP i.MX95 <Carrier Name>";
    compatible = "nxp,imx95-<carrier>", "nxp,imx95";
};

/* Add carrier-specific node overrides below */
```

**STOP checkpoint:** Show the complete generated overlay file and bbappend before writing.

---

#### `imx95-customize-pinmux`

**Purpose:** Modify IOMUX/pinmux configuration in the device tree overlay. Handles pad
function selection, drive strength, pull-up/pull-down, slew rate, and open-drain settings
using the i.MX 95 IOMUX controller DT bindings.

**When to invoke:** When the user needs to change a pin's function (e.g., enable UART4 on
specific pads, configure SPI CS, set GPIO direction), or when bring-up reveals a pin
conflict.

**i.MX 95 IOMUX model:**
- IOMUX controller: `iomuxc` node in DTS
- Pin groups defined as `pinctrl_<peripheral>` sub-nodes
- Property format: `fsl,pins = <MX95_PAD_xxx__FUNC  PAD_CTL_value>;`
- PAD_CTL values: drive strength (DSE), pull (PUE/PUS), slew rate (SRE), open drain (ODE)
- See `references/iomux-bindings.md` for the full property encoding table

**Key files touched:**
- `dt_overlay_dir/imx95-<carrier>-pinmux.dts` (or main overlay)
- `overlay-tracker/` (committed after user approval)

**Validation script:** `scripts/validate_iomux.py` — checks for duplicate pad assignments
across all overlay files.

**Example pinmux node:**
```dts
&iomuxc {
    pinctrl_uart4: uart4grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__LPUART4_TX    0x31e  /* TX: DSE=6, PUE=1, PUS=1 */
            MX95_PAD_GPIO_IO05__LPUART4_RX    0x31e  /* RX: DSE=6, PUE=1, PUS=1 */
        >;
    };
};

&lpuart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart4>;
    status = "okay";
};
```

**STOP checkpoint:** Show `git diff --staged` before committing to overlay-tracker.

---

#### `imx95-customize-usb`

**Purpose:** Configure USB controllers in the device tree overlay. Handles USB3 OTG (via
`usb3` / `dwc3` nodes), USB2 host (via `usbotg2` / `ci_hdrc` nodes), VBUS regulator
assignment, and role switching (host/device/OTG).

**When to invoke:** When enabling or disabling USB ports, changing USB role, adding a VBUS
regulator, or configuring USB for a custom carrier.

**i.MX 95 USB architecture:**
- USB1: USB3.0 OTG (SuperSpeed) — `usb3_0` / `dwc3_0` in DTS
- USB2: USB2.0 Host — `usbotg2` / `ci_hdrc_usb2` in DTS
- PHY: `usb3_phy0` (USB3 SS PHY), `usbphynop1` (USB2 HS PHY)
- See `references/usb-architecture.md` for the full node hierarchy

**Key files touched:**
- `dt_overlay_dir/imx95-<carrier>.dts`
- `overlay-tracker/`

**Example USB3 OTG node:**
```dts
&usb3_0 {
    status = "okay";
};

&usb3_phy0 {
    status = "okay";
};

&dwc3_0 {
    dr_mode = "otg";
    hnp-disable;
    srp-disable;
    adp-disable;
    usb-role-switch;
    status = "okay";
};
```

---

#### `imx95-customize-pcie`

**Purpose:** Configure PCIe controllers in the device tree overlay. Handles PCIe RC (Root
Complex) and EP (Endpoint) mode, link speed (Gen1/Gen2/Gen3), lane count, reference clock
source, and reset GPIO.

**When to invoke:** When enabling PCIe for an M.2 slot, NVMe SSD, Wi-Fi module, or custom
PCIe peripheral on a carrier board.

**i.MX 95 PCIe architecture:**
- PCIe1: `pcie0` node — up to PCIe Gen3 x1
- PCIe2: `pcie1` node — up to PCIe Gen3 x1
- PHY: `pcie_phy0`, `pcie_phy1`
- Reference clock: internal or external (100 MHz REFCLK)
- See `references/procedure.md` for RC vs EP configuration

**Key files touched:**
- `dt_overlay_dir/imx95-<carrier>.dts`
- `overlay-tracker/`

**Key questions asked:**
- PCIe controller (PCIe1 or PCIe2)?
- RC or EP mode?
- Gen1 / Gen2 / Gen3?
- External REFCLK or internal?
- Reset GPIO (pad name and GPIO number)?

---

#### `imx95-customize-camera`

**Purpose:** Configure MIPI-CSI camera pipeline in the device tree overlay. Handles CSI
receiver (`mipi_csi`), ISP pipeline (`isi`), sensor I2C node, MCLK clock, and power/reset
GPIOs.

**When to invoke:** When adding a MIPI-CSI2 camera sensor (e.g., OV5640, IMX219, AR0234) to
a custom carrier or the FRDM expansion header.

**i.MX 95 camera pipeline:**
```
Sensor (I2C) → MIPI CSI-2 RX (mipi_csi0/1) → ISI (Image Sensing Interface) → V4L2
```

**Key questions asked:**
- Sensor model and I2C address
- CSI port (CSI0 or CSI1)
- Number of data lanes (1, 2, or 4)
- MCLK frequency
- Power GPIO (PWDN) and reset GPIO (RESET_N) pad names
- I2C bus number

**Key files touched:**
- `dt_overlay_dir/imx95-<carrier>-camera.dts`
- `overlay-tracker/`

**Templates:** See `references/camera-overlay-templates/` for single-camera and dual-camera
DTS templates.

---

#### `imx95-customize-clocks`

**Purpose:** Modify the clock tree in the device tree overlay. Handles assigned-clocks,
clock-frequency overrides, and enabling/disabling clock consumers for specific peripherals.

**When to invoke:** When a peripheral needs a non-default clock frequency, when enabling a
clock output pin (CLKO1/CLKO2), or when debugging a clock-related boot failure.

**i.MX 95 clock model:**
- Clock controller: `clk` node (CCM — Clock Control Module)
- Peripheral clocks assigned via `assigned-clocks` / `assigned-clock-rates` in DTS
- CLKO1/CLKO2: configurable clock output pads
- See `references/clock-control-model.md` for the CCM hierarchy

**Key files touched:**
- `dt_overlay_dir/imx95-<carrier>.dts`
- `overlay-tracker/`

**NEVER:** Change PLL frequencies or core clock rates without understanding thermal and
power implications. Always ask the user to confirm the target frequency.

---

#### `imx95-customize-power`

**Purpose:** Configure power domains and voltage regulators in the device tree overlay.
Handles PMIC regulator nodes, `power-domains` assignments, and `operating-points-v2` tables.

**When to invoke:** When a custom carrier uses a different PMIC, when adding a new power
rail for a peripheral, or when adjusting voltage/frequency operating points.

**i.MX 95 power model:**
- Power domains: `blk_ctrl_*` nodes (BLK_CTRL_S_AONMIX, BLK_CTRL_NS_AONMIX, etc.)
- PMIC: PCA9450 (FRDM-IMX95 default) — I2C-connected
- Regulators: `reg_<name>` nodes in DTS
- See `references/power-domain-model.md` for the full domain hierarchy

**Key questions asked:**
- PMIC model and I2C address (if different from PCA9450)
- New regulator name, voltage, and GPIO enable pin
- Which peripheral needs the new power domain assignment?

**Key files touched:**
- `dt_overlay_dir/imx95-<carrier>-power.dts`
- `overlay-tracker/`

---

#### `imx95-optimize-memory`

**Purpose:** Tune CMA (Contiguous Memory Allocator) size, DMA-BUF heap pool sizes, and
`reserved-memory` regions in the device tree and kernel bootargs.

**When to invoke:** When the user reports CMA allocation failures, when running
memory-intensive workloads (video encode/decode, ML inference), or when reducing memory
footprint for a constrained application.

**Key parameters:**
- `cma=<size>M` in kernel bootargs (via `chosen` node or U-Boot `bootargs`)
- `reserved-memory` node: `linux,cma` region size
- DMA-BUF heap: `imx-dma-heap` reserved region
- VPU firmware carveout: `vpu_fw` reserved region

**Key files touched:**
- `dt_overlay_dir/imx95-<carrier>-memory.dts`
- `build/conf/local.conf` (if modifying `APPEND_BOOTARGS`)
- `overlay-tracker/`

**Safety:** Never reduce CMA below 320 MB for `imx-image-full` with VPU enabled. See
`references/reserved-memory.md` for minimum safe values per image recipe.

---

### 9.3 Build / Deploy Skills

---

#### `imx95-build-source`

**Purpose:** Run a `bitbake` build for the active target's image recipe. Tracks overlay
changes, verifies the overlay-tracker is clean before building, and reports build results.

**When to invoke:** After any customization, or when the user says "build the image",
"run bitbake", "compile".

**Pre-flight checks (MUST pass before bitbake runs):**
1. `targets/active_target.yaml` exists and is valid.
2. `build/conf/local.conf` has correct `MACHINE` matching the active target.
3. `overlay-tracker/` working tree is clean (`git status` shows no uncommitted changes).
4. Sufficient disk space: ≥ 50 GB free in workspace (full build requires ~40–80 GB).
5. `bitbake` is on PATH (Yocto environment sourced).

**Key commands:**
```bash
# Source environment (if not already sourced in this shell)
cd <workspace_root>/sources/poky
MACHINE=<machine> source oe-init-build-env ../../build

# Build the image
bitbake <image_recipe>

# Build only the kernel (faster, for DT-only changes)
bitbake linux-imx

# Build only the DTB
bitbake linux-imx -c compile -f && bitbake linux-imx -c deploy -f

# Clean a specific recipe
bitbake <recipe> -c cleansstate
```

**Build modes** (from `references/build-modes.md`):

| Mode | Command | When to use |
|---|---|---|
| Full image | `bitbake <image_recipe>` | First build, rootfs changes |
| Kernel only | `bitbake linux-imx` | DT or driver changes |
| DTB only | `bitbake linux-imx -c compile -f` | DT overlay changes only |
| devtool | `devtool modify linux-imx` | Interactive kernel development |

**Post-build:** Artifacts land in `build/tmp/deploy/images/<machine>/`. Run
`imx95-promote-image` next.

---

#### `imx95-promote-image`

**Purpose:** Stage build artifacts from `build/tmp/deploy/images/<machine>/` into the
`staging/` directory, ready for `uuu` flashing. Verifies artifact integrity (checksums)
and records the artifact manifest.

**When to invoke:** After a successful `imx95-build-source`, before `imx95-flash-image`.

**Key artifacts staged:**

| Artifact | Description |
|---|---|
| `imx-boot-<machine>.bin` | Combined boot image (SPL + ATF + U-Boot) |
| `Image` | Kernel image (uncompressed ARM64) |
| `<machine>.dtb` | Compiled device tree blob |
| `<image_recipe>-<machine>.rootfs.ext4` | Root filesystem ext4 image |
| `<image_recipe>-<machine>.rootfs.wic.zst` | Full WIC image (optional) |

**Key files touched:**
- `staging/` (populated)
- `staging/artifact-manifest.json` (written with SHA256 checksums)

**STOP checkpoint:** Show the artifact manifest to the user before proceeding to flash.

---

#### `imx95-flash-image`

**Purpose:** Flash the staged artifacts to the FRDM-IMX95 EVK (or custom board) using `uuu`.
Includes pre-flight hardware checks, recovery mode verification, and a mandatory user
confirmation before any write operation.

**When to invoke:** After `imx95-promote-image`, when the user says "flash the board",
"program eMMC", "write the image".

**Flash tool: `uuu` (Universal Update Utility)**

> ⚠️ **CRITICAL:** This repo uses `uuu`, NOT `flash.sh`. There is no `flash.sh` for i.MX 95.
> If you are looking for `flash.sh`, you are in the wrong BSP. See
> [Section 11](#11-platform-specific-gotchas).

**Pre-flight checklist (ALL must pass before flashing):**

```
[ ] uuu version >= 1.5.21 installed and on PATH
[ ] Board is in USB Serial Download (recovery) mode
    - FRDM-IMX95: set SW1[1:4] = 0000 (USB boot), connect USB-C to J301
[ ] uuu detects the board: `uuu -lsusb` shows VID:PID 1fc9:0146
[ ] staging/ directory exists and artifact-manifest.json is present
[ ] Checksums verified: SHA256 of staged artifacts match manifest
[ ] User has confirmed: "yes, flash the board"
```

**Flash command:**
```bash
# Flash eMMC (FRDM-IMX95 default)
uuu -b emmc_all \
    staging/imx-boot-imx95-19x19-lpddr5-evk.bin \
    staging/<image_recipe>-imx95-19x19-lpddr5-evk.rootfs.wic.zst

# Or use the target's uuu script directly:
uuu <uuu_script_path>
```

**MANDATORY USER CONFIRMATION:**

Before running any `uuu` command that writes to the board, Claude Code MUST display:

```
⚠️  FLASH CONFIRMATION REQUIRED

Target board : <board_name>
Boot device  : <emmc|sd>
uuu script   : <path>
Artifacts    :
  Boot image : <filename> (<sha256>)
  Rootfs     : <filename> (<sha256>)

This will ERASE and REPROGRAM the board's <emmc|sd>.
There is no undo.

Type "flash confirmed" to proceed, or anything else to cancel.
```

Claude Code MUST wait for the user to type exactly **"flash confirmed"** before executing
`uuu`. Any other response cancels the flash.

**Recovery mode instructions** (from `references/recovery-mode.md`):

```
FRDM-IMX95 EVK — Enter USB Serial Download Mode:
1. Power off the board.
2. Set SW1 DIP switches: [1]=OFF [2]=OFF [3]=OFF [4]=OFF  (USB boot)
3. Connect USB-C cable from host to J301 (USB OTG port).
4. Power on the board.
5. Verify: `uuu -lsusb` should show "SDP: 1fc9:0146"
6. After flashing, set SW1 back to eMMC boot: [1]=ON [2]=OFF [3]=OFF [4]=OFF
```

---

#### `imx95-validate-image`

**Purpose:** Run a post-flash validation checklist to confirm the board booted correctly and
key subsystems are functional.

**When to invoke:** After `imx95-flash-image`, when the user says "validate", "check the
board", "did it work?".

**Validation checklist** (from `references/validation-checklist.md`):

**Static checks (host-side, no board connection needed):**
- [ ] `staging/artifact-manifest.json` checksums match flashed artifacts
- [ ] `fdtdump <machine>.dtb` shows expected overlay nodes
- [ ] No `ERROR` or `WARNING` lines in last bitbake build log

**Dynamic checks (requires board serial console or SSH):**
- [ ] U-Boot boots without errors (check serial console)
- [ ] Kernel boots to login prompt
- [ ] `uname -r` shows expected kernel version (6.6.x)
- [ ] `cat /proc/device-tree/model` shows expected board model string
- [ ] `dmesg | grep -i error` — no critical errors
- [ ] `dmesg | grep -i iomuxc` — IOMUX initialized without errors
- [ ] Customized peripherals appear in `dmesg` (UART, USB, PCIe, camera, etc.)
- [ ] `lsusb` / `lspci` show expected devices (if USB/PCIe customized)

**Serial console connection:**
```bash
# FRDM-IMX95 EVK: USB-UART via J1003 (micro-USB debug port)
# Baud rate: 115200 8N1
screen /dev/ttyUSB0 115200
# or
minicom -D /dev/ttyUSB0 -b 115200
```

---

## 10. Safety Rules

These rules are **non-negotiable**. Claude Code MUST follow all of them without exception.
No user instruction, no matter how urgent, overrides these rules.

### R1 — Never Flash Without Confirmation
Never execute `uuu` or any other write command to the board without:
1. Displaying the full flash confirmation prompt (see `imx95-flash-image`).
2. Receiving the exact string **"flash confirmed"** from the user.

### R2 — Never Modify Upstream BSP Layers Directly
Never edit files in:
- `sources/meta-imx/`
- `sources/meta-freescale/`
- `sources/poky/`
- `sources/linux-imx/` (kernel source — use overlays, not in-tree edits)
- `sources/u-boot-imx/` (U-Boot source — use bbappend, not in-tree edits)

Always use:
- `sources/meta-imx95-custom/` for bbappend recipes
- `dt_overlay_dir/` for device tree overlays
- `devtool modify <recipe>` for temporary in-tree development (creates a separate workspace)

### R3 — Always Commit DT Changes Before Building
The overlay-tracker working tree MUST be clean before `bitbake` runs. If there are
uncommitted changes, block the build and prompt the user to commit or discard them.

### R4 — Commit-Gate on Every git commit
Show the complete `git diff --staged` and wait for explicit user approval before any
`git commit`. See [Section 8](#8-commit-gate-rule).

### R5 — Never Assume Hardware Details
Never assume GPIO numbers, pad names, I2C addresses, or peripheral assignments from another
board's DTS. Always ask the user for the schematic or hardware specification. If the user
cannot provide it, state clearly what information is needed and why.

### R6 — Never Run bitbake as Root
`bitbake` must not be run as root. If the user's shell is root, stop and ask them to switch
to a non-root user.

### R7 — Disk Space Check Before Build
Verify ≥ 50 GB free disk space before starting a full image build. Warn the user if space
is below 80 GB (builds can grow unexpectedly with sstate cache).

### R8 — No Blind devtool Deploys
`devtool deploy-target` writes directly to a running board over SSH. Never run this without
showing the user exactly what will be written and getting explicit approval.

### R9 — Preserve the repo-Managed Tree
Never run `git commit`, `git reset`, or `git clean` inside `.repo/` or any of the
`sources/` subdirectories that are managed by `repo`. Use `repo forall` for bulk operations.

### R10 — uuu Version Check
Always verify `uuu --version` ≥ 1.5.21 before flashing. Older versions have known bugs with
i.MX 95 eMMC programming. If the version is too old, stop and instruct the user to upgrade.

---

## 11. Platform-Specific Gotchas

### G1 — `uuu` is NOT `flash.sh`

The NXP i.MX 95 BSP uses **`uuu` (Universal Update Utility)** for flashing. There is no
`flash.sh` script. If you have experience with NVIDIA Jetson, forget `flash.sh` entirely.

```bash
# CORRECT for i.MX 95:
uuu -b emmc_all imx-boot.bin rootfs.wic.zst

# WRONG — does not exist for i.MX 95:
sudo ./flash.sh <target> mmcblk0
```

`uuu` communicates with the i.MX 95 ROM via USB Serial Download Protocol (SDP) when the
board is in recovery mode. It does not require a JTAG debugger.

### G2 — Yocto/bitbake is NOT `make`

The build system is **Yocto/bitbake**, not a kernel Makefile. Common mistakes:

```bash
# WRONG — does not work in Yocto:
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- imx95_defconfig
make ARCH=arm64 -j$(nproc) Image dtbs

# CORRECT — use bitbake:
bitbake linux-imx                          # Build kernel + DTBs
bitbake linux-imx -c menuconfig           # Kernel config
bitbake linux-imx -c compile -f           # Force recompile
bitbake <image_recipe>                    # Full image build
```

### G3 — IOMUX is NOT Tegra Pinmux

The i.MX 95 uses the **IOMUX controller** (IOMUXC), not Tegra's pinmux `.xlsm` spreadsheet
or BCT. There is no `pinmux-dts2cfg.py` or `cfg2pinmux.py`. Pin configuration is done
entirely in DTS using `fsl,pins` properties.

```dts
/* i.MX 95 IOMUX — correct approach */
&iomuxc {
    pinctrl_uart4: uart4grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__LPUART4_TX    0x31e
            MX95_PAD_GPIO_IO05__LPUART4_RX    0x31e
        >;
    };
};

/* NOT Tegra-style — these do not exist for i.MX 95: */
/* nvidia,pins = "uart2_txd_pa0"; */
/* nvidia,function = "uarta"; */
```

MCUXpresso Config Tools can generate IOMUX DT fragments via its GUI, but the agent can
generate them directly from the pad name and function tables in `references/iomux-bindings.md`.

### G4 — Layer Customization via bbappend, Not In-Tree Edits

Never edit `sources/meta-imx/` directly. Use bbappend:

```
# WRONG:
edit sources/meta-imx/recipes-kernel/linux/linux-imx_6.6.bb

# CORRECT:
create sources/meta-imx95-custom/recipes-kernel/linux/linux-imx_%.bbappend
```

### G5 — MACHINE Names Are Exact Strings

The `MACHINE` value in `local.conf` must exactly match a machine configuration file in the
BSP. Common values for i.MX 95:

| MACHINE | Board |
|---|---|
| `imx95-19x19-lpddr5-evk` | i.MX 95 19×19 EVK with LPDDR5 |
| `imx95frdm` | FRDM-IMX95 Freedom board |
| `imx95-15x15-evk` | i.MX 95 15×15 EVK |

See `references/imx95-machines.md` for the full list. A wrong MACHINE value causes bitbake
to fail with a cryptic "no such machine" error.

### G6 — `repo sync` Resets Uncommitted Changes in sources/

Running `repo sync` will reset any uncommitted changes in `sources/` subdirectories. Always
use `meta-imx95-custom/` for customizations, and always commit changes to `overlay-tracker/`
before syncing.

### G7 — DT Overlays vs. In-Tree DTS

The i.MX 95 BSP supports two customization approaches:
1. **In-tree DTS modification** (not recommended — breaks on `repo sync`)
2. **DT overlays** (`.dtbo` files loaded by U-Boot) — recommended for carrier boards
3. **bbappend with `SRC_URI` patch** — for changes that must be in-tree

This skill bundle uses approach 2 (overlays) for all carrier customizations. The overlay
is compiled into a `.dtbo` and loaded by U-Boot via `fdtoverlay` or `fdt apply`.

### G8 — U-Boot Environment for Overlay Loading

To load a DT overlay at boot, the U-Boot environment must be configured:

```
# In U-Boot prompt or via fw_setenv:
setenv fdtoverlays imx95-custom.dtbo
saveenv
```

The `imx95-flash-image` skill handles this automatically when `custom_carrier: true` is set
in the target profile.

### G9 — No tegrastats, No nvpmodel, No JetPack

There is no `tegrastats`, `nvpmodel`, `jtop`, or JetPack on i.MX 95. Power management is
handled via the Linux `cpufreq` subsystem, `devfreq`, and the PMIC driver. Performance
monitoring uses standard Linux tools: `perf`, `top`, `/sys/kernel/debug/`.

### G10 — eMMC Boot Mode Jumpers

After flashing, the FRDM-IMX95 EVK boot mode jumpers MUST be set back to eMMC boot:

```
SW1: [1]=ON [2]=OFF [3]=OFF [4]=OFF   ← eMMC boot (normal operation)
SW1: [1]=OFF [2]=OFF [3]=OFF [4]=OFF  ← USB Serial Download (recovery/flash)
```

Forgetting to restore the jumpers after flashing is the most common reason a board appears
"bricked" after a successful flash.

---

## 12. Running Evals

Each skill has an `evals/evals.json` file with structured test cases. Evals verify that
Claude Code correctly interprets user requests and produces the right skill invocations,
commands, and file outputs.

### Running a Single Skill's Evals

```bash
# From the workspace root (after setup.sh):
python3 .imx95-skills/scripts/run_evals.py \
    --skill imx95-customize-pinmux \
    --verbose
```

### Running All Evals

```bash
python3 .imx95-skills/scripts/run_evals.py --all
```

### Eval Output

```
imx95-customize-pinmux: 8/8 passed (100%)
imx95-flash-image:      6/6 passed (100%)
imx95-build-source:     5/5 passed (100%)
...
Overall: 87/87 passed (100%)
```

### Eval JSON Format

```json
{
  "skill": "imx95-customize-pinmux",
  "version": "1.0",
  "cases": [
    {
      "id": "pinmux-001",
      "description": "Enable UART4 on GPIO_IO04/05",
      "input": "I need to enable UART4 on pads GPIO_IO04 and GPIO_IO05",
      "expected_skill": "imx95-customize-pinmux",
      "expected_commands": ["git diff --staged", "git commit"],
      "expected_files_modified": ["imx95-custom-pinmux.dts"],
      "must_not_do": ["modify sources/meta-imx/", "commit without showing diff"],
      "pass_criteria": "DTS contains MX95_PAD_GPIO_IO04__LPUART4_TX and commit-gate shown"
    }
  ]
}
```

### Adding Eval Cases

Add new cases to `evals/evals.json` in the relevant skill directory. Follow the format above.
Run the eval suite after adding cases to confirm they pass.

---

## 13. Adding a New Skill

To add a new skill to this bundle:

### Step 1 — Create the Skill Directory

```bash
mkdir -p skills/imx95-<new-skill>/{evals,references,scripts}
```

### Step 2 — Write SKILL.md

Use the following template:

```markdown
# imx95-<new-skill>

## Purpose
One paragraph describing what this skill does.

## When to Invoke
- User says "..."
- User asks about "..."

## Pre-conditions
- Active target profile exists (`targets/active_target.yaml`)
- Yocto environment sourced
- [Any other pre-conditions]

## Procedure

### Step 1 — [First step]
...

### STOP — User Approval Required
Show [what] to the user. Wait for explicit approval before proceeding.

### Step 2 — [Second step]
...

## Files Touched
- `<path>` — [what is written/modified]

## Safety Rules Applied
- [List which of R1–R10 apply]

## References
- `references/procedure.md` — detailed procedure
- `references/gotchas.md` — known failure modes
```

### Step 3 — Write BENCHMARK.md

Define pass/fail criteria for the skill. Include:
- What a correct execution looks like
- What constitutes a failure
- Edge cases to test

### Step 4 — Write evals/evals.json

Add at least 3 eval cases covering:
1. The happy path (normal use)
2. An edge case
3. A safety rule enforcement case (e.g., "must show diff before committing")

### Step 5 — Write skill-card.md

One-page human-readable summary. Include: purpose, when to use, key commands, key files.

### Step 6 — Register in CLAUDE.md

Add the new skill to:
1. The [Skills Reference](#9-skills-reference) table (Section 9 quick-reference).
2. The appropriate subsection (Setup / Customize / Build-Deploy).
3. The [Repository Layout](#4-repository-layout) tree (Section 4).

### Step 7 — Run Evals

```bash
python3 .imx95-skills/scripts/run_evals.py --skill imx95-<new-skill>
```

All cases must pass before the skill is considered complete.

---

## 14. Quick Start

For a developer starting from scratch with a FRDM-IMX95 EVK:

### Prerequisites (install on host before starting)

```bash
# Ubuntu 22.04 / 24.04 recommended
sudo apt-get update
sudo apt-get install -y \
    git curl wget python3 python3-pip \
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    libegl1-mesa libsdl1.2-dev pylint xterm python3-subunit mesa-common-dev \
    zstd liblz4-tool file locales libacl1 \
    device-tree-compiler fdtdump

# Install uuu (Universal Update Utility)
# Download from: https://github.com/nxp-imx/mfgtools/releases
# Minimum version: 1.5.21
sudo install -m 755 uuu /usr/local/bin/uuu
uuu --version

# Install repo tool
mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

### Install the Skill Bundle

```bash
git clone https://github.com/<org>/imx95-bsp-skills.git
cd imx95-bsp-skills
./setup.sh --workspace ~/imx95-workspace
```

### Start Claude Code

```bash
cd ~/imx95-workspace
claude
```

### First Prompt

```
help me set up the i.MX 95 BSP workspace for the FRDM-IMX95 EVK
```

Claude Code will invoke `imx95-quick-start` and guide you through:
1. Creating a target profile for the FRDM-IMX95 EVK
2. Downloading the NXP Yocto BSP (~10–20 GB, 30–60 min)
3. Configuring the image recipe (`imx-image-full`)
4. Sourcing the Yocto environment
5. Building the image (`bitbake imx-image-full`, ~2–4 hours first build)
6. Flashing via `uuu`

### Typical Customization Session (after first setup)

```bash
cd ~/imx95-workspace
claude

# Example prompts:
"I need to enable UART4 on GPIO_IO04 and GPIO_IO05 for an RS-485 interface"
→ invokes imx95-customize-pinmux

"Add a MIPI CSI-2 camera on CSI0 with an OV5640 sensor at I2C address 0x3c"
→ invokes imx95-customize-camera

"Build the kernel with the new device tree changes"
→ invokes imx95-build-source

"Flash the board"
→ invokes imx95-promote-image → imx95-flash-image
```

---

## Disclaimer

These skills automate the NXP i.MX 95 Yocto BSP workflow but do not replace NXP official
documentation or engineering review. Always review generated plans, commands, diffs, and
commit messages before accepting them. Flashing can erase device storage or leave a board
temporarily unbootable — keep backups and verify the active target, BSP release, and hardware
setup before any deploy step.

**Official NXP documentation:**
- i.MX 95 Linux BSP Release Notes: https://www.nxp.com/design/software/embedded-software/i-mx-software/embedded-linux-for-i-mx-applications-processors:IMXLINUX
- i.MX 95 Reference Manual: https://www.nxp.com/products/processors-and-microcontrollers/arm-processors/i-mx-applications-processors/i-mx-9-processors/i-mx-95-applications-processor-family:iMX95
- meta-imx source: https://github.com/nxp-imx/meta-imx
- imx-manifest: https://github.com/nxp-imx/imx-manifest
- uuu (mfgtools): https://github.com/nxp-imx/mfgtools

---

*CLAUDE.md version 1.0.0 — imx95-bsp-skills*
*Modeled on the AgentSkills.io convention (ref: NVIDIA jetson-bsp-skills)*
*Platform: NXP i.MX 95 / FRDM-IMX95 EVK / NXP Yocto BSP (meta-imx, Scarthgap)*
