# CLAUDE.md — imx95-bsp-skills

> **Primary ingestion document. Read completely before taking any action in this workspace.**
>
> **Version 2.0 — this is a rewrite, not an edit.** Version 1 was written by an agent with no
> board access and no BSP build. It was fluent and substantially wrong: it named the **i.MX8M**
> PMIC, hardcoded a `MACHINE` string with one supporting reference against 68 for a different one,
> and documented **19 skills, 3 of which do not exist** — along with per-skill `BENCHMARK.md`,
> `skill-card.md` and `references/` directories that exist **zero** times across 16 skills.
>
> If you are looking for something this file describes and cannot find it, **that is now a bug in
> this file** — report it. v1's failure mode was a document describing an aspirational repository.

---

## 0. THE PROVENANCE CONTRACT — this governs everything below

**Read `references/imx95-ground-truth.md` before you write a single constant into a device tree.**
It is the only place this repo is allowed to get a hardware fact from, and every fact in it carries
one of: **[MEASURED]** · **[DERIVED]** · **[SOURCED]** · **[UNVERIFIED]** · **[UNKNOWN]**.

> ### ⭐ THE RULE
> **A skill must never emit a confident-looking artifact for a mechanism nobody has confirmed.**
>
> A generated device-tree overlay is indistinguishable, on the page, from a correct one. It will be
> committed, built (40–80 GB, hours), flashed, and debugged on hardware before anyone questions the
> premise. **For a BSP tool, a plausible wrong answer is more expensive than no answer** — which is
> the opposite of the usual trade-off and is why the rule is this strict here.
>
> **Where the ground truth says [UNKNOWN], the skill ASKS or REFUSES. It does not default.**

---

## 1. What this repo is

`imx95-bsp-skills` runs **entirely on the developer's host machine**. It never SSHes into the board
during build or flash. It guides Claude Code through the NXP Yocto BSP workflow — **Setup →
Customize → Build → Deploy** — for the i.MX 95.

Customization happens **only** through Yocto `bbappend` recipes and kernel device-tree overlays in
your own layer. The upstream layers (`meta-imx`, `meta-freescale`, Poky) are never modified.

Build system is **bitbake**; flash tool is **`uuu`**. There is no `flash.sh`, no L4T, no Tegra BCT.

**Companion repo:** `imx95-device-skills` runs *on* the board. The two share
`references/imx95-ground-truth.md` byte-for-byte — **if you change a hardware fact, change it in
both.**

---

## 2. Target board — the facts that actually matter for a BSP

Full table with tags in `references/imx95-ground-truth.md`. The BSP-relevant subset:

| fact | value | tag |
|---|---|---|
| Board | **FRDM-IMX95-PRO** | [MEASURED] |
| DT `compatible` | **`fsl,frdm-imx95-pro fsl,imx95`** | [MEASURED] |
| DT `model` | **`NXP FRDM-IMX95-PRO`** | [MEASURED] |
| Live DTB on board | **`imx95-19x19-frdm-pro-neutron.dtb`** | [MEASURED] |
| Yocto `MACHINE` | 🔴 **[UNKNOWN] — ASK, DO NOT DEFAULT** | see §7 |
| Kernel on the board | **Linux 6.18** (not 6.6.x) | [MEASURED] |
| PMIC part | **PF09** | [SOURCED] |
| PMIC visibility | **invisible to Linux** (no PMIC regulator driver) | [MEASURED] |
| Clocks | DT-expressed: **24 via `scmi_clk` (SM decides)** + **2 local `vpu-csr` (direct)** | [MEASURED] |
| Board regulators | plain Linux `regulator-fixed`/`-gpio`, **no SM in the path**; SCMI voltage `0x17` not exposed | [MEASURED] |
| Ethernet MAC | **NXP ENETC/NETC** ×3 — *not* Synopsys DWMAC | [MEASURED] |
| I/O expanders | PCAL6416A (i2c-2 @0x20) + PCAL6524 (i2c-3 @0x22) | [MEASURED] |
| Native GPIO domain | **1.8 V**; board I/O 3.3 V | [MEASURED] |
| GPU | Arm **Mali-G310** (not Vivante GC7000UL) | [MEASURED] |
| NPUs | eIQ **Neutron-S** on-SoC **+ Kinara ARA240 on M.2** | [MEASURED] |

