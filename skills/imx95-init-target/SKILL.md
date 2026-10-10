---

> ⚠️ **Examples in this repo write `<machine>`, not a literal MACHINE name.** They used to show
> `imx95-19x19-lpddr5-evk`, which ground-truth §7 marks **[UNKNOWN]** for this board — 1 supporting
> reference across the fleet against 68 for `imx95-19x19-frdm-pro`. **A usage example is a claim**:
> anyone copy-pasting it inherits the guess, and a MACHINE that exists but names a different board
> builds a plausible image for hardware you do not have. Substitute the value you established from
> **your own** BSP checkout (`conf/machine/*.conf`).
name: imx95-init-target
version: "0.1.0"
platform: imx95-bsp
phase: setup
invoke_when:
  - "create a new target"
  - "add board profile"
  - "new target profile"
  - "create target YAML"
  - "add a new board"
requires_host_tools:
  - git
  - python3
safe: true
destructive: false
commit_gate: false
---

# imx95-init-target

## Purpose

Create a new target profile YAML for a board variant and write it to
`targets/<profile_name>.yaml`. Updates `targets/active_target.yaml` to point to the new
profile. The target profile is the single source of truth for all skills — it defines the
board, MACHINE, paths, image recipe, and flash configuration.

## When to Invoke

- User says "create a new target", "add board profile", "new target profile"
- Called by `imx95-quick-start` during first-time setup
- When adding a second board variant to an existing workspace

## Pre-conditions

- Workspace directory exists (created by `setup.sh`)
- `targets/` directory exists in workspace

## Procedure

### Step 1 — Read the Target Profile Schema

Read `context/target-platform-contract.md` completely before asking any questions.
Read `references/bsp-platforms-catalogue.md` to know valid MACHINE names and board variants.

### Step 2 — Ask Core Questions

If called from `imx95-quick-start`, the answers are already known — use them directly.
Otherwise, ask the user:

**Q1: Board variant**
```
Which board are you targeting?
  1. FRDM-IMX95 EVK (imx95-19x19-lpddr5-evk) ⚠️ [UNVERIFIED — 1 fleet reference; NOT a default]
  2. i.MX95-19x19-LPDDR5-EVK (imx95-19x19-lpddr5-evk)
  3. i.MX95-15x15-EVK (imx95-15x15-evk)
  4. Custom carrier board (based on FRDM-IMX95 SOM)
  5. Other (enter MACHINE name manually)
```

**Q2: Profile name** (suggest a default based on board choice)
```
Profile name (short slug, e.g., "frdm-imx95-base"):
[Default: frdm-imx95-base]
```

**Q3: Image recipe**
```
Image recipe:
  1. imx-image-full [DEFAULT]
  2. imx-image-multimedia
  3. core-image-base
  4. Custom
```

**Q4: Boot device**
```
Boot device:
  1. eMMC [DEFAULT]
  2. SD card
```

**Q5: Workspace path**
```
Workspace root path [~/imx95-workspace]:
```

**Q6: Custom carrier name** (only if Q1 = 4)
```
Custom carrier name (e.g., "acme-carrier-v1"):
```

### Step 3 — Derive All Fields

From the user's answers, derive all fields for the target profile YAML:

| User answer | Derived fields |
|---|---|
| Board = FRDM-IMX95 | `machine = "imx95-19x19-lpddr5-evk"`, `base_dts = "imx95-19x19-lpddr5-evk.dts"` |
| Board = 15x15 EVK | `machine = "imx95-15x15-evk"`, `base_dts = "imx95-15x15-evk.dts"` |
| Boot = eMMC | `uuu_script = "references/uuu-scripts/frdm-imx95-emmc.uuu"` |
| Boot = SD | `uuu_script = "references/uuu-scripts/frdm-imx95-sd.uuu"` |
| Custom carrier | `custom_carrier: true`, `carrier_name = <user input>` |

`deploy_dir` must be set to `build/tmp/deploy/images/<machine>`.

### Step 4 — STOP: Show Generated YAML

Display the **complete generated YAML** to the user before writing anything to disk:

```
Here is the target profile I will create at targets/frdm-imx95-base.yaml:

─────────────────────────────────────────────────────────
schema_version: "1.0"
profile_name: "frdm-imx95-base"
...
─────────────────────────────────────────────────────────

Reply "approve" to write this file, or tell me what to change.
```

**WAIT** for explicit approval before writing any file.

### Step 5 — Write the Target Profile YAML

After approval, write the YAML to `<workspace>/targets/<profile_name>.yaml`.

```bash
# Ensure targets/ directory exists
mkdir -p <workspace>/targets

# Write the profile YAML
cat > <workspace>/targets/<profile_name>.yaml << 'EOF'
<generated YAML content>
EOF
```

### Step 6 — Set as Active Target

Write `<workspace>/targets/active_target.yaml` as a copy of the new profile:

```bash
cp <workspace>/targets/<profile_name>.yaml <workspace>/targets/active_target.yaml
```

Or create a symlink:
```bash
cd <workspace>/targets
ln -sf <profile_name>.yaml active_target.yaml
```

### Step 7 — Confirm

Report success:
```
✓ Created targets/<profile_name>.yaml
✓ Set as active target (targets/active_target.yaml)

Active target: <profile_name>
  Board   : <board_name>
  MACHINE : <machine>
  Image   : <image_recipe>
  Boot    : <boot_device>
```

## Files Touched

- `targets/<profile_name>.yaml` — created
- `targets/active_target.yaml` — updated (copy or symlink)

## Safety Rules Applied

- STOP checkpoint: show complete YAML before writing (prevents wrong config)
- Validate `profile_name` matches `[a-z0-9-]+` pattern
- Validate `machine` is a known i.MX 95 MACHINE value
- Validate `flash.tool` == `"uuu"` (never allow other flash tools)

## References

- `context/target-platform-contract.md` — full schema documentation
- `references/platform_template.yaml` — template with all fields
- `references/bsp-platforms-catalogue.md` — valid MACHINE names
- `scripts/init_target.sh` — shell script for non-interactive creation