> ⚠️ **`compatible` matching:** matching only `fsl,imx95` also matches a **non-FRDM** i.MX95. The
> ARA240 being seated and the neutron DTB being booted are **instance** facts about one physical
> board, not properties of the SoC. Match the full string when the distinction matters.

---

## 3. How skills work — as they actually are on disk

```
skills/<skill-name>/
├── SKILL.md          ← the instruction document. ALWAYS present. Read it completely first.
├── scripts/          ← helper shell scripts. Present for most skills, not all.
└── evals/evals.json  ← present for imx95-quick-start only, today.
```

> **v1 documented `BENCHMARK.md`, `skill-card.md` and a `references/` directory inside every skill.
> There are zero of each, across all 16 skills.** They are not described here because they do not
> exist. Shared reference material lives at the **repo top level** in `references/` and `context/`.

**Invocation protocol:**
1. Read `CLAUDE.md` (this file) → identify the skill.
2. Read `skills/<name>/SKILL.md` **completely** before acting.
3. Follow its procedure; read top-level `references/` files when it directs you to.
4. At every **STOP checkpoint**, show the plan or diff and **wait for explicit approval**.
5. Scripts run on the **host**, never on the board.

---

## 4. Repository layout — verified against disk

```
imx95-bsp-skills/
├── CLAUDE.md
├── README.md
├── LICENSE
├── setup.sh
│
├── references/
│   ├── imx95-ground-truth.md            ← ⭐ THE FACT SHEET. Shared with imx95-device-skills.
│   ├── active_target_template.yaml
│   ├── platform_template.yaml
│   ├── bsp-customization-io-devices.md
│   ├── bsp-customization-iomux-dt.md
│   ├── bsp-customization-kernel-dtb.md
│   └── bsp-platforms-catalogue.md
│
├── context/
│   ├── bsp-customization-software-layers.md
│   ├── bsp-customization-workflow.md
│   └── target-platform-contract.md
│
└── skills/                               ← 16 skills, all with SKILL.md
    ├── imx95-quick-start/                (+ evals/evals.json)
    ├── imx95-init-target/                (+ scripts/)
    ├── imx95-set-target/                 (+ scripts/)
    ├── imx95-download-bsp/               (+ scripts/)
    ├── imx95-init-source/                (+ scripts/)
    ├── imx95-print-bsp-info/             (+ scripts/)
    ├── imx95-derive-carrier/             (+ scripts/)
    ├── imx95-customize-pinmux/           (+ scripts/validate_pinmux.sh)
    ├── imx95-customize-usb/              (+ scripts/check_usb_dt.sh)
    ├── imx95-customize-camera/           (+ scripts/gen_camera_overlay.sh)
    ├── imx95-customize-clocks/           (SKILL.md only)
    ├── imx95-optimize-memory/            (SKILL.md only)
    ├── imx95-build-source/               (+ scripts/)
    ├── imx95-promote-image/              (+ scripts/)
    ├── imx95-flash-image/                (+ scripts/)
    └── imx95-validate-image/             (+ scripts/)
```

**Documented by v1 and NOT PRESENT** — do not attempt to invoke them:
`imx95-init-image` · `imx95-customize-pcie` · **`imx95-customize-power`**

> v1's description of `imx95-customize-power` told the agent to edit **PCA9450** PMIC regulator
> nodes over I²C. That was wrong about the **part and the target** — the PMIC here is PF09 and
> invisible to Linux. It was **not** wrong about the mechanism: the board's rails are plain Linux
> `regulator-fixed`/`regulator-gpio` nodes with ordinary DT authority (§7 Q2, resolved). A rebuilt
> power skill is legitimate — it edits **board fixed/GPIO supplies**, never a PMIC.

---

## 5. Target profile YAML

Every board variant is a profile in `targets/`; the active one is `targets/active_target.yaml`.
Template: `references/platform_template.yaml`.

```yaml
schema_version: "1.0"
profile_name: "frdm-imx95-pro"
description:  "FRDM-IMX95-PRO, eMMC boot"

board:
  name:        "FRDM-IMX95-PRO"        # [MEASURED] DT model: NXP FRDM-IMX95-PRO
  soc:         "imx95"
  boot_device: "emmc"                  # emmc | sd
  custom_carrier: false

yocto:
  machine:       null                  # 🔴 [UNKNOWN] — imx95-init-target MUST ASK.
                                       #    Do NOT default. See §7 Q2.
  image_recipe:  "imx-image-full"
  distro:        "fsl-imx-xwayland"
  bsp_manifest_url: "https://github.com/nxp-imx/imx-manifest"
  bsp_manifest_branch: null            # ask — pin deliberately, don't inherit v1's guess
  bsp_manifest_file:   null

device_tree:
  base_dts:       null                 # ask. Live DTB basename on the board is
                                       # imx95-19x19-frdm-pro[-neutron] [MEASURED],
                                       # but the DTS that produces it is not established.
  overlay_prefix: "imx95-custom"

flash:
  tool:        "uuu"                   # ALWAYS uuu for i.MX95 — never flash.sh
  uuu_script:  null
  usb_vid_pid: null                    # v1 asserted 1fc9:0146 — UNVERIFIED here.
                                       # Read it from `uuu -lsusb` on YOUR board.
```

> **Every `null` above is deliberate.** v1 filled each with a plausible value. A profile that is
> *wrong* is worse than one that is *empty*, because an empty field stops the build immediately and
> a wrong one stops it three hours in, or after a flash.

---

## 6. Overlay-tracker and the commit gate — KEEP THIS, IT WAS THE GOOD PART

v1's safety architecture was genuinely sound and is carried forward unchanged.

**Overlay-tracker:** all DT overlay changes are tracked in a dedicated git repo at
`<workspace>/overlay-tracker/`, separate from the `repo`-managed BSP tree. `repo sync` resets
uncommitted changes in `sources/`; the tracker is where your customizations actually survive.

**Pre-build gate:** `imx95-build-source` blocks if the tracker tree is dirty.

### THE COMMIT GATE — mandatory, no exceptions

Before **any** `git commit` in this workspace, Claude Code MUST:

1. Run `git diff --staged`.
2. Display the **complete** diff — do not summarize, do not truncate.
3. Say: *"Here is the complete diff. Reply 'approve' to commit, or tell me what to change."*
4. **WAIT** for explicit approval.
5. Only then commit.

**MUST NOT:** auto-commit · commit on a vague "ok"/"sure"/"continue" · batch multiple overlay
changes into one commit without showing each · amend without showing the amended diff.

Commit message form:
```
customize(<subsystem>): <one-line summary>

Board: <profile_name>
Skill: imx95-customize-<subsystem>
Files: <changed files>

<what changed and why>

Tested: <pending | passed | not-applicable>
```

---

## 7. 🔴 KNOWN UNKNOWNS — where a skill must ask, not guess

These are tracked in `../agentic-skills-imx/ROADMAP.md` and on the fleet bus.

**Q1 — Yocto `MACHINE` name. [UNKNOWN]**
v1 hardcoded `imx95-19x19-lpddr5-evk` everywhere, including `deploy_dir`. Evidence across the
fleet's i.MX95 repos: `imx95-19x19-frdm-pro` **68 hits** · `imx95-15x15-evk` **45** ·
`imx95-19x19-lpddr5-evk` **1**. The live *DTB basename* is measured; the *Yocto MACHINE that
produces it* is a different string and has not been established.
⇒ **`imx95-init-target` must ask.** A wrong MACHINE fails with a cryptic "no such machine" — which
is the *good* outcome; the bad one is a MACHINE that exists and builds the wrong board.

**Q2 — Power and clocks. ✅ RESOLVED 2026-09-12 — two resources, two answers.**
Measured on the real board by `@95emulator`, reproduced independently (ground truth §6):
- **Clocks: DT is the lever, SCMI carries it, the System Manager decides.** 24 of 26
  `assigned-clocks` nodes reference `scmi_clk`. ⇒ `imx95-customize-clocks` **generates** overlays
  under a **set-and-read-back** contract: report requested vs effective rate, and treat a mismatch
  as an SM denial, not an overlay bug.
- **Regulators: ordinary Linux DT authority.** SCMI voltage protocol `0x17` is not exposed; the
  rails are plain fixed/GPIO supplies. ⇒ a regulator overlay is legitimate and needs no SM caveat.
⚠️ The earlier framing here — "power is owned by the SM, so DT may be the wrong lever" — was too
coarse and would have made both skills wrong in opposite directions.

**Q3 — MIPI-CSI sensors. [UNKNOWN]**
v1 claimed OV5640/OV13858/OV2775/IMX219/IMX477 and hardcoded I²C buses 4 and 5. None confirmed.
⇒ `imx95-customize-camera` must ask for the sensor and its bus. *(Question with `@imx95-media-test`.)*

**Q4 — `uuu` VID:PID and recovery-mode switch settings. [UNVERIFIED]**
v1 gave `1fc9:0146` and a specific SW1 pattern. Plausible, unconfirmed for this board revision.
⇒ `imx95-flash-image` must have the user read `uuu -lsusb` rather than assert a match.

---

## 8. Safety rules — non-negotiable

**R1 — Never flash without the literal confirmation.** `imx95-flash-image` must display the full
confirmation block and receive the exact string **`flash confirmed`**. Anything else cancels.

**R2 — Never modify upstream BSP layers.** Not `sources/meta-imx/`, `meta-freescale/`, `poky/`,
`linux-imx/`, `u-boot-imx/`. Use `meta-imx95-custom/` bbappends and DT overlays, or `devtool modify`.

**R3 — Commit DT changes before building.** Tracker tree clean, or the build is blocked.

**R4 — Commit-gate on every commit.** §6. No exceptions.

**R5 — Never assume hardware details.** Never carry GPIO numbers, pad names, I²C addresses or
peripheral assignments over from another board's DTS — **including from another i.MX part.** That is
the specific error that produced v1. Ask for the schematic. If the user cannot provide it, say what
is needed and why.

**R6 — Never run bitbake as root.**

**R7 — Disk space.** Verify ≥ 50 GB free before a full build; warn below 80 GB.

**R8 — No blind `devtool deploy-target`.** It writes to a running board over SSH. Show exactly what
will be written; get approval.

**R9 — Preserve the repo-managed tree.** No `git commit`/`reset`/`clean` inside `.repo/` or
`repo`-managed `sources/` subdirectories.

**R10 — `uuu` version check.** Verify `uuu --version` before flashing; v1 claimed ≥ 1.5.21 is
required — treat that as [UNVERIFIED] and surface the actual version to the user.

**R11 — NEW: never emit an artifact for an unconfirmed mechanism.** If §7 marks it [UNKNOWN], the
skill asks or refuses. See §0.

---

## 9. Platform gotchas

**G1 — `uuu`, not `flash.sh`.** i.MX95 flashes over USB Serial Download Protocol (SDP) via `uuu`.
No JTAG needed. If you are reaching for `flash.sh`, you are thinking of Jetson.

**G2 — bitbake, not `make`.** `bitbake linux-imx` (kernel + DTBs), `-c menuconfig`, `-c compile -f`.
A bare `make ARCH=arm64 ... imx95_defconfig` does not work here.

**G3 — IOMUX, not Tegra pinmux.** `fsl,pins = <MX95_PAD_xxx__FUNC PAD_CTL>;` in DTS. There is no
`.xlsm` spreadsheet, no BCT, no `pinmux-dts2cfg.py`.

**G4 — bbappend, never in-tree edits.** `repo sync` resets `sources/`.

**G5 — ⭐ CMA AND THE NEUTRON DTB — the most consequential reserved-memory fact on this board.**
The board boots **`imx95-19x19-frdm-pro-neutron.dtb`**, which adds a dedicated **4 GiB
`neutron_memory` `shared-dma-pool`**: `CmaTotal` **960 MiB → 4.94 GiB** [MEASURED].
- **Without it, the ONNX-Runtime Neutron EP cannot initialise at all** — it requests a flat 2 GiB
  contiguous buffer, gets ENOMEM against the stock 960 MiB pool, logs at a severity nobody reads,
  and **silently runs the entire graph on the A55s at a plausible latency.** That single failure is
  why the Neutron was believed "CNN-only" for months.
- It is a **strict improvement**: `linux,cma` stays 960 MiB and memory bandwidth re-measured
  **16.0 GB/s identical** before/after [MEASURED].
- 🔴 **A "restore the stock DTB" cleanup silently breaks the board** into the CNN-only-looking state.
  Never do it as an automated reaper action.
> ⚠️ v1's `imx95-optimize-memory` states `linux,cma: 512 MB` (measured: **960 MiB**), invents a
> "never below 320 MB" floor, and **does not mention `neutron_memory` at all.** Treat every number in
> that skill as unverified until it is rewritten.

**G6 — Clocks and regulators are different animals.** SCMI clocks: set **and read back** — the SM can deny. Board regulators: ordinary DT. See §7 Q2.

**G6a — `find` does not traverse `/proc/device-tree` on this rootfs** (returns 0; `cat` works). Count DT properties under `/sys/firmware/devicetree/base`, and validate the counter against a known-present property first.

**G7 — Ethernet is NXP ENETC/NETC**, not Synopsys DWMAC. DWMAC bindings and workarounds do not apply.
Synopsys IP on this SoC is confined to **PCIe and I3C**.

**G8 — Restore boot-mode switches after flashing.** Forgetting is the most common reason a board
looks bricked after a *successful* flash. Exact switch settings for this board: **[UNVERIFIED]** —
have the user confirm against their board's documentation rather than trusting a remembered pattern.

---

## 10. Evals

Today: `skills/imx95-quick-start/evals/evals.json` only. There is **no `scripts/run_evals.py`** —
v1 documented one and it does not exist.

**When adding evals, prefer tests that run without the board.** The companion repo's
`imx95-npu-benchmark` eval is the model: it feeds synthetic runtime logs to the safety gate and
asserts exit codes, so the property that must never regress is testable on any machine. *A safety
property you can only test on hardware you have to reserve is a safety property nobody tests.*

---

## 11. Adding a skill

1. `mkdir -p skills/imx95-<name>/{scripts,evals}`
2. Write `SKILL.md` — YAML front matter (`name`, `version`, `platform`, `phase`, `invoke_when`,
   `requires_host_tools`, `safe`, `destructive`, `commit_gate`), then Purpose / When to Invoke /
   Pre-conditions / Procedure with **STOP** checkpoints / Files Touched / Safety Rules Applied.
3. **Every hardware constant cites `references/imx95-ground-truth.md`.** If it is not there, add it
   there first — with a tag — or mark it [UNKNOWN] and make the skill ask.
4. Register it in §4 **and** §9's quick-reference. **If you document it here, it must exist.**

---

*imx95-bsp-skills v2.0 · NXP i.MX 95 / FRDM-IMX95-PRO · NXP Yocto BSP*
*Hardware facts: `references/imx95-ground-truth.md`. Milestones: `../agentic-skills-imx/ROADMAP.md`.*
